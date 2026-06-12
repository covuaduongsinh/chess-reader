import 'package:pdfrx/pdfrx.dart';

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

/// Extracts text from PDF pages, detects chess moves and resolves them into
/// positions. Results are cached per (document, page): extraction is the
/// expensive step and pages are revisited constantly while scrolling.
///
/// v1 resolves each page independently from the initial position (single-game
/// books). Anchor-based contexts arrive in Phase 3.
class PageMovesService {
  final Map<String, Future<PageMovesResult>> _cache = {};

  Future<PageMovesResult> movesForPage(PdfPage page) {
    final key = '${page.document.sourceName}#${page.pageNumber}';
    return _cache.putIfAbsent(key, () => _compute(page));
  }

  Future<PageMovesResult> _compute(PdfPage page) async {
    // PDFium does the heavy lifting in pdfrx's background worker.
    final text = await page.loadStructuredText();
    final tokens = SanTokenizer.tokenize(text.fullText);
    final line = MoveResolver.resolve(tokens);

    final moves = <PageMove>[];
    for (final resolved in line.moves) {
      final bounds = _union(
        text.charRects,
        resolved.token.start,
        resolved.token.end,
      );
      if (bounds != null) {
        moves.add(PageMove(resolved: resolved, bounds: bounds));
      }
    }
    return PageMovesResult(pageNumber: page.pageNumber, moves: moves);
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
