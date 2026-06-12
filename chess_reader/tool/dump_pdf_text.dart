// Diagnostic: dump text extraction from a chess book PDF.
//
// Reports per-page text samples, a histogram of non-ASCII codepoints (to
// discover how the book's figurine font extracts), and tokenizer/resolver
// hit counts across the whole book.
//
// Usage: dart run tool/dump_pdf_text.dart <book.pdf> [samplePage...]
import 'dart:io';

import 'package:chess_reader/features/reader/domain/move_resolver.dart';
import 'package:chess_reader/features/reader/domain/san_tokenizer.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('usage: dart run tool/dump_pdf_text.dart <book.pdf> [page...]');
    exit(2);
  }
  await pdfrxInitialize();
  final doc = await PdfDocument.openFile(args[0]);
  print('pages: ${doc.pages.length}');

  final samplePages = args.skip(1).map(int.parse).toList();
  final codepoints = <int, int>{};
  var totalTokens = 0;
  var totalResolved = 0;
  var pagesWithMoves = 0;

  for (final page in doc.pages) {
    final text = await page.loadStructuredText();
    final full = text.fullText;
    for (final code in full.codeUnits) {
      if (code >= 0x80) {
        codepoints[code] = (codepoints[code] ?? 0) + 1;
      }
    }
    final tokens = SanTokenizer.tokenize(full);
    final line = MoveResolver.resolve(tokens);
    totalTokens += tokens.length;
    totalResolved += line.moves.length;
    if (line.moves.isNotEmpty) pagesWithMoves++;

    if (samplePages.contains(page.pageNumber)) {
      print('=== page ${page.pageNumber} '
          '(tokens: ${tokens.length}, resolved: ${line.moves.length}) ===');
      print(full.length > 1500 ? full.substring(0, 1500) : full);
      print('--- resolved sans: '
          '${line.moves.take(30).map((m) => m.token.san).join(' ')}');
    }
  }

  print('');
  print('total tokens: $totalTokens, resolved: $totalResolved, '
      'pages with resolved moves: $pagesWithMoves/${doc.pages.length}');
  print('non-ASCII codepoints (top 40):');
  final sorted = codepoints.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  for (final e in sorted.take(40)) {
    final char = String.fromCharCode(e.key);
    print('  U+${e.key.toRadixString(16).toUpperCase().padLeft(4, '0')} '
        '"$char" x${e.value}');
  }
  doc.dispose();
}
