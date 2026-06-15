/// Decides whether a classified 8x8 grid is a real, populated chess diagram
/// worth emitting — or a false positive (an empty board grid, a photo/figure,
/// or any large square dark blob the locator picked up) that should be dropped.
///
/// The board locator accepts any large square-ish dark region, and the square
/// classifier always forces every cell to *some* class. Without this gate those
/// non-boards surface as diagrams full of random pieces. We reject on actual
/// piece evidence: a genuine diagram has a sane number of pieces, at least one
/// king, no impossible counts, and (when the model reports it) decent average
/// confidence.
library;

/// Minimum number of pieces for a grid to count as a real diagram. Kept low so
/// genuine sparse endgame studies (e.g. K+P vs K = 3 pieces) still pass; an
/// empty board has 0 and is dropped. The "at least one king" rule, the count
/// caps and (on the ONNX path) the confidence gate do the real filtering.
const int kMinPieces = 2;

/// A real chess position never has more than 32 pieces, 8 pawns per side, or
/// one king per side. Exceeding these means the read is garbage, not a board.
const int kMaxPieces = 32;
const int kMaxPawnsPerSide = 8;

/// Below this mean top-class probability the grid is almost certainly not a
/// board (the model is guessing). Only applied when confidences are supplied
/// (the ONNX path); the template classifier reports none.
const double kMinMeanConfidence = 0.5;

/// Whether [labels] (64 FEN letters, '' for empty) describe a plausible diagram.
/// When [confidences] (64 per-cell top-class probabilities) is given, also
/// requires a decent mean — this is what rejects non-board regions.
bool isPlausibleDiagram(List<String> labels, {List<double>? confidences}) {
  assert(labels.length == 64);

  var pieces = 0;
  var whiteKings = 0, blackKings = 0;
  var whitePawns = 0, blackPawns = 0;
  for (final label in labels) {
    if (label.isEmpty) continue;
    pieces++;
    switch (label) {
      case 'K':
        whiteKings++;
      case 'k':
        blackKings++;
      case 'P':
        whitePawns++;
      case 'p':
        blackPawns++;
    }
  }

  if (pieces < kMinPieces || pieces > kMaxPieces) return false;
  if (whiteKings + blackKings == 0) return false;
  if (whiteKings > 1 || blackKings > 1) return false;
  if (whitePawns > kMaxPawnsPerSide || blackPawns > kMaxPawnsPerSide) {
    return false;
  }

  if (confidences != null && confidences.isNotEmpty) {
    final mean =
        confidences.reduce((a, b) => a + b) / confidences.length;
    if (mean < kMinMeanConfidence) return false;
  }

  return true;
}
