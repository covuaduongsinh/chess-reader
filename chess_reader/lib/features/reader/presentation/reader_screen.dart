import 'package:flutter/material.dart';

import '../../board/board_panel.dart';

/// Main screen: book pane on the left, board + (later) engine panel on the
/// right. On narrow layouts this will become a board overlay (Phase 6).
class ReaderScreen extends StatelessWidget {
  const ReaderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chess Reader')),
      body: Row(
        children: [
          Expanded(
            flex: 3,
            child: Card(
              margin: const EdgeInsets.all(12),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.menu_book,
                        size: 64,
                        color: Theme.of(context).colorScheme.outline),
                    const SizedBox(height: 16),
                    const Text('Open a chess book (PDF/EPUB) — coming next'),
                  ],
                ),
              ),
            ),
          ),
          const Expanded(
            flex: 2,
            child: Padding(
              padding: EdgeInsets.all(12),
              child: BoardPanel(),
            ),
          ),
        ],
      ),
    );
  }
}
