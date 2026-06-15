// Feeds real ONNX-CNN readings (from infer_cells.py) through the SHIPPED Dart
// pipeline — isPlausibleDiagram gate, repairToLegal, assembleFen — and reports
// FEN legality before vs after repair. This is the app's exact post-processing
// on the real model's reading of a real book.
//
// Usage: dart run tool/repair_from_json.dart <readings.json>
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:chess_reader/features/vision/domain/board_repair.dart';
import 'package:chess_reader/features/vision/domain/board_validator.dart';
import 'package:chess_reader/features/vision/domain/fen_assembler.dart';
import 'package:dartchess/dartchess.dart' hide File;

bool isLegalFen(String fen) {
  final parts = fen.split(' ');
  for (final side in ['w', 'b']) {
    parts[1] = side;
    try {
      Chess.fromSetup(Setup.parseFen(parts.join(' ')),
          ignoreImpossibleCheck: true);
      return true;
    } catch (_) {}
  }
  return false;
}

void main(List<String> args) {
  final boards = (jsonDecode(File(args[0]).readAsStringSync()) as List)
      .cast<Map<String, dynamic>>();

  var plausible = 0, baseIllegal = 0, repIllegal = 0, fixed = 0;
  for (final b in boards) {
    final labels = (b['labels'] as List).cast<String>();
    final probs = [
      for (final row in (b['probs'] as List))
        Float32List.fromList([for (final v in (row as List)) (v as num).toDouble()])
    ];
    final confidences = [for (final row in probs) row.reduce((a, c) => a > c ? a : c)];

    // App gate: drop non-board regions before emitting anything.
    if (!isPlausibleDiagram(labels, confidences: confidences)) continue;
    plausible++;

    final base = assembleFen(labels);
    final rep = assembleFen(repairToLegal(labels, probs));
    final baseLegal = isLegalFen(base);
    final repLegal = isLegalFen(rep);
    if (!baseLegal) baseIllegal++;
    if (!repLegal) repIllegal++;
    if (!baseLegal && repLegal) fixed++;

    if (!baseLegal) {
      print('${b['id']}: ${baseLegal ? "legal" : "ILLEGAL"} $base');
      if (base != rep) {
        print('       -> ${repLegal ? "LEGAL  " : "illegal"} $rep');
      }
    }
  }

  print('\n=== real CNN readings through shipped repair ===');
  print('plausible diagrams:    $plausible');
  print('illegal before repair: $baseIllegal');
  print('illegal after repair:  $repIllegal');
  print('rescued by repair:     $fixed');
}
