import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

import '../domain/board_slicer.dart';
import '../domain/square_classifier.dart';

/// Class order MUST match `CLASSES` in tool/vision_train/model.py. Shares the
/// [squareLabels] contract used by the template classifier.
const List<String> kModelClasses = squareLabels;

const String kSquareModelAsset = 'assets/models/square_classifier.onnx';

/// Below this contrast (std-dev of a cell's normalized pixels) a cell is forced
/// to empty regardless of the CNN, so the blank squares of an empty/sparse
/// board don't get hallucinated pieces. Mirrors `TemplateSquareClassifier`'s
/// emptiness gate (its grayscale std-dev 10 ≈ 10/127.5 here, as cells are
/// normalized to [-1, 1] by `preprocessCell`).
const double _emptyStdDev = 0.08;

/// A classified board: 64 FEN labels (row-major) plus, per cell, the model's
/// top-class probability — used to reject non-board regions read with low
/// confidence (see `isPlausibleDiagram`).
class BoardClassification {
  const BoardClassification(this.labels, this.confidences, [this.classProbs]);

  final List<String> labels;
  final List<double> confidences;

  /// Per-cell softmax over [kModelClasses] (64 rows of [kModelClasses].length,
  /// same row-major order as [labels]). Null on the template path. Used only by
  /// legality repair (`repairToLegal`), which redistributes a misread square to
  /// its next-best class.
  final List<Float32List>? classProbs;
}

/// Runs the per-square CNN over a board's 64 cells in a single batched
/// inference. Native ONNX Runtime executes off the Dart thread, so calling
/// this from the main isolate does not block the UI.
///
/// Platform-channel based (flutter_onnxruntime) — must NOT be constructed
/// inside a `compute()` isolate; the heavy cell preprocessing happens there
/// instead and the resulting tensors are classified here.
class OnnxSquareClassifier {
  OnnxSquareClassifier._(this._session, this._inputName);

  final OrtSession _session;
  final String _inputName;

  static Future<OnnxSquareClassifier?> tryLoad() async {
    try {
      final session = await OnnxRuntime()
          .createSessionFromAsset(kSquareModelAsset);
      final inputName =
          session.inputNames.isNotEmpty ? session.inputNames.first : 'cells';
      return OnnxSquareClassifier._(session, inputName);
    } catch (_) {
      // Model asset absent or runtime unavailable: caller falls back.
      return null;
    }
  }

  /// [cells64] holds 64 preprocessed cells (row-major) concatenated, each of
  /// length [kCellSize]². Returns 64 FEN labels and per-cell confidences.
  ///
  /// A near-flat cell (low contrast) is forced to empty before trusting the
  /// CNN — see [_emptyStdDev].
  Future<BoardClassification> classifyBoard(Float32List cells64) async {
    const cellLen = kCellSize * kCellSize;
    assert(cells64.length == 64 * cellLen);
    final input = await OrtValue.fromList(
      cells64,
      [64, 1, kCellSize, kCellSize],
    );
    try {
      final outputs = await _session.run({_inputName: input});
      final logitsValue = outputs.values.first;
      final flat = (await logitsValue.asFlattenedList()).cast<num>();
      for (final v in outputs.values) {
        await v.dispose();
      }
      final labels = <String>[];
      final confidences = <double>[];
      final classProbs = <Float32List>[];
      final n = kModelClasses.length;
      for (var cell = 0; cell < 64; cell++) {
        var best = 0;
        var bestVal = flat[cell * n].toDouble();
        for (var c = 1; c < n; c++) {
          final v = flat[cell * n + c].toDouble();
          if (v > bestVal) {
            bestVal = v;
            best = c;
          }
        }
        // Softmax over the cell's logits; reused for both the winning-class
        // confidence and the full per-class distribution legality repair needs.
        var sumExp = 0.0;
        for (var c = 0; c < n; c++) {
          sumExp += math.exp(flat[cell * n + c].toDouble() - bestVal);
        }
        final invSum = 1.0 / sumExp;
        final confidence = invSum; // exp(bestVal - bestVal) == 1
        final probs = Float32List(n);
        for (var c = 0; c < n; c++) {
          probs[c] = math.exp(flat[cell * n + c].toDouble() - bestVal) * invSum;
        }
        classProbs.add(probs);

        // Emptiness gate: a flat cell is empty whatever the CNN says.
        final empty =
            _cellStdDev(cells64, cell * cellLen, cellLen) < _emptyStdDev;
        labels.add(empty ? '' : kModelClasses[best]);
        confidences.add(confidence);
      }
      return BoardClassification(labels, confidences, classProbs);
    } finally {
      await input.dispose();
    }
  }

  /// Standard deviation of one cell's normalized pixels in [cells64].
  static double _cellStdDev(Float32List cells64, int start, int len) {
    var mean = 0.0;
    for (var i = 0; i < len; i++) {
      mean += cells64[start + i];
    }
    mean /= len;
    var sumSq = 0.0;
    for (var i = 0; i < len; i++) {
      final d = cells64[start + i] - mean;
      sumSq += d * d;
    }
    return math.sqrt(sumSq / len);
  }

  Future<void> dispose() => _session.close();
}
