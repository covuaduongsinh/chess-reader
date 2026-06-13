import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../../core/persistence/library_store.dart';
import '../../../core/settings/app_settings.dart';
import '../data/epub_book.dart';
import '../state/book_providers.dart';
import '../state/reader_nav.dart';

/// Parsed EPUB cache, keyed by file path.
final epubBookProvider =
    FutureProvider.family<EpubBook, String>((ref, path) => loadEpubBook(path));

/// EPUB reader: chapters as a scrollable list of HTML with tappable
/// `<chessmove>` spans. Supports jump-to-chapter (TOC/search/bookmarks),
/// resume to the last chapter, and current-chapter tracking.
class EpubBookView extends ConsumerStatefulWidget {
  const EpubBookView({super.key, required this.path});

  final String path;

  @override
  ConsumerState<EpubBookView> createState() => _EpubBookViewState();
}

class _EpubBookViewState extends ConsumerState<EpubBookView> {
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
    // The top-most fully/partly visible chapter is the "current" one.
    final top = positions
        .where((p) => p.itemTrailingEdge > 0)
        .reduce((a, b) => a.itemLeadingEdge < b.itemLeadingEdge ? a : b)
        .index;
    ref.read(currentPageProvider.notifier).set(top + 1);
    ref.read(libraryStoreProvider.notifier).recordPage(widget.path, top + 1);
  }

  @override
  Widget build(BuildContext context) {
    final book = ref.watch(epubBookProvider(widget.path));

    // Honour jump requests from TOC/search/bookmarks.
    ref.listen(epubJumpProvider, (_, target) {
      if (target != null && _itemScroll.isAttached) {
        _itemScroll.scrollTo(
            index: target, duration: const Duration(milliseconds: 300));
        ref.read(epubJumpProvider.notifier).consumed();
      }
    });

    return book.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Could not open EPUB: $e')),
      data: (book) {
        final resume =
            ref.read(libraryStoreProvider.notifier).lastPageFor(widget.path);
        return ScrollablePositionedList.builder(
          itemScrollController: _itemScroll,
          itemPositionsListener: _positions,
          initialScrollIndex:
              resume != null ? (resume - 1).clamp(0, book.chapters.length - 1) : 0,
          itemCount: book.chapters.length,
          itemBuilder: (context, i) =>
              _ChapterView(chapter: book.chapters[i], chapterIndex: i),
        );
      },
    );
  }
}

class _ChapterView extends ConsumerWidget {
  const _ChapterView({required this.chapter, required this.chapterIndex});

  final EpubChapter chapter;
  final int chapterIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeLineProvider);
    final selectedIdx = active != null && active.sourceKey == 'ch$chapterIndex'
        ? active.index
        : -1;
    final highlight = Theme.of(context).colorScheme.primary;
    final textScale = ref.watch(
        settingsProvider.select((s) => s.textScale));

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
            builder: (extensionContext) {
              final idx = int.tryParse(
                      extensionContext.attributes['idx'] ?? '') ??
                  -1;
              final text = extensionContext.element?.text ?? '';
              final selected = idx == selectedIdx;
              return GestureDetector(
                onTap: idx >= 0
                    ? () => ref
                        .read(activeLineProvider.notifier)
                        .select(chapter.moves, idx, 'ch$chapterIndex')
                    : null,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: highlight.withValues(alpha: selected ? 0.25 : 0.08),
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
            tagsToExtend: const {'img'},
            builder: (extensionContext) {
              final src = extensionContext.attributes['src'] ?? '';
              if (!src.startsWith('data:')) return const SizedBox.shrink();
              final comma = src.indexOf(',');
              if (comma < 0 || src.contains('svg')) {
                return const SizedBox.shrink();
              }
              return Image.memory(base64Decode(src.substring(comma + 1)));
            },
          ),
        ],
      ),
    );
  }
}
