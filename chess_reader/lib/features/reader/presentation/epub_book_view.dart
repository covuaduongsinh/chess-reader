import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/epub_book.dart';
import '../state/book_providers.dart';

/// Parsed EPUB cache, keyed by file path.
final epubBookProvider =
    FutureProvider.family<EpubBook, String>((ref, path) => loadEpubBook(path));

/// EPUB reader: chapters as scrollable HTML with tappable `<chessmove>`
/// spans wired to the shared game session.
class EpubBookView extends ConsumerWidget {
  const EpubBookView({super.key, required this.path});

  final String path;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final book = ref.watch(epubBookProvider(path));
    return book.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Could not open EPUB: $e')),
      data: (book) => ListView.builder(
        itemCount: book.chapters.length,
        itemBuilder: (context, i) =>
            _ChapterView(chapter: book.chapters[i], chapterIndex: i),
      ),
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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Html(
        data: chapter.html,
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
