import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/analysis_provider.dart';

/// Engine evaluation strip: toggle, eval bar, score and principal variation.
class EnginePanel extends ConsumerWidget {
  const EnginePanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analysis = ref.watch(analysisProvider);
    final theme = Theme.of(context);

    final pv = analysis.eval != null && analysis.fen != null
        ? pvToSan(analysis.fen!, analysis.eval!.pvUci).join(' ')
        : '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: analysis.enabled ? 'Stop engine' : 'Analyze with Stockfish',
              icon: Icon(
                analysis.enabled ? Icons.memory : Icons.memory_outlined,
                color: analysis.enabled ? theme.colorScheme.primary : null,
              ),
              onPressed: () => ref.read(analysisProvider.notifier).toggle(),
            ),
            if (analysis.enabled) ...[
              SizedBox(
                width: 64,
                child: Text(
                  analysis.scoreLabel ?? '…',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                ),
              ),
              if (analysis.eval?.depth != null)
                Text('d${analysis.eval!.depth}',
                    style: theme.textTheme.bodySmall),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  pv,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ] else if (analysis.error != null)
              Expanded(
                child: Text(
                  analysis.error!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error),
                ),
              ),
          ],
        ),
        if (analysis.enabled) _EvalBar(whitePawns: analysis.whitePawns),
      ],
    );
  }
}

class _EvalBar extends StatelessWidget {
  const _EvalBar({this.whitePawns});

  /// Eval in pawns from White's perspective; null → balanced bar.
  final double? whitePawns;

  @override
  Widget build(BuildContext context) {
    // Map eval to a 0..1 white share with a sigmoid-like clamp: ±5 pawns
    // nearly fills the bar.
    final v = (whitePawns ?? 0).clamp(-5.0, 5.0) / 10.0 + 0.5;
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: SizedBox(
        height: 6,
        child: Row(
          children: [
            Expanded(
              flex: (v * 1000).round().clamp(1, 999),
              child: Container(color: Colors.white),
            ),
            Expanded(
              flex: ((1 - v) * 1000).round().clamp(1, 999),
              child: Container(color: Colors.black87),
            ),
          ],
        ),
      ),
    );
  }
}
