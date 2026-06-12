import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/book_providers.dart';

/// Horizontal strip showing the moves detected on the active page, with
/// previous/next stepping. SAN is shown in plain letters here; inline piece
/// images replace the letters in a later phase.
class MoveStrip extends ConsumerWidget {
  const MoveStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeLineProvider);
    if (active == null) {
      return const SizedBox.shrink();
    }
    final notifier = ref.read(activeLineProvider.notifier);

    return Row(
      children: [
        IconButton(
          tooltip: 'Previous move',
          icon: const Icon(Icons.chevron_left),
          onPressed: active.hasPrevious ? notifier.previous : null,
        ),
        Expanded(
          child: SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: active.result.moves.length,
              separatorBuilder: (_, _) => const SizedBox(width: 4),
              itemBuilder: (context, i) {
                final token = active.result.moves[i].resolved.token;
                final label = token.moveNumber != null
                    ? (token.isWhiteHint == false
                        ? '${token.moveNumber}...${token.san}'
                        : '${token.moveNumber}.${token.san}')
                    : token.san;
                return ChoiceChip(
                  label: Text(label),
                  selected: i == active.index,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => notifier.select(active.result, i),
                );
              },
            ),
          ),
        ),
        IconButton(
          tooltip: 'Next move',
          icon: const Icon(Icons.chevron_right),
          onPressed: active.hasNext ? notifier.next : null,
        ),
      ],
    );
  }
}
