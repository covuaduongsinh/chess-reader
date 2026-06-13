// Diagnostic: scan PDF pages for chess diagrams and print recognized FENs.
// Usage: dart run tool/scan_pdf_page.dart <book.pdf> <page> [page...]
// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:typed_data';

import 'package:chess_reader/features/vision/data/vision_service.dart';
import 'package:chess_reader/features/vision/domain/board_locator.dart';
import 'package:chess_reader/features/vision/domain/square_classifier.dart';
import 'package:image/image.dart' as img;
import 'package:pdfrx_engine/pdfrx_engine.dart';

Future<Uint8List> loadPiece(String id) async {
  final cache = Platform.environment['PUB_CACHE'] ??
      '${Platform.environment['LOCALAPPDATA']}\\Pub\\Cache';
  final hosted = Directory('$cache\\hosted\\pub.dev');
  final dir = hosted
      .listSync()
      .whereType<Directory>()
      .lastWhere((d) => d.path.contains('chessground-'));
  for (final rel in [
    'assets\\piece_sets\\merida\\$id.png',
    'lib\\piece_sets\\merida\\$id.png',
  ]) {
    final f = File('${dir.path}\\$rel');
    if (f.existsSync()) return f.readAsBytes();
  }
  throw StateError('piece $id not found');
}

Future<void> main(List<String> args) async {
  await pdfrxInitialize();
  final doc = await PdfDocument.openFile(args[0]);
  final service = VisionService(
    locator: const ConnectedComponentBoardLocator(),
    classifier: TemplateSquareClassifier(loadPiece),
  );
  for (final pageNum in args.skip(1).map(int.parse)) {
    final page = doc.pages[pageNum - 1];
    const scale = 200 / 72;
    final pdfImage = await page.render(
      fullWidth: page.width * scale,
      fullHeight: page.height * scale,
    );
    if (pdfImage == null) {
      print('page $pageNum: render failed');
      continue;
    }
    final image = img.Image.fromBytes(
      width: pdfImage.width,
      height: pdfImage.height,
      bytes: pdfImage.pixels.buffer,
      order: img.ChannelOrder.bgra,
    );
    final anchors = await service.scanPage(image);
    print('page $pageNum: ${anchors.length} diagram(s)');
    for (final a in anchors) {
      print('  at (${a.board.left},${a.board.top}) size ${a.board.size}: '
          '${a.fen}');
    }
  }
  doc.dispose();
}
