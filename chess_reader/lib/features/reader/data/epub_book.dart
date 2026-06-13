import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import '../../../core/models/move_token.dart';
import '../domain/move_resolver.dart';
import '../domain/san_tokenizer.dart';

/// One spine chapter, preprocessed: every resolved move is wrapped in a
/// `<chessmove idx="...">` element that the view renders as a tappable span.
class EpubChapter {
  const EpubChapter({
    required this.title,
    required this.html,
    required this.moves,
  });

  final String title;

  /// XHTML with `<chessmove>` wrappers and images inlined as data URIs.
  final String html;

  /// Resolved moves of this chapter, indexed by the `idx` attribute.
  final List<ResolvedMove> moves;
}

class EpubBook {
  const EpubBook({required this.title, required this.chapters});

  final String title;
  final List<EpubChapter> chapters;
}

/// Parses an EPUB (zip + XHTML) directly — no third-party EPUB package:
/// we need full DOM access to wrap move tokens, and EPUB's structure
/// (container.xml → OPF manifest/spine) is simple enough to read directly.
Future<EpubBook> loadEpubBook(String path) async {
  final bytes = await File(path).readAsBytes();
  final archive = ZipDecoder().decodeBytes(bytes);

  String readEntry(String name) {
    final file = archive.findFile(name) ??
        archive.findFile(name.replaceAll('\\', '/'));
    if (file == null) {
      throw FormatException('EPUB entry not found: $name');
    }
    return utf8.decode(file.content as List<int>, allowMalformed: true);
  }

  // container.xml points at the OPF package file.
  final container = XmlDocument.parse(readEntry('META-INF/container.xml'));
  final opfPath = container
      .findAllElements('rootfile')
      .first
      .getAttribute('full-path')!;
  final opfDir = p.posix.dirname(opfPath);
  final opf = XmlDocument.parse(readEntry(opfPath));

  final title = opf.findAllElements('dc:title').isNotEmpty
      ? opf.findAllElements('dc:title').first.innerText
      : p.basenameWithoutExtension(path);

  // Manifest: id → href; spine gives reading order.
  final manifest = <String, ({String href, String type})>{};
  for (final item in opf.findAllElements('item')) {
    final id = item.getAttribute('id');
    final href = item.getAttribute('href');
    if (id != null && href != null) {
      manifest[id] =
          (href: href, type: item.getAttribute('media-type') ?? '');
    }
  }
  final spineHrefs = <String>[
    for (final ref in opf.findAllElements('itemref'))
      if (manifest[ref.getAttribute('idref')] case final item?)
        if (item.type.contains('xhtml') || item.type.contains('html'))
          p.posix.normalize(p.posix.join(opfDir, item.href)),
  ];

  // Parse all chapters, collect text + tokens, resolve the whole book as
  // one continuous stream (games span chapters).
  final documents = <dom.Document>[];
  final chapterNodeIndexes = <List<({dom.Text node, int start})>>[];
  final chapterTokens = <List<MoveToken>>[];

  for (final href in spineHrefs) {
    final doc = html_parser.parse(readEntry(href));
    _inlineImages(doc, archive, p.posix.dirname(href));
    final (text, nodeIndex) = _collectText(doc.body);
    documents.add(doc);
    chapterNodeIndexes.add(nodeIndex);
    chapterTokens.add(SanTokenizer.tokenize(text));
  }

  final allTokens = [for (final t in chapterTokens) ...t];
  final line = MoveResolver.resolve(allTokens);
  final resolvedByToken = {for (final r in line.moves) r.token: r};

  final chapters = <EpubChapter>[];
  for (var c = 0; c < documents.length; c++) {
    final moves = <ResolvedMove>[];
    // Wrap from last to first so earlier offsets stay valid.
    final tokensHere = chapterTokens[c]
        .where((t) => resolvedByToken.containsKey(t))
        .toList();
    for (final token in tokensHere) {
      moves.add(resolvedByToken[token]!);
    }
    _wrapTokens(chapterNodeIndexes[c], tokensHere);
    final titleEl = documents[c].querySelector('h1, h2, h3, title');
    chapters.add(EpubChapter(
      title: titleEl?.text.trim().isNotEmpty == true
          ? titleEl!.text.trim()
          : 'Chapter ${c + 1}',
      html: documents[c].body?.innerHtml ?? '',
      moves: moves,
    ));
  }
  return EpubBook(title: title, chapters: chapters);
}

/// Concatenates the text nodes under [root] (skipping scripts/styles) and
/// records each node's start offset in the combined string.
const _blockTags = {'p', 'div', 'br', 'h1', 'h2', 'h3', 'li', 'td'};

(String, List<({dom.Text node, int start})>) _collectText(dom.Element? root) {
  final buffer = StringBuffer();
  final index = <({dom.Text node, int start})>[];
  void walk(dom.Node node) {
    if (node is dom.Text) {
      index.add((node: node, start: buffer.length));
      buffer.write(node.text);
      return;
    }
    if (node is dom.Element &&
        (node.localName == 'script' || node.localName == 'style')) {
      return;
    }
    for (final child in node.nodes) {
      walk(child);
    }
    // Block boundaries separate text so moves cannot span paragraphs.
    if (node is dom.Element && _blockTags.contains(node.localName)) {
      buffer.write('\n');
    }
  }

  if (root != null) walk(root);
  return (buffer.toString(), index);
}

/// Replaces each token's text with a `<chessmove idx="...">` element.
/// A text node usually carries several moves ("1.e4 e5 2.Nf3"), so each
/// node is rebuilt once with all its tokens. Tokens spanning nodes are left
/// unwrapped (rare; they stay plain text).
void _wrapTokens(
  List<({dom.Text node, int start})> nodeIndex,
  List<MoveToken> tokens,
) {
  // Group token list indices (= the `idx` attribute) by owning text node.
  final byNode = <int, List<int>>{};
  for (var t = 0; t < tokens.length; t++) {
    for (var n = 0; n < nodeIndex.length; n++) {
      final entry = nodeIndex[n];
      final nodeEnd = entry.start + entry.node.text.length;
      if (tokens[t].start >= entry.start && tokens[t].end <= nodeEnd) {
        byNode.putIfAbsent(n, () => []).add(t);
        break;
      }
    }
  }

  byNode.forEach((n, tokenIndices) {
    final entry = nodeIndex[n];
    final node = entry.node;
    final parent = node.parentNode;
    if (parent == null) return;
    final text = node.text;

    final replacement = <dom.Node>[];
    var cursor = 0;
    for (final t in tokenIndices) {
      final localStart = tokens[t].start - entry.start;
      final localEnd = tokens[t].end - entry.start;
      if (localStart > cursor) {
        replacement.add(dom.Text(text.substring(cursor, localStart)));
      }
      replacement.add(dom.Element.tag('chessmove')
        ..attributes['idx'] = '$t'
        ..append(dom.Text(text.substring(localStart, localEnd))));
      cursor = localEnd;
    }
    if (cursor < text.length) {
      replacement.add(dom.Text(text.substring(cursor)));
    }

    final insertAt = parent.nodes.indexOf(node);
    parent.nodes.removeAt(insertAt);
    parent.nodes.insertAll(insertAt, replacement);
  });
}

/// Replaces `<img src>` with base64 data URIs so chapters are
/// self-contained (the view decodes them without zip access).
void _inlineImages(dom.Document doc, Archive archive, String baseDir) {
  for (final img in doc.querySelectorAll('img')) {
    final src = img.attributes['src'];
    if (src == null || src.startsWith('data:')) continue;
    final entryPath = p.posix.normalize(p.posix.join(baseDir, src));
    final file = archive.findFile(entryPath);
    if (file == null) continue;
    final data = file.content as List<int>;
    final ext = p.extension(src).toLowerCase();
    final mime = switch (ext) {
      '.png' => 'image/png',
      '.gif' => 'image/gif',
      '.svg' => 'image/svg+xml',
      _ => 'image/jpeg',
    };
    img.attributes['src'] =
        'data:$mime;base64,${base64Encode(Uint8List.fromList(data))}';
  }
}
