import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/book_conversion.dart';
import '../data/epub_book.dart';
import '../data/pdf_html_builder.dart';
import 'book_html_view.dart';

/// PDF rendered as a reflowed HTML reading view: one chapter per page, with
/// clickable moves and `<chessdiagram>` tiles. Built from the already-loaded
/// [conversion]; chapters are memoised so scrolling doesn't re-resolve moves.
class PdfHtmlView extends ConsumerStatefulWidget {
  const PdfHtmlView({super.key, required this.path, required this.conversion});

  final String path;
  final BookConversion conversion;

  @override
  ConsumerState<PdfHtmlView> createState() => _PdfHtmlViewState();
}

class _PdfHtmlViewState extends ConsumerState<PdfHtmlView> {
  late List<EpubChapter> _chapters = buildPdfChapters(widget.conversion);

  @override
  void didUpdateWidget(PdfHtmlView old) {
    super.didUpdateWidget(old);
    if (!identical(old.conversion, widget.conversion)) {
      _chapters = buildPdfChapters(widget.conversion);
    }
  }

  @override
  Widget build(BuildContext context) {
    return HtmlChapterList(
      path: widget.path,
      chapters: _chapters,
      sourceKeyPrefix: 'pg',
    );
  }
}
