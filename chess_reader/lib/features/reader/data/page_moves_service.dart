import 'package:pdfrx/pdfrx.dart';

import '../../../core/models/move_token.dart';
import '../domain/move_resolver.dart';
import '../domain/san_tokenizer.dart';

/// A resolved move on a PDF page together with the bounding box of its
/// printed text, in PDF page coordinates (origin bottom-left).
class PageMove {
  const PageMove({required this.resolved, required this.bounds});

  final ResolvedMove resolved;
  final PdfRect bounds;
}

class PageMovesResult {
  const PageMovesResult({required this.pageNumber, required this.moves});

  final int pageNumber;
  final List<PageMove> moves;

  static const empty = PageMovesResult(pageNumber: 0, moves: []);
}

/// Detects and resolves chess moves for a whole book.
///
/// Chess games span pages (a page often starts at move 26), so resolution
/// must be continuous: the entire book is tokenized and resolved as one
/// stream, then split back into per-page results. This happens once per
/// book, asynchronously, and is cached; pages render immediately and the
/// overlays appear when the pass completes.
class PageMovesService {
  final Map<String, Future<List<PageMovesResult>>> _cache = {};

  Future<PageMovesResult> movesForPage(PdfPage page) async {
    final all = await _resolveBook(page.document);
    final index = page.pageNumber - 1;
    return index < all.length ? all[index] : PageMovesResult.empty;
  }

  Future<List<PageMovesResult>> _resolveBook(PdfDocument document) {
    return _cache.putIfAbsent(
      document.sourceName,
      () => _compute(document),
    );
  }

  Future<List<PageMovesResult>> _compute(PdfDocument document) async {
    // Extract and tokenize page by page (PDFium runs in pdfrx's background
    // worker), keeping per-page tokens and char boxes.
    final pageTokens = <List<MoveToken>>[];
    final pageRects = <List<PdfRect>>[];
    for (final page in document.pages) {
      final text = await page.loadStructuredText();
      pageTokens.add(SanTokenizer.tokenize(text.fullText));
      pageRects.add(text.charRects);
    }

    // Resolve the whole book as one continuous stream.
    final allTokens = [for (final tokens in pageTokens) ...tokens];
    final line = MoveResolver.resolve(allTokens);
    final resolvedByToken = {
      for (final r in line.moves) r.token: r,
    };

    final results = <PageMovesResult>[];
    for (var p = 0; p < pageTokens.length; p++) {
      final moves = <PageMove>[];
      for (final token in pageTokens[p]) {
        final resolved = resolvedByToken[token];
        if (resolved == null) continue;
        final bounds = _union(pageRects[p], token.start, token.end);
        if (bounds != null) {
          moves.add(PageMove(resolved: resolved, bounds: bounds));
        }
      }
      results.add(PageMovesResult(pageNumber: p + 1, moves: moves));
    }
    return results;
  }

  /// Union of the character boxes for fullText[start..end). PDF coordinates
  /// are bottom-up: top is the larger y.
  PdfRect? _union(List<PdfRect> charRects, int start, int end) {
    PdfRect? result;
    for (var i = start; i < end && i < charRects.length; i++) {
      final r = charRects[i];
      if (r.width <= 0 && r.height <= 0) continue;
      result = result == null
          ? r
          : PdfRect(
              result.left < r.left ? result.left : r.left,
              result.top > r.top ? result.top : r.top,
              result.right > r.right ? result.right : r.right,
              result.bottom < r.bottom ? result.bottom : r.bottom,
            );
    }
    return result;
  }
}
