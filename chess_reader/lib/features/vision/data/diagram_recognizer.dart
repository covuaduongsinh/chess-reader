import 'dart:typed_data';

import '../domain/board_validator.dart';
import '../domain/fen_assembler.dart';
import 'onnx_square_classifier.dart';
import 'vision_isolate.dart';

/// A diagram recognized in an image: where it sits (raster pixels of the
/// source image), the assembled FEN, and a PNG crop of the board region.
class RecognizedDiagram {
  const RecognizedDiagram({
    required this.left,
    required this.top,
    required this.size,
    required this.fen,
    required this.cropPng,
  });

  final int left;
  final int top;
  final int size;
  final String fen;
  final Uint8List cropPng;
}

/// Finds printed chess diagrams in page rasters (PDF) or encoded images
/// (EPUB `<img>`) and assembles a FEN for each. Reuses the shared pipeline:
/// CV board location + cell preprocessing in an isolate, ONNX square
/// classification on the main isolate.
///
/// Holds one lazily-loaded classifier; create one per conversion run and
/// [dispose] it when done.
class DiagramRecognizer {
  OnnxSquareClassifier? _classifier;
  bool _loaded = false;

  Future<OnnxSquareClassifier?> _ensureClassifier() async {
    if (_loaded) return _classifier;
    _classifier = await OnnxSquareClassifier.tryLoad();
    _loaded = true;
    return _classifier;
  }

  /// Recognizes diagrams in a rendered page (BGRA pixels, e.g. from pdfrx).
  Future<List<RecognizedDiagram>> recognizePage({
    required Uint8List bgra,
    required int width,
    required int height,
  }) async {
    final boards = await extractBoardsInIsolate(
      ExtractRequest(bgra: bgra, width: width, height: height),
    );
    return _classify(boards);
  }

  /// Recognizes diagrams in an encoded image (PNG/JPEG/GIF).
  Future<List<RecognizedDiagram>> recognizeEncoded(Uint8List bytes) async {
    final boards = await extractBoardsFromEncodedInIsolate(bytes);
    return _classify(boards);
  }

  Future<List<RecognizedDiagram>> _classify(
      List<ExtractedBoard> boards) async {
    if (boards.isEmpty) return const [];
    final classifier = await _ensureClassifier();
    if (classifier == null) return const [];
    final out = <RecognizedDiagram>[];
    for (final b in boards) {
      final result = await classifier.classifyBoard(b.cells);
      // Drop empty grids, photos/figures and other non-board regions the
      // locator picked up: only emit confidently-read, populated positions.
      if (!isPlausibleDiagram(result.labels,
          confidences: result.confidences)) {
        continue;
      }
      out.add(RecognizedDiagram(
        left: b.left,
        top: b.top,
        size: b.size,
        fen: assembleFen(result.labels),
        cropPng: b.cropPng,
      ));
    }
    return out;
  }

  Future<void> dispose() async {
    await _classifier?.dispose();
    _classifier = null;
  }
}
