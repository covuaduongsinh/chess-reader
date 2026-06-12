import 'package:dartchess/dartchess.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/state/game_session.dart';
import '../data/page_moves_service.dart';

/// Path of the currently opened book, or null when no book is open.
final openedBookProvider = NotifierProvider<OpenedBook, String?>(
  OpenedBook.new,
);

class OpenedBook extends Notifier<String?> {
  @override
  String? build() => null;

  void open(String path) => state = path;

  void close() => state = null;
}

final pageMovesServiceProvider = Provider((ref) => PageMovesService());

/// The sequence of book moves the user is currently stepping through:
/// the resolved moves of one page, plus the index of the move on the board.
class ActiveLine {
  const ActiveLine({required this.result, required this.index});

  final PageMovesResult result;

  /// Index into [PageMovesResult.moves] of the move currently shown.
  final int index;

  bool get hasPrevious => index > 0;
  bool get hasNext => index < result.moves.length - 1;
}

class ActiveLineNotifier extends Notifier<ActiveLine?> {
  @override
  ActiveLine? build() => null;

  /// User tapped a move in the book: show its resulting position.
  void select(PageMovesResult result, int index) {
    state = ActiveLine(result: result, index: index);
    _applyToBoard();
  }

  void next() {
    final line = state;
    if (line == null || !line.hasNext) return;
    state = ActiveLine(result: line.result, index: line.index + 1);
    _applyToBoard();
  }

  void previous() {
    final line = state;
    if (line == null || !line.hasPrevious) return;
    state = ActiveLine(result: line.result, index: line.index - 1);
    _applyToBoard();
  }

  void _applyToBoard() {
    final line = state;
    if (line == null) return;
    final resolved = line.result.moves[line.index].resolved;
    ref.read(gameSessionProvider.notifier).setPosition(
          resolved.positionAfter,
          lastMove: resolved.move is NormalMove
              ? resolved.move as NormalMove
              : null,
        );
  }
}

final activeLineProvider =
    NotifierProvider<ActiveLineNotifier, ActiveLine?>(ActiveLineNotifier.new);
