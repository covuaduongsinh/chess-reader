import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../../core/persistence/library_store.dart';
import '../../search/book_search.dart';
import '../state/book_providers.dart';
import '../state/reader_nav.dart';
import 'epub_book_view.dart';

/// Side panel for in-book navigation: table of contents, full-text search,
/// and bookmarks. Works for both PDF and EPUB.
class ReaderDrawer extends ConsumerWidget {
  const ReaderDrawer({super.key, required this.path});

  final String path;

  bool get _isEpub => path.toLowerCase().endsWith('.epub');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Drawer(
      width: 360,
      child: DefaultTabController(
        length: 3,
        child: Column(
          children: [
            const SafeArea(
              bottom: false,
              child: TabBar(tabs: [
                Tab(icon: Icon(Icons.list), text: 'Contents'),
                Tab(icon: Icon(Icons.search), text: 'Search'),
                Tab(icon: Icon(Icons.bookmark), text: 'Bookmarks'),
              ]),
            ),
            Expanded(
              child: TabBarView(children: [
                _isEpub ? _EpubToc(path: path) : _PdfToc(),
                _SearchTab(),
                _BookmarksTab(path: path),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

void _jump(WidgetRef ref, BuildContext context, bool isEpub, int page) {
  if (isEpub) {
    ref.read(epubJumpProvider.notifier).requestChapter(page - 1);
  } else {
    ref.read(pdfControllerProvider.notifier).goToPage(page);
  }
  Navigator.of(context).maybePop();
}

class _PdfToc extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(pdfControllerProvider);
    if (controller == null || !controller.isReady) {
      return const Center(child: Text('Loading…'));
    }
    return FutureBuilder<List<PdfOutlineNode>>(
      future: controller.document.loadOutline(),
      builder: (context, snapshot) {
        final outline = snapshot.data;
        if (outline == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (outline.isEmpty) {
          return const Center(child: Text('No table of contents'));
        }
        final tiles = <Widget>[];
        void walk(List<PdfOutlineNode> nodes, int depth) {
          for (final n in nodes) {
            tiles.add(ListTile(
              dense: true,
              contentPadding: EdgeInsets.only(left: 16.0 + depth * 16, right: 16),
              title: Text(n.title, maxLines: 2, overflow: TextOverflow.ellipsis),
              onTap: n.dest != null
                  ? () => _jump(ref, context, false, n.dest!.pageNumber)
                  : null,
            ));
            walk(n.children, depth + 1);
          }
        }

        walk(outline, 0);
        return ListView(children: tiles);
      },
    );
  }
}

class _EpubToc extends ConsumerWidget {
  const _EpubToc({required this.path});
  final String path;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final book = ref.watch(epubBookProvider(path));
    return book.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (book) => ListView.builder(
        itemCount: book.chapters.length,
        itemBuilder: (context, i) => ListTile(
          dense: true,
          title: Text(book.chapters[i].title,
              maxLines: 2, overflow: TextOverflow.ellipsis),
          onTap: () => _jump(ref, context, true, i + 1),
        ),
      ),
    );
  }
}

class _SearchTab extends ConsumerStatefulWidget {
  @override
  ConsumerState<_SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends ConsumerState<_SearchTab> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final search = ref.watch(bookSearchProvider);
    final isEpub = ref
        .read(openedBookProvider)!
        .toLowerCase()
        .endsWith('.epub');
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: TextField(
            controller: _controller,
            decoration: InputDecoration(
              hintText: 'Search text or moves (e.g. Nf3)',
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () {
                  _controller.clear();
                  ref.read(bookSearchProvider.notifier).clear();
                },
              ),
            ),
            onSubmitted: (q) =>
                ref.read(bookSearchProvider.notifier).search(q),
          ),
        ),
        if (search.searching) const LinearProgressIndicator(),
        Expanded(
          child: search.hits.isEmpty
              ? Center(
                  child: Text(search.query.isEmpty
                      ? 'Type to search'
                      : search.searching
                          ? 'Searching…'
                          : 'No matches'))
              : ListView.builder(
                  itemCount: search.hits.length,
                  itemBuilder: (context, i) {
                    final hit = search.hits[i];
                    return ListTile(
                      dense: true,
                      leading: Text(isEpub ? 'Ch ${hit.page}' : 'p${hit.page}'),
                      title: Text(hit.snippet,
                          maxLines: 3, overflow: TextOverflow.ellipsis),
                      onTap: () => _jump(ref, context, isEpub, hit.page),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

Future<String?> _askNote(BuildContext context, String where) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Bookmark $where'),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'Note (optional)',
          border: OutlineInputBorder(),
        ),
        onSubmitted: (v) => Navigator.of(context).pop(v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(controller.text.trim()),
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

class _BookmarksTab extends ConsumerWidget {
  const _BookmarksTab({required this.path});
  final String path;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(libraryStoreProvider);
    final store = ref.read(libraryStoreProvider.notifier);
    final bookmarks = store.bookmarksFor(path);
    final isEpub = path.toLowerCase().endsWith('.epub');

    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.add),
          title: const Text('Bookmark current location'),
          subtitle: const Text('Optionally add a note'),
          onTap: () async {
            final page = ref.read(currentPageProvider);
            final where = isEpub ? 'Chapter $page' : 'Page $page';
            final note = await _askNote(context, where);
            if (note == null) return;
            store.addBookmark(
              path,
              Bookmark(page: page, label: note.isEmpty ? where : '$where — $note'),
            );
          },
        ),
        const Divider(height: 1),
        Expanded(
          child: bookmarks.isEmpty
              ? const Center(child: Text('No bookmarks yet'))
              : ListView.builder(
                  itemCount: bookmarks.length,
                  itemBuilder: (context, i) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.bookmark),
                    title: Text(bookmarks[i].label),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => store.removeBookmark(path, i),
                    ),
                    onTap: () =>
                        _jump(ref, context, isEpub, bookmarks[i].page),
                  ),
                ),
        ),
      ],
    );
  }
}
