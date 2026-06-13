import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/persistence/library_store.dart';
import '../reader/data/book_conversion.dart';
import '../reader/state/book_providers.dart';
import 'open_book_button.dart';

/// Shown when no book is open: a prominent "open" action plus the list of
/// recently-opened books for one-tap switching. Books that have already been
/// converted reopen instantly from the cache (shown with a check).
class LibraryHome extends ConsumerWidget {
  const LibraryHome({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recent = ref.watch(libraryStoreProvider).recentPaths;
    final theme = Theme.of(context);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Icons.menu_book, size: 64, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            const Center(child: OpenBookButton(filled: true)),
            if (recent.isNotEmpty) ...[
              const SizedBox(height: 28),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text('Recent books', style: theme.textTheme.titleSmall),
              ),
              const SizedBox(height: 4),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final path in recent) _RecentTile(path: path),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RecentTile extends ConsumerWidget {
  const _RecentTile({required this.path});
  final String path;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exists = File(path).existsSync();
    final isEpub = path.toLowerCase().endsWith('.epub');
    return ListTile(
      leading: Icon(isEpub ? Icons.menu_book : Icons.picture_as_pdf),
      title: Text(p.basename(path),
          maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: exists
          ? FutureBuilder<bool>(
              future: hasCachedConversion(path),
              builder: (context, snap) => snap.data == true
                  ? const Text('Converted · opens instantly')
                  : Text(p.dirname(path),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
            )
          : const Text('File not found',
              style: TextStyle(color: Colors.redAccent)),
      trailing: IconButton(
        tooltip: 'Remove from list',
        icon: const Icon(Icons.close, size: 18),
        onPressed: () =>
            ref.read(libraryStoreProvider.notifier).removeRecent(path),
      ),
      enabled: exists,
      onTap: exists
          ? () => ref.read(openedBookProvider.notifier).open(path)
          : null,
    );
  }
}
