import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/persistence/library_store.dart';
import '../../board/board_panel.dart';
import '../../library/open_book_button.dart';
import '../../settings/settings_screen.dart';
import '../state/book_providers.dart';
import 'epub_book_view.dart';
import 'move_strip.dart';
import 'pdf_book_view.dart';
import 'reader_drawer.dart';

/// Main screen: book pane and board, side-by-side on wide layouts and a
/// toggleable board panel on narrow (phone) layouts. Auto-resumes the most
/// recent book on launch.
class ReaderScreen extends ConsumerStatefulWidget {
  const ReaderScreen({super.key});

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen> {
  bool _resumed = false;
  bool _boardVisibleNarrow = true;

  @override
  void initState() {
    super.initState();
    // Auto-resume the most recent book once, if its file still exists.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_resumed) return;
      _resumed = true;
      final recent = ref.read(libraryStoreProvider).mostRecent;
      if (recent != null && File(recent).existsSync()) {
        ref.read(openedBookProvider.notifier).open(recent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bookPath = ref.watch(openedBookProvider);

    return Scaffold(
      endDrawer: bookPath != null ? ReaderDrawer(path: bookPath) : null,
      appBar: AppBar(
        title: const Text('Chess Reader'),
        actions: [
          const OpenBookButton(),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
          if (bookPath != null)
            Builder(
              builder: (context) => IconButton(
                tooltip: 'Contents, search, bookmarks',
                icon: const Icon(Icons.menu_open),
                onPressed: () => Scaffold.of(context).openEndDrawer(),
              ),
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;
          final bookPane = _BookPane(path: bookPath);
          final boardPane = Column(
            children: const [
              Expanded(child: BoardPanel()),
              MoveStrip(),
            ],
          );

          if (wide) {
            return Row(
              children: [
                Expanded(flex: 3, child: bookPane),
                Expanded(
                  flex: 2,
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
              if (bookPath != null)
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

class _BookPane extends StatelessWidget {
  const _BookPane({required this.path});
  final String? path;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.all(12),
      child: path == null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.menu_book,
                      size: 64, color: Theme.of(context).colorScheme.outline),
                  const SizedBox(height: 16),
                  const OpenBookButton(filled: true),
                ],
              ),
            )
          : path!.toLowerCase().endsWith('.epub')
              ? EpubBookView(path: path!)
              : PdfBookView(path: path!),
    );
  }
}
