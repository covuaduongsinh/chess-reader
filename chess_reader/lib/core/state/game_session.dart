import 'package:dartchess/dartchess.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Immutable snapshot of the board state the app is currently showing.
///
/// In later phases this grows a "book line vs user excursion" distinction
/// (variation sandbox) and an anchor FEN; for now it is a single line of play.
class GameSessionState {
  const GameSessionState({
    required this.position,
    this.lastMove,
    this.canUndo = false,
  });

  final Position position;
  final NormalMove? lastMove;
  final bool canUndo;

  String get fen => position.fen;
}

/// Central authority over the current position. The board, the reader and
/// (later) the engine all observe this provider; moves from any source
/// (board taps, clicked book moves, diagram anchors) funnel through it.
class GameSession extends Notifier<GameSessionState> {
  final List<(Position, NormalMove?)> _undoStack = [];

  @override
  GameSessionState build() => GameSessionState(position: Chess.initial);

  void playMove(Move move) {
    final pos = state.position;
    if (move is! NormalMove || !pos.isLegal(move)) return;
    _undoStack.add((pos, state.lastMove));
    state = GameSessionState(
      position: pos.playUnchecked(move),
      lastMove: move,
      canUndo: true,
    );
  }

  void undo() {
    if (_undoStack.isEmpty) return;
    final (pos, lastMove) = _undoStack.removeLast();
    state = GameSessionState(
      position: pos,
      lastMove: lastMove,
      canUndo: _undoStack.isNotEmpty,
    );
  }

  void reset() {
    _undoStack.clear();
    state = GameSessionState(position: Chess.initial);
  }

  /// Jumps to an arbitrary position (clicked book move, diagram anchor, FEN
  /// input). Clears the undo stack: the new position starts a fresh context.
  void setPosition(Position position, {NormalMove? lastMove}) {
    _undoStack.clear();
    state = GameSessionState(position: position, lastMove: lastMove);
  }
}

final gameSessionProvider =
    NotifierProvider<GameSession, GameSessionState>(GameSession.new);
