import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/persistence/library_store.dart';
import '../../../core/settings/app_settings.dart';
import '../../board/board_panel.dart';
import '../../library/about.dart';
import '../../library/converted_library_screen.dart';
import '../../library/library_home.dart';
import '../../library/open_book_button.dart';
import '../../settings/settings_screen.dart';
import '../data/book_exporter.dart';
import '../data/epub_book.dart';
import '../data/pdf_html_builder.dart';
import '../state/book_providers.dart';
import '../state/conversion_provider.dart';
import 'epub_book_view.dart';
import 'move_strip.dart';
import 'pdf_book_view.dart';
import 'pdf_html_view.dart';
import 'reader_drawer.dart';

bool _isEpub(String path) => path.toLowerCase().endsWith('.epub');

/// Main screen: a library home until a book is opened, then the book pane and
/// board (side-by-side on wide layouts, a toggleable board panel on phones).
class ReaderScreen extends ConsumerStatefulWidget {
  const ReaderScreen({super.key});

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen> {
  bool _boardVisibleNarrow = true;
  String? _promptedPath;

  /// On opening a PDF with no saved preference, ask how to read it.
  void _maybePromptView(String path) {
    if (_isEpub(path) || _promptedPath == path) return;
    if (ref.read(libraryStoreProvider).viewMode[path] != null) return;
    _promptedPath = path;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final mode = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('How would you like to read this PDF?'),
          content: const Text(
            'Original pages keep the book exactly as printed.\n\n'
            'Reading view reflows the text so it is easier on small screens; '
            'layout and fonts are approximate.\n\n'
            'You can switch anytime from the toolbar.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop('pdf'),
              child: const Text('Original pages'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop('html'),
              child: const Text('Reading view'),
            ),
          ],
        ),
      );
      ref.read(libraryStoreProvider.notifier).setViewMode(path, mode ?? 'pdf');
    });
  }

  Future<void> _exportConverted(String path) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
        const SnackBar(content: Text('Preparing export…')));
    try {
      final conversion = await ref.read(conversionProvider(path).future);
      final chapters = _isEpub(path)
          ? (await loadEpubBook(path, diagrams: conversion)).chapters
          : buildPdfChapters(conversion);
      final html =
          buildExportHtml(p.basenameWithoutExtension(path), chapters);
      final location = await getSaveLocation(
        suggestedName: '${p.basenameWithoutExtension(path)}.html',
        acceptedTypeGroups: const [
          XTypeGroup(label: 'HTML', extensions: ['html']),
        ],
      );
      if (location == null) return;
      await File(location.path).writeAsString(html);
      messenger.showSnackBar(
          SnackBar(content: Text('Exported to ${location.path}')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Export failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bookPath = ref.watch(openedBookProvider);
    if (bookPath != null) _maybePromptView(bookPath);
    final showViewToggle = bookPath != null && !_isEpub(bookPath);

    return Scaffold(
      endDrawer: bookPath != null ? ReaderDrawer(path: bookPath) : null,
      appBar: AppBar(
        title: const Text('Chess Reader'),
        actions: [
          if (showViewToggle) _ViewToggle(path: bookPath),
          OpenBookButton(tooltip: bookPath == null ? null : 'Open another book'),
          if (bookPath != null)
            IconButton(
              tooltip: 'Close book',
              icon: const Icon(Icons.close),
              onPressed: () =>
                  ref.read(openedBookProvider.notifier).close(),
            ),
          if (bookPath != null)
            Builder(
              builder: (context) => IconButton(
                tooltip: 'Contents, search, bookmarks',
                icon: const Icon(Icons.menu_open),
                onPressed: () => Scaffold.of(context).openEndDrawer(),
              ),
            ),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'export':
                  if (bookPath != null) _exportConverted(bookPath);
                case 'library':
                  Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const ConvertedLibraryScreen()));
                case 'settings':
                  Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const SettingsScreen()));
                case 'about':
                  showAppAboutDialog(context);
              }
            },
            itemBuilder: (context) => [
              if (bookPath != null)
                const PopupMenuItem(
                  value: 'export',
                  child: ListTile(
                    leading: Icon(Icons.download),
                    title: Text('Export converted HTML…'),
                  ),
                ),
              const PopupMenuItem(
                value: 'library',
                child: ListTile(
                  leading: Icon(Icons.library_books),
                  title: Text('Converted books'),
                ),
              ),
              const PopupMenuItem(
                value: 'settings',
                child: ListTile(
                  leading: Icon(Icons.settings),
                  title: Text('Settings'),
                ),
              ),
              const PopupMenuItem(
                value: 'about',
                child: ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('About'),
                ),
              ),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;
          final bookPane = _BookPane(path: bookPath);

          // No book open: full-width library home (no board chrome).
          if (bookPath == null) return bookPane;

          final boardPane = Column(
            children: const [
              Expanded(child: BoardPanel()),
              MoveStrip(),
            ],
          );

          if (wide) {
            final total = constraints.maxWidth;
            const handle = 10.0;
            final fraction =
                ref.watch(settingsProvider.select((s) => s.boardFraction));
            final boardWidth = (total - handle) * fraction;
            return Row(
              children: [
                SizedBox(width: total - handle - boardWidth, child: bookPane),
                _ResizeHandle(
                  onDelta: (dx) => ref
                      .read(settingsProvider.notifier)
                      .setBoardFraction(fraction - dx / total),
                ),
                SizedBox(
                  width: boardWidth,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: boardPane,
                  ),
                ),
              ],
            );
          }

          // Narrow: book fills, board is a toggleable bottom panel.
          return Column(
            children: [
              Expanded(child: bookPane),
              Material(
                elevation: 8,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InkWell(
                      onTap: () => setState(
                          () => _boardVisibleNarrow = !_boardVisibleNarrow),
                      child: SizedBox(
                        height: 32,
                        child: Icon(_boardVisibleNarrow
                            ? Icons.keyboard_arrow_down
                            : Icons.keyboard_arrow_up),
                      ),
                    ),
                    if (_boardVisibleNarrow)
                      SizedBox(
                        height: constraints.maxHeight * 0.5,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: boardPane,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Original-pages / reading-view switch (PDF only).
class _ViewToggle extends ConsumerWidget {
  const _ViewToggle({required this.path});
  final String path;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(libraryStoreProvider).viewMode[path] ?? 'pdf';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: SegmentedButton<String>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(
              value: 'pdf',
              icon: Icon(Icons.picture_as_pdf_outlined),
              tooltip: 'Original pages'),
          ButtonSegment(
              value: 'html',
              icon: Icon(Icons.article_outlined),
              tooltip: 'Reading view'),
        ],
        selected: {mode},
        onSelectionChanged: (s) =>
            ref.read(libraryStoreProvider.notifier).setViewMode(path, s.first),
      ),
    );
  }
}

/// Draggable divider between the book pane and the side board.
class _ResizeHandle extends StatelessWidget {
  const _ResizeHandle({required this.onDelta});
  final void Function(double dx) onDelta;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (d) => onDelta(d.delta.dx),
        child: SizedBox(
          width: 10,
          child: Center(
            child: Container(
              width: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BookPane extends ConsumerWidget {
  const _BookPane({required this.path});
  final String? path;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (path == null) return const LibraryHome();
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.all(12),
      child: _book(context, ref, path!),
    );
  }

  Widget _book(BuildContext context, WidgetRef ref, String path) {
    // Up-front diagram detection gates the reader (progress bar) for both
    // formats; results are cached so reopening is instant.
    final conversion = ref.watch(conversionProvider(path));
    return conversion.when(
      loading: () => _progress(ref, path),
      error: (e, _) => Center(child: Text('Could not open book: $e')),
      data: (c) {
        if (_isEpub(path)) return EpubBookView(path: path);
        final mode = ref.watch(libraryStoreProvider).viewMode[path] ?? 'pdf';
        return mode == 'html'
            ? PdfHtmlView(path: path, conversion: c)
            : PdfBookView(path: path);
      },
    );
  }

  Widget _progress(WidgetRef ref, String path) {
    final fraction =
        (ref.watch(conversionProgressProvider)[path] ?? 0).clamp(0.0, 1.0);
    final pct = (fraction * 100).toStringAsFixed(0);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 220,
            child: LinearProgressIndicator(
                value: fraction == 0 ? null : fraction),
          ),
          const SizedBox(height: 12),
          Text('Detecting chess diagrams… $pct%'),
        ],
      ),
    );
  }
}
