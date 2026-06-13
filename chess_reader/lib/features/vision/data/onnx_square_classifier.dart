import 'dart:typed_data';

import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

import '../domain/board_slicer.dart';
import '../domain/square_classifier.dart';

/// Class order MUST match `CLASSES` in tool/vision_train/model.py. Shares the
/// [squareLabels] contract used by the template classifier.
const List<String> kModelClasses = squareLabels;

const String kSquareModelAsset = 'assets/models/square_classifier.onnx';

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
  /// length [kCellSize]². Returns 64 FEN labels.
  Future<List<String>> classifyBoard(Float32List cells64) async {
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
        labels.add(kModelClasses[best]);
      }
      return labels;
    } finally {
      await input.dispose();
    }
  }

  Future<void> dispose() => _session.close();
}
