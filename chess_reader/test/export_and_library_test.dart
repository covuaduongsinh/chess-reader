import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chess_reader/core/settings/app_settings.dart';
import 'package:chess_reader/core/persistence/library_store.dart';
import 'package:chess_reader/features/reader/data/book_exporter.dart';
import 'package:chess_reader/features/reader/data/epub_book.dart';

void main() {
  group('buildExportHtml', () {
    test('lowers app tags to browser-viewable HTML', () {
      final chapters = [
        const EpubChapter(
          title: 'Page 1',
          html: '<div><p>Play <chessmove idx="0">1.e4</chessmove> then'
              '</p><chessdiagram fen="8/8/8/8/8/8/8/8 w - - 0 1">'
              '<img src="data:image/png;base64,AAAA"></chessdiagram></div>',
          moves: [],
        ),
      ];
      final html = buildExportHtml('My Book', chapters);

      // App-only tags are gone.
      expect(html.contains('<chessmove'), isFalse);
      expect(html.contains('<chessdiagram'), isFalse);
      // Moves become a styled span; diagrams a figure with FEN caption + img.
      expect(html.contains('class="move"'), isTrue);
      expect(html.contains('1.e4'), isTrue);
      expect(html.contains('<figure'), isTrue);
      expect(html.contains('<figcaption>8/8/8/8/8/8/8/8 w - - 0 1'), isTrue);
      expect(html.contains('data:image/png;base64,AAAA'), isTrue);
      // It is a complete document with the title.
      expect(html.startsWith('<!DOCTYPE html>'), isTrue);
      expect(html.contains('<title>My Book</title>'), isTrue);
    });
  });

  group('LibraryStore.removeRecent', () {
    test('drops a path from the recent list', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final c = ProviderContainer(
        overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
      );
      addTearDown(c.dispose);
      final store = c.read(libraryStoreProvider.notifier);
      store.recordOpened('a.pdf');
      store.recordOpened('b.pdf');
      store.removeRecent('a.pdf');
      expect(c.read(libraryStoreProvider).recentPaths, ['b.pdf']);
    });
  });
}
