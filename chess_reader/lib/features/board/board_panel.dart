import 'dart:math';

import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/state/game_session.dart';
import '../engine/presentation/engine_panel.dart';
import 'external_links.dart';

/// Interactive chessground board bound to the [gameSessionProvider].
///
/// Both sides are playable (free play): the board is the user's analysis
/// surface, not a game against an opponent. Moves played here that leave the
/// book line enter the variation sandbox; "back to book" snaps back.
class BoardPanel extends ConsumerStatefulWidget {
  const BoardPanel({super.key});

  @override
  ConsumerState<BoardPanel> createState() => _BoardPanelState();
}

class _BoardPanelState extends ConsumerState<BoardPanel> {
  late final ChessboardController _controller;
  Side _orientation = Side.white;

  static const _settings = ChessboardSettings(
    pieceAssets: PieceSet.meridaAssets,
    enableCoordinates: true,
  );

  @override
  void initState() {
    super.initState();
    _controller =
        ChessboardController(game: _gameDataFor(ref.read(gameSessionProvider)));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  GameData _gameDataFor(GameSessionState s) {
    return GameData(
      fen: s.position.fen,
      lastMove: s.lastMove,
      playerSide:
          s.position.turn == Side.white ? PlayerSide.white : PlayerSide.black,
      validMoves: makeLegalMoves(s.position),
      sideToMove: s.position.turn,
      kingSquareInCheck:
          s.position.isCheck ? s.position.board.kingOf(s.position.turn) : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(gameSessionProvider, (previous, next) {
      _controller.updatePosition(_gameDataFor(next), resetPremove: true);
    });
    final session = ref.watch(gameSessionProvider);

    return Column(
      children: [
        const EnginePanel(),
        const SizedBox(height: 8),
        Expanded(
          child: Center(
            child: LayoutBuilder(
              builder: (context, constraints) => Chessboard(
                controller: _controller,
                size: min(constraints.maxWidth, constraints.maxHeight),
                settings: _settings,
                orientation: _orientation,
                onMove: (move, {viaDragAndDrop}) =>
                    ref.read(gameSessionProvider.notifier).playMove(move),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (!session.onBookLine)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: FilledButton.tonalIcon(
              icon: const Icon(Icons.keyboard_return),
              label: const Text('Back to book'),
              onPressed: () =>
                  ref.read(gameSessionProvider.notifier).backToBook(),
            ),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              tooltip: 'Undo move',
              icon: const Icon(Icons.undo),
              onPressed: session.canUndo
                  ? () => ref.read(gameSessionProvider.notifier).undo()
                  : null,
            ),
            IconButton(
              tooltip: 'Reset board',
              icon: const Icon(Icons.restart_alt),
              onPressed: () => ref.read(gameSessionProvider.notifier).reset(),
            ),
            IconButton(
              tooltip: 'Flip board',
              icon: const Icon(Icons.swap_vert),
              onPressed: () =>
                  setState(() => _orientation = _orientation.opposite),
            ),
            const SizedBox(width: 12),
            IconButton(
              tooltip: 'Open in Lichess',
              icon: const Icon(Icons.open_in_new),
              onPressed: () => launchUrl(
                Uri.parse(lichessAnalysisUrl(session.fen)),
              ),
            ),
            IconButton(
              tooltip: 'Open in Chess.com',
              icon: const Icon(Icons.language),
              onPressed: () => launchUrl(
                Uri.parse(chessComAnalysisUrl(session.fen)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
