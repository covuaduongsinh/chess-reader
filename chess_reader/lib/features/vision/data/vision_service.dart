import 'package:image/image.dart' as img;

import '../domain/board_locator.dart';
import '../domain/board_slicer.dart';
import '../domain/board_validator.dart';
import '../domain/fen_assembler.dart';
import '../domain/square_classifier.dart';

/// A diagram recognized on a page: where it sits (pixel coordinates of the
/// scanned raster) and the position it shows.
class DiagramAnchor {
  const DiagramAnchor({required this.board, required this.fen});

  final LocatedBoard board;
  final String fen;
}

/// Synchronous, template-based recognition: page raster → located boards →
/// 64 cells → [SquareClassifier] → FEN.
///
/// Used in tests and as an offline fallback. The app's primary path is the
/// ONNX classifier (see vision_isolate.dart + onnx_square_classifier.dart),
/// which is more accurate on print fonts.
class VisionService {
  VisionService({required this.locator, required this.classifier});

  final BoardLocator locator;
  final SquareClassifier classifier;

  Future<List<DiagramAnchor>> scanPage(img.Image page) async {
    await classifier.ensureReady();
    final anchors = <DiagramAnchor>[];
    for (final board in locator.locate(page)) {
      final cells = sliceBoardCells(page, board);
      final labels = [for (final c in cells) classifier.classify(c)];
      // Structural plausibility only — the template classifier reports no
      // probabilities. Drops empty grids and other non-board regions.
      if (!isPlausibleDiagram(labels)) continue;
      anchors.add(DiagramAnchor(board: board, fen: assembleFen(labels)));
    }
    return anchors;
  }
}
