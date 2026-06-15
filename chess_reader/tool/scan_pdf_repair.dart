// Diagnostic: scan PDF pages, locate boards, and report FEN legality BEFORE vs
// AFTER repairToLegal — so we can measure how many illegal readings the repair
// layer rescues on a real book.
//
// NOTE: this runs the pure-Dart TEMPLATE classifier (the only path that works
// headlessly). The shipped app uses the ONNX CNN, which needs the Flutter
// runtime. The template path has no per-class distribution, so we feed repair a
// one-hot prob per cell: that still exercises the legality guarantee (offenders
// fall back to empty) but can't show the "next-best piece" behaviour the CNN's
// real softmax enables.
//
// Usage: dart run tool/scan_pdf_repair.dart <book.pdf> <fromPage> <toPage>
// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:typed_data';

import 'package:chess_reader/features/vision/domain/board_locator.dart';
import 'package:chess_reader/features/vision/domain/board_repair.dart';
import 'package:chess_reader/features/vision/domain/board_slicer.dart';
import 'package:chess_reader/features/vision/domain/board_validator.dart';
import 'package:chess_reader/features/vision/domain/fen_assembler.dart';
import 'package:chess_reader/features/vision/domain/square_classifier.dart';
import 'package:dartchess/dartchess.dart' hide File;
import 'package:image/image.dart' as img;
import 'package:pdfrx_engine/pdfrx_engine.dart';

const _order = [
  'K', 'Q', 'R', 'B', 'N', 'P', 'k', 'q', 'r', 'b', 'n', 'p', '' //
];

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

/// Mirrors board_loader.tryLoadFen's notion of "legal": parseable, and a legal
/// Position for some side-to-move (impossible check ignored).
bool isLegalFen(String fen) {
  final parts = fen.split(' ');
  for (final side in ['w', 'b']) {
    parts[1] = side;
    try {
      final setup = Setup.parseFen(parts.join(' '));
      Chess.fromSetup(setup, ignoreImpossibleCheck: true);
      return true;
    } catch (_) {}
  }
  return false;
}

List<Float32List> oneHot(List<String> labels) => [
      for (final l in labels) Float32List(13)..[_order.indexOf(l)] = 1.0,
    ];

Future<void> main(List<String> args) async {
  final from = int.parse(args[1]);
  final to = int.parse(args[2]);
  await pdfrxInitialize();
  final doc = await PdfDocument.openFile(args[0]);
  final classifier = TemplateSquareClassifier(loadPiece);
  await classifier.ensureReady();
  const locator = ConnectedComponentBoardLocator();

  var boards = 0, plausible = 0, baselineIllegal = 0, repairedIllegal = 0;
  var fixed = 0;

  for (var pageNum = from; pageNum <= to && pageNum <= doc.pages.length;
      pageNum++) {
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

    for (final board in locator.locate(image)) {
      boards++;
      final cells = sliceBoardCells(image, board);
      final labels = [for (final c in cells) classifier.classify(c)];
      if (!isPlausibleDiagram(labels)) continue;
      plausible++;

      final base = assembleFen(labels);
      final baseLegal = isLegalFen(base);
      final repaired = assembleFen(repairToLegal(labels, oneHot(labels)));
      final repLegal = isLegalFen(repaired);

      if (!baseLegal) baselineIllegal++;
      if (!repLegal) repairedIllegal++;
      if (!baseLegal && repLegal) fixed++;

      if (!baseLegal || base != repaired) {
        print('p$pageNum sz${board.size}  '
            '${baseLegal ? "legal " : "ILLEGAL"} $base');
        if (base != repaired) {
          print('        -> ${repLegal ? "legal " : "ILLEGAL"} $repaired');
        }
      }
    }
  }

  print('\n=== pages $from-$to ===');
  print('located boards:        $boards');
  print('plausible diagrams:    $plausible');
  print('illegal before repair: $baselineIllegal');
  print('illegal after repair:  $repairedIllegal');
  print('rescued by repair:     $fixed');
  doc.dispose();
}
