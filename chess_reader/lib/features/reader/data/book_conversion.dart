import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../vision/data/diagram_recognizer.dart';
import 'epub_book.dart';

/// One recognized diagram, ready to place in a page/chapter.
class ConvertedDiagram {
  const ConvertedDiagram({
    required this.fen,
    required this.cropPngBase64,
    required this.left,
    required this.top,
    required this.size,
    required this.anchor,
  });

  /// Detected position.
  final String fen;

  /// Board crop as base64 PNG (embedded into the HTML reading view).
  final String cropPngBase64;

  /// Board region in raster pixels of the rendered page (200 dpi). Used by the
  /// Original-PDF overlay to place a tappable hotspot.
  final int left;
  final int top;
  final int size;

  /// Placement hint: for PDF, the character offset in the page text where the
  /// diagram should be inserted; for EPUB, the occurrence index of the board
  /// `<img>` within the chapter.
  final int anchor;

  Map<String, dynamic> toJson() => {
        'fen': fen,
        'png': cropPngBase64,
        'l': left,
        't': top,
        's': size,
        'a': anchor,
      };

  factory ConvertedDiagram.fromJson(Map<String, dynamic> j) => ConvertedDiagram(
        fen: j['fen'] as String,
        cropPngBase64: j['png'] as String,
        left: j['l'] as int,
        top: j['t'] as int,
        size: j['s'] as int,
        anchor: j['a'] as int,
      );
}

/// One PDF page or EPUB chapter after conversion.
class ConvertedPage {
  const ConvertedPage({
    required this.index,
    this.text,
    this.diagrams = const [],
  });

  /// PDF page number, or EPUB chapter index.
  final int index;

  /// Plain page text (PDF only; used to build the HTML reading view).
  final String? text;

  final List<ConvertedDiagram> diagrams;

  Map<String, dynamic> toJson() => {
        'i': index,
        if (text != null) 'text': text,
        'd': [for (final d in diagrams) d.toJson()],
      };

  factory ConvertedPage.fromJson(Map<String, dynamic> j) => ConvertedPage(
        index: j['i'] as int,
        text: j['text'] as String?,
        diagrams: [
          for (final d in (j['d'] as List? ?? const []))
            ConvertedDiagram.fromJson(d as Map<String, dynamic>)
        ],
      );
}

/// The cached result of detecting diagrams (and, for PDF, extracting text)
/// across a whole book. The slow vision work lives here; move resolution and
/// HTML assembly are recomputed cheaply on open.
class BookConversion {
  const BookConversion({
    required this.title,
    required this.format,
    required this.pages,
    this.sourcePath = '',
  });

  final String title;

  /// 'pdf' or 'epub'.
  final String format;
  final List<ConvertedPage> pages;

  /// Absolute path of the source book (recorded so the converted-books library
  /// can list and reopen cached books).
  final String sourcePath;

  /// Diagrams for a given PDF page number / EPUB chapter index.
  List<ConvertedDiagram> diagramsFor(int index) =>
      pages.firstWhere((p) => p.index == index,
          orElse: () => const ConvertedPage(index: -1)).diagrams;

  static const _version = 2;

  Map<String, dynamic> toJson() => {
        'v': _version,
        'title': title,
        'format': format,
        'sourcePath': sourcePath,
        'pages': [for (final p in pages) p.toJson()],
      };

  factory BookConversion.fromJson(Map<String, dynamic> j) => BookConversion(
        title: j['title'] as String,
        format: j['format'] as String,
        sourcePath: j['sourcePath'] as String? ?? '',
        pages: [
          for (final pg in (j['pages'] as List))
            ConvertedPage.fromJson(pg as Map<String, dynamic>)
        ],
      );
}

/// A converted book on disk: enough to list and reopen it.
class CachedBook {
  const CachedBook(
      {required this.path, required this.title, required this.format});
  final String path;
  final String title;
  final String format;
}

/// Loads a cached conversion if one exists for [path]'s current contents,
/// otherwise runs the conversion and caches it. Reports progress in [0,1].
Future<BookConversion> loadOrConvert(
  String path,
  DiagramRecognizer recognizer, {
  void Function(double progress)? onProgress,
}) async {
  final cached = await _readCache(path);
  if (cached != null) {
    onProgress?.call(1);
    return cached;
  }
  final conversion = path.toLowerCase().endsWith('.epub')
      ? await convertEpub(path, recognizer, onProgress: onProgress)
      : await convertPdf(path, recognizer, onProgress: onProgress);
  await _writeCache(path, conversion);
  return conversion;
}

/// PDF conversion: render each page (200 dpi), recognize diagrams, extract the
/// page text, and compute each diagram's insertion offset into that text.
Future<BookConversion> convertPdf(
  String path,
  DiagramRecognizer recognizer, {
  void Function(double progress)? onProgress,
}) async {
  const scale = 200 / 72; // PDF points (72 dpi) → ~200 dpi raster.
  final doc = await PdfDocument.openFile(path);
  try {
    final pages = <ConvertedPage>[];
    final total = doc.pages.length;
    for (var i = 0; i < total; i++) {
      final page = doc.pages[i];
      final structured = await page.loadStructuredText();
      final text = structured.fullText;

      final image = await page.render(
        fullWidth: page.width * scale,
        fullHeight: page.height * scale,
      );
      final diagrams = <ConvertedDiagram>[];
      if (image != null) {
        final recognized = await recognizer.recognizePage(
          bgra: image.pixels,
          width: image.width,
          height: image.height,
        );
        image.dispose();
        for (final r in recognized) {
          diagrams.add(ConvertedDiagram(
            fen: r.fen,
            cropPngBase64: base64Encode(r.cropPng),
            left: r.left,
            top: r.top,
            size: r.size,
            anchor: _insertOffsetForDiagram(
              charRects: structured.charRects,
              pageHeight: page.height,
              scale: scale,
              diagramTopPx: r.top,
              textLength: text.length,
            ),
          ));
        }
      }
      pages.add(ConvertedPage(
          index: page.pageNumber, text: text, diagrams: diagrams));
      onProgress?.call((i + 1) / total);
    }
    return BookConversion(
      title: p.basenameWithoutExtension(path),
      format: 'pdf',
      sourcePath: path,
      pages: pages,
    );
  } finally {
    doc.dispose();
  }
}

/// EPUB conversion: recognize boards in each chapter's images. Each diagram's
/// [ConvertedDiagram.anchor] is the `<img>` occurrence index within its
/// chapter, so the HTML builder can wrap exactly that image.
Future<BookConversion> convertEpub(
  String path,
  DiagramRecognizer recognizer, {
  void Function(double progress)? onProgress,
}) async {
  final chapterImages = await epubChapterImages(path);
  final pages = <ConvertedPage>[];
  final total = chapterImages.length;
  for (var c = 0; c < total; c++) {
    final images = chapterImages[c];
    final diagrams = <ConvertedDiagram>[];
    for (var j = 0; j < images.length; j++) {
      final bytes = images[j];
      if (bytes == null) continue;
      final recognized = await recognizer.recognizeEncoded(bytes);
      if (recognized.isEmpty) continue;
      final r = recognized.first; // largest board in the image
      diagrams.add(ConvertedDiagram(
        fen: r.fen,
        cropPngBase64: base64Encode(r.cropPng),
        left: r.left,
        top: r.top,
        size: r.size,
        anchor: j,
      ));
    }
    pages.add(ConvertedPage(index: c, diagrams: diagrams));
    onProgress?.call(total == 0 ? 1 : (c + 1) / total);
  }
  return BookConversion(
    title: p.basenameWithoutExtension(path),
    format: 'epub',
    sourcePath: path,
    pages: pages,
  );
}

/// Finds the character offset where a diagram (whose top edge is [diagramTopPx]
/// raster pixels from the page top) should be spliced into the page text:
/// the first character whose vertical centre sits at or below the diagram top.
/// PDF coordinates are bottom-up (larger y = higher on the page).
int _insertOffsetForDiagram({
  required List<PdfRect> charRects,
  required double pageHeight,
  required double scale,
  required int diagramTopPx,
  required int textLength,
}) {
  final diagramTopPdfY = pageHeight - diagramTopPx / scale;
  for (var i = 0; i < charRects.length && i < textLength; i++) {
    final r = charRects[i];
    if (r.width <= 0 && r.height <= 0) continue;
    final centreY = (r.top + r.bottom) / 2;
    if (centreY <= diagramTopPdfY) return i;
  }
  return textLength;
}

/// Whether a cached conversion exists for [path]'s current contents.
Future<bool> hasCachedConversion(String path) async {
  try {
    return (await _cacheFile(path)).existsSync();
  } catch (_) {
    return false;
  }
}

Future<Directory> _cacheDir() async {
  final dir = await getApplicationSupportDirectory();
  final cacheDir = Directory(p.join(dir.path, 'book_cache'));
  if (!cacheDir.existsSync()) cacheDir.createSync(recursive: true);
  return cacheDir;
}

/// Lists every converted book held in the on-disk cache (newest first).
Future<List<CachedBook>> listCachedConversions() async {
  try {
    final dir = await _cacheDir();
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .toList()
      ..sort((a, b) =>
          b.statSync().modified.compareTo(a.statSync().modified));
    final books = <CachedBook>[];
    for (final f in files) {
      try {
        final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
        final source = j['sourcePath'] as String? ?? '';
        if (source.isEmpty) continue; // pre-v2 cache without a source path
        books.add(CachedBook(
          path: source,
          title: j['title'] as String? ?? p.basenameWithoutExtension(source),
          format: j['format'] as String? ?? 'pdf',
        ));
      } catch (_) {
        // Skip corrupt entries.
      }
    }
    return books;
  } catch (_) {
    return const [];
  }
}

/// Deletes the cached conversion for [path] (the source book is untouched).
Future<void> deleteCachedConversion(String path) async {
  try {
    final file = await _cacheFile(path);
    if (file.existsSync()) file.deleteSync();
  } catch (_) {
    // Ignore.
  }
}

// ---- Disk cache ---------------------------------------------------------

Future<File> _cacheFile(String path) async {
  final cacheDir = await _cacheDir();
  final stat = File(path).statSync();
  final base = p
      .basenameWithoutExtension(path)
      .replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
  final key =
      '${base}_${stat.size}_${stat.modified.millisecondsSinceEpoch}_${path.length}';
  return File(p.join(cacheDir.path, '$key.json'));
}

Future<BookConversion?> _readCache(String path) async {
  try {
    final file = await _cacheFile(path);
    if (!file.existsSync()) return null;
    final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    if (json['v'] != BookConversion._version) return null;
    return BookConversion.fromJson(json);
  } catch (_) {
    return null; // Corrupt or unreadable cache: just reconvert.
  }
}

Future<void> _writeCache(String path, BookConversion conversion) async {
  try {
    final file = await _cacheFile(path);
    await file.writeAsString(jsonEncode(conversion.toJson()));
  } catch (_) {
    // Best-effort cache; conversion still returns to the caller.
  }
}
