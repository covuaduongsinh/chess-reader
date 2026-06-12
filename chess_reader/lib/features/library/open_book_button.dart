import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../reader/state/book_providers.dart';

class OpenBookButton extends ConsumerWidget {
  const OpenBookButton({super.key, this.filled = false});

  /// Render as a prominent filled button (empty state) instead of an icon.
  final bool filled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Future<void> pick() async {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        dialogTitle: 'Open a chess book',
      );
      final path = result?.files.single.path;
      if (path != null) {
        ref.read(openedBookProvider.notifier).open(path);
      }
    }

    if (filled) {
      return FilledButton.icon(
        onPressed: pick,
        icon: const Icon(Icons.folder_open),
        label: const Text('Open a chess book (PDF)'),
      );
    }
    return IconButton(
      tooltip: 'Open book',
      icon: const Icon(Icons.folder_open),
      onPressed: pick,
    );
  }
}
