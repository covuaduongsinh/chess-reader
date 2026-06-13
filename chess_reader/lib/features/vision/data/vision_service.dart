import 'package:image/image.dart' as img;

import '../domain/board_locator.dart';
import '../domain/fen_assembler.dart';
import '../domain/square_classifier.dart';

/// A diagram recognized on a page: where it sits (pixel coordinates of the
/// scanned raster) and the position it shows.
class DiagramAnchor {
  const DiagramAnchor({required this.board, required this.fen});

  final LocatedBoard board;
  final String fen;
}

/// Page raster → located boards → 64 cells each → classifier → FEN.
class VisionService {
  VisionService({required this.locator, required this.classifier});

  final BoardLocator locator;
  final SquareClassifier classifier;

  Future<List<DiagramAnchor>> scanPage(img.Image page) async {
    await classifier.ensureReady();
    final anchors = <DiagramAnchor>[];
    for (final board in locator.locate(page)) {
      final inner = _cropInsideFrame(page, board);
      final cell = inner.width / 8;
      final labels = <String>[];
      for (var r = 0; r < 8; r++) {
        for (var f = 0; f < 8; f++) {
          final crop = img.copyCrop(
            inner,
            x: (f * cell).round(),
            y: (r * cell).round(),
            width: cell.round(),
            height: cell.round(),
          );
          labels.add(classifier.classify(crop));
        }
      }
      anchors.add(DiagramAnchor(board: board, fen: assembleFen(labels)));
    }
    return anchors;
  }

  /// Crops the board to the area inside its frame: from each edge, rows and
  /// columns that are almost entirely dark (the printed frame line) are
  /// peeled off. A correct grid origin matters — a few pixels of drift puts
  /// a high-contrast sliver of the neighboring square into every cell.
  img.Image _cropInsideFrame(img.Image page, LocatedBoard board) {
    final gray = img.grayscale(img.copyCrop(
      page,
      x: board.left,
      y: board.top,
      width: board.size,
      height: board.size,
    ));
    final n = gray.width;
    final maxPeel = n ~/ 8;

    double rowDarkness(int y) {
      var dark = 0;
      for (var x = 0; x < n; x++) {
        if (gray.getPixel(x, y).r < 128) dark++;
      }
      return dark / n;
    }

    double colDarkness(int x) {
      var dark = 0;
      for (var y = 0; y < gray.height; y++) {
        if (gray.getPixel(x, y).r < 128) dark++;
      }
      return dark / gray.height;
    }

    var top = 0, bottom = gray.height - 1, left = 0, right = n - 1;
    while (top < maxPeel && rowDarkness(top) > 0.8) {
      top++;
    }
    while (bottom > gray.height - maxPeel && rowDarkness(bottom) > 0.8) {
      bottom--;
    }
    while (left < maxPeel && colDarkness(left) > 0.8) {
      left++;
    }
    while (right > n - maxPeel && colDarkness(right) > 0.8) {
      right--;
    }

    return img.copyCrop(
      page,
      x: board.left + left,
      y: board.top + top,
      width: right - left + 1,
      height: bottom - top + 1,
    );
  }
}
