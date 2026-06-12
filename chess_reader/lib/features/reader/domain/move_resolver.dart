import 'package:dartchess/dartchess.dart';

import '../../../core/models/move_token.dart';

/// A token successfully resolved against the game context: playing [move]
/// from [positionBefore] yields [positionAfter], which is what the board
/// shows when the user taps this token in the book.
class ResolvedMove {
  const ResolvedMove({
    required this.token,
    required this.move,
    required this.positionBefore,
    required this.positionAfter,
  });

  final MoveToken token;
  final Move move;
  final Position positionBefore;
  final Position positionAfter;
}

class ResolvedLine {
  const ResolvedLine({required this.moves, required this.unresolved});

  /// Tokens resolved into a legal sequence, in reading order.
  final List<ResolvedMove> moves;

  /// Tokens that looked like SAN but were illegal in context. These render
  /// non-clickable: wrong is worse than missing.
  final List<MoveToken> unresolved;
}

/// v1 resolver: assumes the tokens form a single game played from [start]
/// (default: the initial position). Unresolvable tokens are skipped without
/// advancing the position, so one false positive in prose ("a4 pawn") does
/// not poison the rest of the page. Anchors, variations and the recovery
/// ladder arrive in Phase 3.
class MoveResolver {
  MoveResolver._();

  static ResolvedLine resolve(List<MoveToken> tokens, {Position? start}) {
    var position = start ?? Chess.initial;
    final moves = <ResolvedMove>[];
    final unresolved = <MoveToken>[];

    for (final token in tokens) {
      final move = position.parseSan(token.san);
      if (move == null) {
        unresolved.add(token);
        continue;
      }
      final next = position.play(move);
      moves.add(ResolvedMove(
        token: token,
        move: move,
        positionBefore: position,
        positionAfter: next,
      ));
      position = next;
    }
    return ResolvedLine(moves: moves, unresolved: unresolved);
  }
}
