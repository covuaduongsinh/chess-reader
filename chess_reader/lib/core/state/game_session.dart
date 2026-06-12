import 'package:dartchess/dartchess.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Immutable snapshot of the board state the app is currently showing.
class GameSessionState {
  const GameSessionState({
    required this.position,
    this.lastMove,
    this.canUndo = false,
    this.onBookLine = true,
  });

  final Position position;
  final NormalMove? lastMove;
  final bool canUndo;

  /// False while the user is exploring own moves away from the position the
  /// book set (variation sandbox). "Back to book" snaps back.
  final bool onBookLine;

  String get fen => position.fen;
}

/// Central authority over the current position. The board, the reader and
/// the engine all observe this provider; moves from any source (board taps,
/// clicked book moves, diagram anchors) funnel through it.
class GameSession extends Notifier<GameSessionState> {
  final List<(Position, NormalMove?)> _undoStack = [];

  /// The position the book most recently put on the board — the place
  /// "back to book" returns to.
  (Position, NormalMove?)? _bookAnchor;

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
      // Only an excursion when there is a book position to return to.
      onBookLine: _bookAnchor == null,
    );
  }

  void undo() {
    if (_undoStack.isEmpty) return;
    final (pos, lastMove) = _undoStack.removeLast();
    state = GameSessionState(
      position: pos,
      lastMove: lastMove,
      canUndo: _undoStack.isNotEmpty,
      onBookLine: _isBookPosition(pos),
    );
  }

  void reset() {
    _undoStack.clear();
    _bookAnchor = null;
    state = GameSessionState(position: Chess.initial);
  }

  /// Jumps to a book position (clicked move, diagram anchor, FEN input).
  /// Becomes the new anchor; the undo stack restarts from here.
  void setPosition(Position position, {NormalMove? lastMove}) {
    _undoStack.clear();
    _bookAnchor = (position, lastMove);
    state = GameSessionState(position: position, lastMove: lastMove);
  }

  /// Snaps back to the last book position after a sandbox excursion.
  void backToBook() {
    final anchor = _bookAnchor;
    if (anchor == null) return;
    _undoStack.clear();
    state = GameSessionState(position: anchor.$1, lastMove: anchor.$2);
  }

  bool _isBookPosition(Position pos) =>
      _bookAnchor == null || _bookAnchor!.$1.fen == pos.fen;
}

final gameSessionProvider =
    NotifierProvider<GameSession, GameSessionState>(GameSession.new);
