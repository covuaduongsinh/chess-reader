import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../board/board_panel.dart';
import '../../library/open_book_button.dart';
import '../state/book_providers.dart';
import 'move_strip.dart';
import 'pdf_book_view.dart';

/// Main screen: book pane on the left, board + move strip on the right.
/// On narrow layouts this will become a board overlay (Phase 6).
class ReaderScreen extends ConsumerWidget {
  const ReaderScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookPath = ref.watch(openedBookProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chess Reader'),
        actions: const [OpenBookButton(), SizedBox(width: 8)],
      ),
      body: Row(
        children: [
          Expanded(
            flex: 3,
            child: Card(
              clipBehavior: Clip.antiAlias,
              margin: const EdgeInsets.all(12),
              child: bookPath == null
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.menu_book,
                              size: 64,
                              color: Theme.of(context).colorScheme.outline),
                          const SizedBox(height: 16),
                          const OpenBookButton(filled: true),
                        ],
                      ),
                    )
                  : PdfBookView(path: bookPath),
            ),
          ),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: const [
                  Expanded(child: BoardPanel()),
                  MoveStrip(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
