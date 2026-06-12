import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/state/game_session.dart';

/// "Set position here": paste a FEN to anchor the board (and, downstream,
/// move resolution) to an arbitrary position — the manual counterpart of the
/// Phase 5 diagram anchors.
Future<void> showFenAnchorDialog(BuildContext context, WidgetRef ref) async {
  final controller = TextEditingController(
    text: ref.read(gameSessionProvider).fen,
  );
  String? error;

  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Set position from FEN'),
        content: SizedBox(
          width: 480,
          child: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: 'FEN',
              errorText: error,
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              try {
                final setup = Setup.parseFen(controller.text.trim());
                final position = Chess.fromSetup(setup);
                ref.read(gameSessionProvider.notifier).setPosition(position);
                Navigator.of(context).pop();
              } on FenException {
                setState(() => error = 'Invalid FEN');
              } on PositionSetupException {
                setState(() => error = 'Illegal position');
              }
            },
            child: const Text('Set position'),
          ),
        ],
      ),
    ),
  );
}
