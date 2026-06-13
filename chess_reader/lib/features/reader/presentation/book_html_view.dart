import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../../core/persistence/library_store.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/state/game_session.dart';
import '../data/epub_book.dart';
import '../state/book_providers.dart';
import '../state/reader_nav.dart';

/// A scrollable list of [EpubChapter]s rendered with [ChapterHtml]. Shared by
/// the EPUB reader and the PDF "reading view". Handles resume-to-last,
/// current-chapter tracking, and jump-to-chapter requests (TOC/search/
/// bookmarks) via [epubJumpProvider].
class HtmlChapterList extends ConsumerStatefulWidget {
  const HtmlChapterList({
    super.key,
    required this.path,
    required this.chapters,
    required this.sourceKeyPrefix,
  });

  final String path;
  final List<EpubChapter> chapters;

  /// 'ch' for EPUB chapters, 'pg' for PDF pages.
  final String sourceKeyPrefix;

  @override
  ConsumerState<HtmlChapterList> createState() => _HtmlChapterListState();
}

class _HtmlChapterListState extends ConsumerState<HtmlChapterList> {
  final _itemScroll = ItemScrollController();
  final _positions = ItemPositionsListener.create();

  @override
  void initState() {
    super.initState();
    _positions.itemPositions.addListener(_onScroll);
  }

  @override
  void dispose() {
    _positions.itemPositions.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    final positions = _positions.itemPositions.value;
    if (positions.isEmpty) return;
    final top = positions
        .where((p) => p.itemTrailingEdge > 0)
        .reduce((a, b) => a.itemLeadingEdge < b.itemLeadingEdge ? a : b)
        .index;
    ref.read(currentPageProvider.notifier).set(top + 1);
    ref.read(libraryStoreProvider.notifier).recordPage(widget.path, top + 1);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(epubJumpProvider, (_, target) {
      if (target != null && _itemScroll.isAttached) {
        _itemScroll.scrollTo(
            index: target.clamp(0, widget.chapters.length - 1),
            duration: const Duration(milliseconds: 300));
        ref.read(epubJumpProvider.notifier).consumed();
      }
    });

    final resume =
        ref.read(libraryStoreProvider.notifier).lastPageFor(widget.path);
    return ScrollablePositionedList.builder(
      itemScrollController: _itemScroll,
      itemPositionsListener: _positions,
      initialScrollIndex: resume != null
          ? (resume - 1).clamp(0, widget.chapters.length - 1)
          : 0,
      itemCount: widget.chapters.length,
      itemBuilder: (context, i) => ChapterHtml(
        chapter: widget.chapters[i],
        sourceKey: '${widget.sourceKeyPrefix}$i',
      ),
    );
  }
}

/// Renders one [EpubChapter] (used for both EPUB chapters and PDF "pages" in
/// the HTML reading view) as flutter_html with three custom tags:
/// - `<chessmove idx>` — tappable move that drives the side board;
/// - `<chessdiagram fen>` — a detected board image captioned with its FEN,
///   tappable to load that position onto the side board;
/// - `<img>` — inlined base64 images.
///
/// [sourceKey] scopes move-selection highlighting to this chapter/page.
class ChapterHtml extends ConsumerWidget {
  const ChapterHtml({
    super.key,
    required this.chapter,
    required this.sourceKey,
  });

  final EpubChapter chapter;
  final Object sourceKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeLineProvider);
    final selectedIdx =
        active != null && active.sourceKey == sourceKey ? active.index : -1;
    final highlight = Theme.of(context).colorScheme.primary;
    final textScale =
        ref.watch(settingsProvider.select((s) => s.textScale));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Html(
        data: chapter.html,
        style: {
          'body': Style(fontSize: FontSize(16 * textScale)),
        },
        extensions: [
          TagExtension(
            tagsToExtend: const {'chessmove'},
            builder: (ctx) {
              final idx =
                  int.tryParse(ctx.attributes['idx'] ?? '') ?? -1;
              final text = ctx.element?.text ?? '';
              final selected = idx == selectedIdx;
              return GestureDetector(
                onTap: idx >= 0
                    ? () => ref
                        .read(activeLineProvider.notifier)
                        .select(chapter.moves, idx, sourceKey)
                    : null,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color:
                        highlight.withValues(alpha: selected ? 0.25 : 0.08),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    text,
                    style: TextStyle(
                      color: highlight,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              );
            },
          ),
          TagExtension(
            tagsToExtend: const {'chessdiagram'},
            builder: (ctx) {
              final fen = ctx.attributes['fen'] ?? '';
              final src =
                  ctx.element?.querySelector('img')?.attributes['src'] ?? '';
              return _DiagramTile(fen: fen, src: src);
            },
          ),
          TagExtension(
            tagsToExtend: const {'img'},
            builder: (ctx) {
              final src = ctx.attributes['src'] ?? '';
              final bytes = _decodeDataImage(src);
              return bytes == null
                  ? const SizedBox.shrink()
                  : Image.memory(bytes);
            },
          ),
        ],
      ),
    );
  }
}

/// A detected diagram: the board crop, its FEN, and a tap target that loads
/// the position onto the side board.
class _DiagramTile extends ConsumerWidget {
  const _DiagramTile({required this.fen, required this.src});

  final String fen;
  final String src;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bytes = _decodeDataImage(src);
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Card(
          clipBehavior: Clip.antiAlias,
          margin: const EdgeInsets.symmetric(vertical: 8),
          child: InkWell(
            onTap: () {
              final ok =
                  ref.read(gameSessionProvider.notifier).loadFen(fen);
              if (!ok) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Could not read this diagram reliably')));
              }
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (bytes != null) Image.memory(bytes),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    children: [
                      Icon(Icons.touch_app,
                          size: 16, color: theme.colorScheme.primary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          fen,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Decodes a `data:` image URI to bytes, skipping SVG (unsupported).
Uint8List? _decodeDataImage(String src) {
  if (!src.startsWith('data:') || src.contains('svg')) return null;
  final comma = src.indexOf(',');
  if (comma < 0) return null;
  return base64Decode(src.substring(comma + 1));
}
