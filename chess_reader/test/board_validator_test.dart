import 'package:flutter_test/flutter_test.dart';

import 'package:chess_reader/features/vision/domain/board_validator.dart';

/// Builds 64 labels from a FEN board-placement field (rank 8 → rank 1).
List<String> _labels(String placement) {
  final out = <String>[];
  for (final rank in placement.split('/')) {
    for (final ch in rank.split('')) {
      final skip = int.tryParse(ch);
      if (skip != null) {
        out.addAll(List.filled(skip, ''));
      } else {
        out.add(ch);
      }
    }
  }
  assert(out.length == 64, 'got ${out.length}');
  return out;
}

void main() {
  test('accepts a real starting position', () {
    expect(
      isPlausibleDiagram(
          _labels('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR')),
      isTrue,
    );
  });

  test('accepts a sparse but legal endgame', () {
    expect(isPlausibleDiagram(_labels('4k3/8/8/8/8/8/4P3/3RK3')), isTrue);
  });

  test('rejects an empty board', () {
    expect(isPlausibleDiagram(_labels('8/8/8/8/8/8/8/8')), isFalse);
  });

  test('accepts a bare K+P vs K endgame but rejects a lone king', () {
    expect(isPlausibleDiagram(_labels('4k3/8/8/8/8/8/4P3/4K3')), isTrue);
    expect(isPlausibleDiagram(_labels('4k3/8/8/8/8/8/8/8')), isFalse);
  });

  test('rejects a grid with no king', () {
    expect(isPlausibleDiagram(_labels('rnbq1bnr/pppppppp/8/8/8/8/8/8')),
        isFalse);
  });

  test('rejects impossible counts (two white kings, too many pawns)', () {
    final twoKings = List.filled(64, '')
      ..[0] = 'K'
      ..[1] = 'K'
      ..[2] = 'k'
      ..[3] = 'Q'
      ..[4] = 'R';
    expect(isPlausibleDiagram(twoKings), isFalse);

    final ninePawns = _labels('4k3/8/8/8/8/8/PPPPPPPP/PPPK4');
    expect(isPlausibleDiagram(ninePawns), isFalse);
  });

  test('rejects a board read with low mean confidence', () {
    final labels = _labels('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR');
    expect(
      isPlausibleDiagram(labels,
          confidences: List.filled(64, 0.2)),
      isFalse,
    );
    expect(
      isPlausibleDiagram(labels,
          confidences: List.filled(64, 0.95)),
      isTrue,
    );
  });
}
