import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

/// Holds the live PDF viewer controller so TOC, search, bookmarks and
/// auto-resume can drive page jumps from anywhere. Null when no PDF is open.
final pdfControllerProvider =
    NotifierProvider<PdfControllerHolder, PdfViewerController?>(
        PdfControllerHolder.new);

class PdfControllerHolder extends Notifier<PdfViewerController?> {
  @override
  PdfViewerController? build() => null;

  void attach(PdfViewerController controller) => state = controller;
  void detach() => state = null;

  void goToPage(int pageNumber) {
    final c = state;
    if (c != null && c.isReady) {
      c.goToPage(pageNumber: pageNumber);
    }
  }
}

/// For EPUB: a jump request (chapter index) the chapter list listens to.
/// EPUB has no page controller, so jumps are expressed as a target chapter
/// that [EpubBookView] scrolls to.
final epubJumpProvider =
    NotifierProvider<EpubJump, int?>(EpubJump.new);

class EpubJump extends Notifier<int?> {
  @override
  int? build() => null;

  void requestChapter(int index) => state = index;
  void consumed() => state = null;
}

/// Current 1-based page (PDF) or chapter index + 1 (EPUB) for the open book,
/// used to label new bookmarks and to persist the resume point.
final currentPageProvider = NotifierProvider<CurrentPage, int>(CurrentPage.new);

class CurrentPage extends Notifier<int> {
  @override
  int build() => 1;

  void set(int page) => state = page;
}

/// Scroll controller for the EPUB list view (exposed so jumps work).
final epubScrollProvider = Provider<ScrollController>((ref) {
  final c = ScrollController();
  ref.onDispose(c.dispose);
  return c;
});
