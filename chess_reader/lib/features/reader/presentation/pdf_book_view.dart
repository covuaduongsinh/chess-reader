import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../../core/persistence/library_store.dart';
import '../../../core/state/game_session.dart';
import '../../vision/state/diagram_provider.dart';
import '../data/page_moves_service.dart';
import '../state/book_providers.dart';
import '../state/reader_nav.dart';

/// PDF viewer with clickable chess moves overlaid on each page. Attaches its
/// controller to [pdfControllerProvider], resumes at the last-read page, and
/// records page changes for resume + bookmark labelling.
class PdfBookView extends ConsumerStatefulWidget {
  const PdfBookView({super.key, required this.path});

  final String path;

  @override
  ConsumerState<PdfBookView> createState() => _PdfBookViewState();
}

class _PdfBookViewState extends ConsumerState<PdfBookView> {
  final _controller = PdfViewerController();

  @override
  void dispose() {
    ref.read(pdfControllerProvider.notifier).detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final resumePage =
        ref.read(libraryStoreProvider.notifier).lastPageFor(widget.path) ?? 1;
    return PdfViewer.file(
      widget.path,
      controller: _controller,
      initialPageNumber: resumePage,
      params: PdfViewerParams(
        onViewerReady: (document, controller) {
          ref.read(pdfControllerProvider.notifier).attach(_controller);
        },
        onPageChanged: (pageNumber) {
          if (pageNumber == null) return;
          ref.read(currentPageProvider.notifier).set(pageNumber);
          ref.read(libraryStoreProvider.notifier)
              .recordPage(widget.path, pageNumber);
        },
        pageOverlaysBuilder: (context, pageRect, page) => [
          _PageMovesOverlay(page: page, pageSize: pageRect.size),
          _DiagramAnchorsOverlay(page: page, pageSize: pageRect.size),
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
            active != null && active.sourceKey == result.pageNumber;
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
        onTap: () => ref.read(activeLineProvider.notifier).select(
            [for (final m in result.moves) m.resolved],
            index,
            result.pageNumber),
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

/// Diagram-recognition layer: a scan button per page; after scanning,
/// recognized diagrams get a tappable chip that anchors the board to the
/// printed position.
class _DiagramAnchorsOverlay extends ConsumerWidget {
  const _DiagramAnchorsOverlay({required this.page, required this.pageSize});

  final PdfPage page;
  final Size pageSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(diagramScansProvider);
    final scans = ref.read(diagramScansProvider.notifier);
    final results = scans.resultsFor(page);
    final scanning = scans.isScanning(page);

    // Raster pixels (200 dpi) → page-widget coordinates.
    final toWidget = pageSize.width / (page.width * 200 / 72);

    return Stack(
      children: [
        Positioned(
          top: 4,
          right: 4,
          child: scanning
              ? const Padding(
                  padding: EdgeInsets.all(8),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : results == null
                  ? IconButton.filledTonal(
                      tooltip: 'Scan page for diagrams',
                      iconSize: 18,
                      icon: const Icon(Icons.center_focus_strong),
                      onPressed: () => scans.scan(page),
                    )
                  : const SizedBox.shrink(),
        ),
        if (results != null)
          for (final r in results)
            Positioned(
              left: r.left * toWidget,
              top: r.top * toWidget - 14,
              child: ActionChip(
                visualDensity: VisualDensity.compact,
                avatar: const Icon(Icons.push_pin, size: 14),
                label: const Text('Set board'),
                onPressed: () {
                  try {
                    final position =
                        Chess.fromSetup(Setup.parseFen(r.fen));
                    ref
                        .read(gameSessionProvider.notifier)
                        .setPosition(position);
                  } on Exception {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content:
                            Text('Could not read this diagram reliably')));
                  }
                },
              ),
            ),
      ],
    );
  }
}
