// Exports the sliced board cells of diagrams found on PDF pages, so the ONNX
// model can be validated on real print fonts (run the cells through Python
// eval). Uses the real sliceBoardCells, so slicing matches the app exactly.
//
// Usage: dart run tool/dump_board_cells.dart <book.pdf> <outDir> <page> [page...]
// Writes <outDir>/p<page>_b<idx>/cell_<rr><ff>.png (rr=rank row 0-7, ff=file).
// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:typed_data';

import 'package:chess_reader/features/vision/domain/board_locator.dart';
import 'package:chess_reader/features/vision/domain/board_slicer.dart';
import 'package:image/image.dart' as img;
import 'package:pdfrx_engine/pdfrx_engine.dart';

Future<void> main(List<String> args) async {
  if (args.length < 3) {
    stderr.writeln(
        'usage: dart run tool/dump_board_cells.dart <pdf> <outDir> <page>...');
    exit(2);
  }
  final outDir = args[1];
  await pdfrxInitialize();
  final doc = await PdfDocument.openFile(args[0]);
  const locator = ConnectedComponentBoardLocator();

  for (final pageNum in args.skip(2).map(int.parse)) {
    final page = doc.pages[pageNum - 1];
    const scale = 200 / 72;
    final pdfImage = await page.render(
      fullWidth: page.width * scale,
      fullHeight: page.height * scale,
    );
    if (pdfImage == null) continue;
    final image = img.Image.fromBytes(
      width: pdfImage.width,
      height: pdfImage.height,
      bytes: pdfImage.pixels.buffer,
      order: img.ChannelOrder.bgra,
    );
    final boards = locator.locate(image);
    print('page $pageNum: ${boards.length} board(s)');
    for (var b = 0; b < boards.length; b++) {
      final cells = sliceBoardCells(image, boards[b]);
      final dir = Directory('$outDir/p${pageNum}_b$b')..createSync(recursive: true);
      // Whole-board crop (for prototyping image-level annotation detection).
      final crop = img.copyCrop(image,
          x: boards[b].left,
          y: boards[b].top,
          width: boards[b].size,
          height: boards[b].size);
      File('${dir.path}/board.png')
          .writeAsBytesSync(Uint8List.fromList(img.encodePng(crop)));
      for (var i = 0; i < 64; i++) {
        final rr = i ~/ 8, ff = i % 8;
        final png = img.encodePng(cells[i]);
        File('${dir.path}/cell_$rr$ff.png').writeAsBytesSync(Uint8List.fromList(png));
      }
      print('  board $b at (${boards[b].left},${boards[b].top}) '
          'size ${boards[b].size} -> ${dir.path}');
    }
  }
  doc.dispose();
}
