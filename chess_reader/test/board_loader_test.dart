import 'package:dartchess/dartchess.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chess_reader/core/state/board_loader.dart';
import 'package:chess_reader/core/state/game_session.dart';

void main() {
  group('tryLoadFen', () {
    test('loads a normal legal position as-is', () {
      const fen =
          'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1';
      final loaded = tryLoadFen(fen);
      expect(loaded, isNotNull);
      expect(loaded!.legal, isTrue);
      expect(loaded.position!.turn, Side.black);
    });

    test('recovers a wrong side-to-move by flipping the turn', () {
      // Black king on e8 is in check from the white queen on e7. As written
      // (white to move) this is illegal "opposite check" — exactly what the
      // FEN assembler produces when it guesses the wrong side to move.
      const fen = '4k3/4Q3/4K3/8/8/8/8/8 w - - 0 1';
      final loaded = tryLoadFen(fen);
      expect(loaded, isNotNull, reason: 'placement is valid');
      expect(loaded!.legal, isTrue, reason: 'legal once the turn is flipped');
      expect(loaded.position!.turn, Side.black);
    });

    test('keeps a genuinely illegal placement as display-only', () {
      // Only one king — can never be a legal position.
      const fen = '8/8/8/8/8/8/8/4K3 w - - 0 1';
      final loaded = tryLoadFen(fen);
      expect(loaded, isNotNull);
      expect(loaded!.legal, isFalse);
      expect(loaded.position, isNull);
      expect(loaded.fen.startsWith('8/8/8/8/8/8/8/4K3'), isTrue);
    });

    test('returns null for an unparseable FEN', () {
      expect(tryLoadFen('not a fen'), isNull);
    });
  });

  group('GameSession.loadFen', () {
    GameSession sessionIn(ProviderContainer c) =>
        c.read(gameSessionProvider.notifier);

    test('updates the board for a flip-recoverable diagram FEN', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final ok = sessionIn(c).loadFen('4k3/4Q3/4K3/8/8/8/8/8 w - - 0 1');
      expect(ok, isTrue);
      final state = c.read(gameSessionProvider);
      expect(state.legal, isTrue);
      expect(state.position.turn, Side.black);
      // The board now shows the diagram, not the start position.
      expect(state.fen, isNot(kInitialFEN));
    });

    test('shows illegal placements display-only (board still changes)', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final ok = sessionIn(c).loadFen('8/8/8/8/8/8/8/4K3 w - - 0 1');
      expect(ok, isTrue);
      final state = c.read(gameSessionProvider);
      expect(state.legal, isFalse);
      expect(state.fen.startsWith('8/8/8/8/8/8/8/4K3'), isTrue);
    });

    test('rejects an unparseable FEN without touching the board', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final ok = sessionIn(c).loadFen('garbage');
      expect(ok, isFalse);
      expect(c.read(gameSessionProvider).fen, kInitialFEN);
    });
  });
}
