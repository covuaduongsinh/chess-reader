import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chess_reader/core/models/move_token.dart';
import 'package:chess_reader/core/settings/app_settings.dart';
import 'package:chess_reader/core/state/game_session.dart';
import 'package:chess_reader/features/reader/data/epub_book.dart';
import 'package:chess_reader/features/reader/domain/move_resolver.dart';
import 'package:chess_reader/features/reader/presentation/book_html_view.dart';

/// Regression: tapping a detected diagram in the HTML reading view must load
/// its FEN onto the side board — it worked in PDF (original-pages) mode but the
/// reading view's tap didn't reach the handler. Renders the production
/// HtmlChapterList (ScrollablePositionedList) so the real scroll/hit-test
/// context is exercised.
void main() {
  testWidgets('tapping a diagram in the reading view loads its FEN',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    const fen = '4k3/8/8/3PP3/3PP3/8/8/4K3 w - - 0 1';
    const placement = '4k3/8/8/3PP3/3PP3/8/8/4K3';
    final chapter = EpubChapter(
      title: 'p1',
      html: '<div><p>before</p>'
          '<chessdiagram fen="$fen">board</chessdiagram>'
          '<p>after</p></div>',
      moves: const [],
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
      child: MaterialApp(
        home: Scaffold(
          body: HtmlChapterList(
            path: '/tmp/book.pdf',
            chapters: [chapter],
            sourceKeyPrefix: 'pg',
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final boardFinder = find.byType(StaticChessboard);
    expect(boardFinder, findsOneWidget, reason: 'diagram board should render');

    final container = ProviderScope.containerOf(
        tester.element(boardFinder),
        listen: false);
    expect(container.read(gameSessionProvider).fen.startsWith(placement),
        isFalse);

    await tester.tapAt(tester.getCenter(boardFinder));
    await tester.pumpAndSettle();

    expect(
      container.read(gameSessionProvider).fen.startsWith(placement),
      isTrue,
      reason: 'tapping the diagram should load its position onto the board',
    );
  });

  testWidgets('tapping a move in the reading view updates the board',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    // One resolved move: 1.e4 from the initial position.
    final before = Chess.initial;
    final move = NormalMove.fromUci('e2e4');
    final after = before.play(move);
    const expectedFen =
        'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1';
    final resolved = ResolvedMove(
      token: const MoveToken(san: 'e4', start: 0, end: 2),
      move: move,
      positionBefore: before,
      positionAfter: after,
    );
    final chapter = EpubChapter(
      title: 'p1',
      html: '<div><p>1.<chessmove idx="0">e4</chessmove> and so on.</p></div>',
      moves: [resolved],
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
      child: MaterialApp(
        home: Scaffold(
          body: HtmlChapterList(
            path: '/tmp/book.pdf',
            chapters: [chapter],
            sourceKeyPrefix: 'pg',
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final moveFinder = find.text('e4');
    expect(moveFinder, findsOneWidget, reason: 'move chip should render');

    final container = ProviderScope.containerOf(
        tester.element(moveFinder),
        listen: false);
    expect(container.read(gameSessionProvider).fen, isNot(expectedFen));

    await tester.tap(moveFinder);
    await tester.pumpAndSettle();

    expect(
      container.read(gameSessionProvider).fen,
      expectedFen,
      reason: 'tapping a move should play it onto the board',
    );
  });
}
