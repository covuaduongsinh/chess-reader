// Diagnostic: parse an EPUB chess book and report chapters/moves.
// Usage: dart run tool/dump_epub.dart <book.epub> [chapterIndex...]
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:chess_reader/features/reader/data/epub_book.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('usage: dart run tool/dump_epub.dart <book.epub> [ch...]');
    exit(2);
  }
  final book = await loadEpubBook(args[0]);
  print('title: ${book.title}');
  print('chapters: ${book.chapters.length}');
  var total = 0;
  for (var i = 0; i < book.chapters.length; i++) {
    final ch = book.chapters[i];
    total += ch.moves.length;
    print('  [$i] ${ch.title} — ${ch.moves.length} moves');
    if (args.skip(1).contains('$i')) {
      print('      ${ch.moves.take(40).map((m) => m.token.san).join(' ')}');
    }
  }
  print('total resolved moves: $total');
}
