import 'package:dartchess/dartchess.dart';

/// Result of trying to turn a (possibly imperfect) FEN into a board position.
///
/// Vision-assembled diagram FENs are frequently *almost* legal: the most
/// common defect is a wrong side-to-move (so the side not to move appears to
/// be in check). [tryLoadFen] recovers those; placements that are genuinely
/// illegal (missing/extra king, pawn on the back rank) still can't become a
/// dartchess [Position], but the board can display the raw placement so the
/// user always sees what was detected and can correct it.
class LoadedBoard {
  const LoadedBoard({required this.fen, this.position});

  /// FEN to render on the board (always set).
  final String fen;

  /// A legal position, or null when the placement could not be validated.
  /// When null the board is display-only (no legal-move generation/analysis).
  final Position? position;

  bool get legal => position != null;
}

/// Parses [fen] and tries hard to produce a legal [Position]:
/// 1. relax the "impossible check" rule (diagrams can't encode move history);
/// 2. if the side *not* to move is in check, retry with the side-to-move
///    flipped — this is by far the most common diagram defect, because the
///    FEN assembler defaults to "white to move".
///
/// Returns null if [fen]'s board placement is itself unparseable. If the
/// placement parses but no turn yields a legal position, the returned
/// [LoadedBoard] carries the placement with `position == null` (display-only).
LoadedBoard? tryLoadFen(String fen) {
  final Setup setup;
  try {
    setup = Setup.parseFen(fen);
  } on FenException {
    return null;
  }

  // Try the FEN as written, then with the opposite side to move.
  for (final turn in [setup.turn, setup.turn.opposite]) {
    final candidate = turn == setup.turn
        ? setup
        : Setup(
            board: setup.board,
            pockets: setup.pockets,
            turn: turn,
            castlingRights: setup.castlingRights,
            epSquare: setup.epSquare,
            halfmoves: setup.halfmoves,
            fullmoves: setup.fullmoves,
            remainingChecks: setup.remainingChecks,
          );
    try {
      final position =
          Chess.fromSetup(candidate, ignoreImpossibleCheck: true);
      return LoadedBoard(fen: position.fen, position: position);
    } on PositionSetupException {
      // Try the other turn; if both fail, fall through to display-only.
    }
  }

  // Placement is real but illegal (king count, pawns on back rank, …):
  // show it anyway so the board reflects the detection.
  return LoadedBoard(fen: setup.fen, position: null);
}
