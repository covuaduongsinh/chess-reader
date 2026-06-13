import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../domain/board_locator.dart';
import '../domain/board_slicer.dart';

/// Sendable scan input: raw page pixels (BGRA from pdfrx).
class ExtractRequest {
  const ExtractRequest({
    required this.bgra,
    required this.width,
    required this.height,
  });

  final Uint8List bgra;
  final int width;
  final int height;
}

/// One located board with its 64 preprocessed cells (row-major, each
/// [kCellSize]² floats) ready for the model. Sendable across isolates.
class ExtractedBoard {
  const ExtractedBoard({
    required this.left,
    required this.top,
    required this.size,
    required this.cells,
  });

  final int left;
  final int top;
  final int size;
  final Float32List cells;
}

List<ExtractedBoard> _extract(ExtractRequest request) {
  final page = img.Image.fromBytes(
    width: request.width,
    height: request.height,
    bytes: request.bgra.buffer,
    order: img.ChannelOrder.bgra,
  );
  const locator = ConnectedComponentBoardLocator();
  const cellLen = kCellSize * kCellSize;

  final boards = <ExtractedBoard>[];
  for (final board in locator.locate(page)) {
    final cells = sliceBoardCells(page, board);
    final packed = Float32List(64 * cellLen);
    for (var i = 0; i < 64; i++) {
      packed.setRange(i * cellLen, (i + 1) * cellLen, preprocessCell(cells[i]));
    }
    boards.add(ExtractedBoard(
      left: board.left,
      top: board.top,
      size: board.size,
      cells: packed,
    ));
  }
  return boards;
}

/// Locates diagrams and preprocesses their cells off the UI thread. The
/// returned tensors are classified by the ONNX model on the main isolate.
Future<List<ExtractedBoard>> extractBoardsInIsolate(ExtractRequest request) =>
    compute(_extract, request);
