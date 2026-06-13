import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../domain/board_locator.dart';
import '../domain/square_classifier.dart';
import 'vision_service.dart';

/// Sendable scan input: raw page pixels plus the template PNGs (the isolate
/// cannot touch rootBundle).
class ScanRequest {
  const ScanRequest({
    required this.bgra,
    required this.width,
    required this.height,
    required this.templatePngs,
  });

  final Uint8List bgra;
  final int width;
  final int height;
  final Map<String, Uint8List> templatePngs;
}

/// Sendable scan output, page-pixel coordinates.
class ScanResult {
  const ScanResult({
    required this.left,
    required this.top,
    required this.size,
    required this.fen,
  });

  final int left;
  final int top;
  final int size;
  final String fen;
}

Future<List<ScanResult>> _scan(ScanRequest request) async {
  final page = img.Image.fromBytes(
    width: request.width,
    height: request.height,
    bytes: request.bgra.buffer,
    order: img.ChannelOrder.bgra,
  );
  final service = VisionService(
    locator: const ConnectedComponentBoardLocator(),
    classifier: TemplateSquareClassifier(
      (id) async => request.templatePngs[id]!,
    ),
  );
  final anchors = await service.scanPage(page);
  return [
    for (final a in anchors)
      ScanResult(
        left: a.board.left,
        top: a.board.top,
        size: a.board.size,
        fen: a.fen,
      ),
  ];
}

/// Runs the diagram scan off the UI thread.
Future<List<ScanResult>> scanPageInIsolate(ScanRequest request) =>
    compute(_scan, request);
