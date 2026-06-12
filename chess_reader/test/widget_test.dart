import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chess_reader/app.dart';
import 'package:chess_reader/core/state/game_session.dart';

void main() {
  group('GameSession', () {
    test('plays legal moves and rejects illegal ones', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final session = container.read(gameSessionProvider.notifier);

      session.playMove(NormalMove.fromUci('e2e4'));
      expect(
        container.read(gameSessionProvider).fen,
        'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1',
      );

      // Illegal: white pawn already moved, black to play.
      session.playMove(NormalMove.fromUci('e4e5'));
      expect(
        container.read(gameSessionProvider).fen,
        'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1',
      );

      session.playMove(NormalMove.fromUci('e7e5'));
      expect(container.read(gameSessionProvider).position.turn, Side.white);
    });

    test('undo and reset restore earlier positions', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final session = container.read(gameSessionProvider.notifier);

      session.playMove(NormalMove.fromUci('d2d4'));
      session.playMove(NormalMove.fromUci('g8f6'));
      session.undo();
      expect(
        container.read(gameSessionProvider).fen,
        'rnbqkbnr/pppppppp/8/8/3P4/8/PPP1PPPP/RNBQKBNR b KQkq - 0 1',
      );

      session.reset();
      expect(container.read(gameSessionProvider).fen, kInitialFEN);
      expect(container.read(gameSessionProvider).canUndo, isFalse);
    });
  });

  testWidgets('app renders an interactive board that follows the session',
      (tester) async {
    await tester.pumpWidget(const ProviderScope(child: ChessReaderApp()));
    await tester.pump();

    expect(find.byType(Chessboard), findsOneWidget);

    final context = tester.element(find.byType(Chessboard));
    final container = ProviderScope.containerOf(context, listen: false);
    container.read(gameSessionProvider.notifier).playMove(
          NormalMove.fromUci('e2e4'),
        );
    await tester.pumpAndSettle();

    final controller =
        tester.widget<Chessboard>(find.byType(Chessboard)).controller;
    expect(
      controller.fen,
      'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1',
    );
  });
}
