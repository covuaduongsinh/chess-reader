import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

import '../data/page_moves_service.dart';
import '../state/book_providers.dart';

/// PDF viewer with clickable chess moves overlaid on each page.
class PdfBookView extends ConsumerWidget {
  const PdfBookView({super.key, required this.path});

  final String path;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PdfViewer.file(
      path,
      params: PdfViewerParams(
        pageOverlaysBuilder: (context, pageRect, page) => [
          _PageMovesOverlay(page: page, pageSize: pageRect.size),
        ],
      ),
    );
  }
}

/// Tap targets for the resolved moves of one page. Children are positioned
/// relative to the page (the viewer wraps overlays in a page-sized Stack).
class _PageMovesOverlay extends ConsumerWidget {
  const _PageMovesOverlay({required this.page, required this.pageSize});

  final PdfPage page;
  final Size pageSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final movesFuture = ref.watch(pageMovesServiceProvider).movesForPage(page);
    final active = ref.watch(activeLineProvider);
    final highlight = Theme.of(context).colorScheme.primary;

    return FutureBuilder<PageMovesResult>(
      future: movesFuture,
      builder: (context, snapshot) {
        final result = snapshot.data;
        if (result == null || result.moves.isEmpty) {
          return const SizedBox.shrink();
        }
        final isActivePage =
            active != null && active.result.pageNumber == result.pageNumber;
        return Stack(
          children: [
            for (var i = 0; i < result.moves.length; i++)
              _moveTarget(
                context,
                ref,
                result,
                i,
                selected: isActivePage && active.index == i,
                highlight: highlight,
              ),
          ],
        );
      },
    );
  }

  Widget _moveTarget(
    BuildContext context,
    WidgetRef ref,
    PageMovesResult result,
    int index, {
    required bool selected,
    required Color highlight,
  }) {
    final move = result.moves[index];
    final rect = move.bounds.toRect(page: page, scaledPageSize: pageSize);
    // Slight padding so the highlight does not hug the glyphs.
    final padded = rect.inflate(1.5);
    return Positioned(
      left: padded.left,
      top: padded.top,
      width: padded.width,
      height: padded.height,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () =>
            ref.read(activeLineProvider.notifier).select(result, index),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: highlight.withValues(alpha: selected ? 0.28 : 0.10),
            borderRadius: BorderRadius.circular(3),
            border: selected ? Border.all(color: highlight, width: 1) : null,
          ),
        ),
      ),
    );
  }
}
