import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Per-square piece labels. Uppercase white, lowercase black, '' empty —
/// FEN letters directly.
const squareLabels = [
  'K', 'Q', 'R', 'B', 'N', 'P', //
  'k', 'q', 'r', 'b', 'n', 'p', //
  '',
];

/// Classifies one board cell image into one of [squareLabels].
///
/// Implementations: [TemplateSquareClassifier] (pure Dart, good on clean
/// rendered diagrams) now; an ONNX CNN (exported from
/// tsoj/Chess_diagram_to_FEN or trained on synthetic data) is the planned
/// drop-in upgrade for scanned book diagrams.
abstract class SquareClassifier {
  Future<void> ensureReady();

  /// [cell] is a square crop of one board cell.
  String classify(img.Image cell);
}

/// Template classifier: empty squares are detected by their flatness
/// (low variance); occupied cells are matched against piece templates by
/// cosine similarity of z-scored grayscale patches, which is robust to
/// paper tone and print density.
class TemplateSquareClassifier implements SquareClassifier {
  TemplateSquareClassifier(this._loadTemplatePng);

  static const _patch = 24;

  /// Below this grayscale standard deviation a cell counts as empty.
  static const _emptyStdDev = 10.0;

  /// Loads the raw PNG bytes for a piece id like `wN`, `bQ` — from Flutter
  /// bundle assets in the app, from the filesystem in tests.
  final Future<Uint8List> Function(String pieceId) _loadTemplatePng;

  final List<(String label, Float64List patch)> _templates = [];
  bool _ready = false;

  @override
  Future<void> ensureReady() async {
    if (_ready) return;
    const pieces = {
      'K': 'wK', 'Q': 'wQ', 'R': 'wR', 'B': 'wB', 'N': 'wN', 'P': 'wP',
      'k': 'bK', 'q': 'bQ', 'r': 'bR', 'b': 'bB', 'n': 'bN', 'p': 'bP',
    };
    for (final light in [true, false]) {
      final bg = light ? 0xF0D9B5 : 0xB58863; // lichess board colors
      for (final entry in pieces.entries) {
        final png = img.decodePng(await _loadTemplatePng(entry.value))!;
        final composed = img.Image(width: png.width, height: png.height);
        img.fill(composed, color: _rgb(bg));
        img.compositeImage(composed, png);
        final (vector, _) = _normalize(composed);
        _templates.add((entry.key, vector));
      }
    }
    _ready = true;
  }

  @override
  String classify(img.Image cell) {
    assert(_ready, 'call ensureReady() first');
    final (probe, stdDev) = _normalize(cell);
    if (stdDev < _emptyStdDev) return '';
    var bestLabel = '';
    var bestSimilarity = -2.0;
    for (final (label, template) in _templates) {
      var dot = 0.0;
      for (var i = 0; i < probe.length; i++) {
        dot += probe[i] * template[i];
      }
      if (dot > bestSimilarity) {
        bestSimilarity = dot;
        bestLabel = label;
      }
    }
    return bestLabel;
  }

  /// Grayscale [_patch]x[_patch], zero-mean and L2-normalized (a unit
  /// vector, so dot product = cosine similarity). Also returns the raw
  /// grayscale standard deviation for the emptiness gate.
  (Float64List, double) _normalize(img.Image cell) {
    final small = img.copyResize(
      img.grayscale(img.Image.from(cell)),
      width: _patch,
      height: _patch,
    );
    final v = Float64List(_patch * _patch);
    var mean = 0.0;
    var i = 0;
    for (final p in small) {
      v[i] = p.r.toDouble();
      mean += v[i];
      i++;
    }
    mean /= v.length;
    var sumSq = 0.0;
    for (var j = 0; j < v.length; j++) {
      v[j] -= mean;
      sumSq += v[j] * v[j];
    }
    final stdDev = math.sqrt(sumSq / v.length);
    final norm = math.sqrt(sumSq);
    if (norm > 1e-9) {
      for (var j = 0; j < v.length; j++) {
        v[j] /= norm;
      }
    }
    return (v, stdDev);
  }

  img.Color _rgb(int rgb) => img.ColorRgb8(
        (rgb >> 16) & 0xFF,
        (rgb >> 8) & 0xFF,
        rgb & 0xFF,
      );
}
