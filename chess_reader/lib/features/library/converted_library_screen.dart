import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../reader/data/book_conversion.dart';
import '../reader/state/book_providers.dart';

/// A standalone screen listing every book that has been converted (cached on
/// disk). Each opens instantly; the cache entry can be deleted.
class ConvertedLibraryScreen extends ConsumerStatefulWidget {
  const ConvertedLibraryScreen({super.key});

  @override
  ConsumerState<ConvertedLibraryScreen> createState() =>
      _ConvertedLibraryScreenState();
}

class _ConvertedLibraryScreenState
    extends ConsumerState<ConvertedLibraryScreen> {
  late Future<List<CachedBook>> _future = listCachedConversions();

  void _refresh() => setState(() => _future = listCachedConversions());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Converted books')),
      body: FutureBuilder<List<CachedBook>>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final books = snap.data!;
          if (books.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'No converted books yet.\n'
                  'Open a PDF or EPUB and it will be converted and saved here.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.separated(
            itemCount: books.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final book = books[i];
              final exists = File(book.path).existsSync();
              return ListTile(
                leading: Icon(book.format == 'epub'
                    ? Icons.menu_book
                    : Icons.picture_as_pdf),
                title: Text(book.title,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  exists ? book.path : 'File moved or deleted',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: exists
                      ? null
                      : const TextStyle(color: Colors.redAccent),
                ),
                trailing: IconButton(
                  tooltip: 'Delete saved conversion',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    await deleteCachedConversion(book.path);
                    _refresh();
                  },
                ),
                enabled: exists,
                onTap: exists
                    ? () {
                        ref
                            .read(openedBookProvider.notifier)
                            .open(book.path);
                        Navigator.of(context).pop();
                      }
                    : null,
              );
            },
          );
        },
      ),
    );
  }
}
