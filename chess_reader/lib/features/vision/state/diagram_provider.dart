import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

import '../data/vision_isolate.dart';

/// Recognized diagrams per PDF page, keyed by `sourceName#pageNumber`.
/// Pages are scanned on demand ("scan this page" button) and cached.
class DiagramScans extends Notifier<Map<String, List<ScanResult>>> {
  final Set<String> _inFlight = {};

  @override
  Map<String, List<ScanResult>> build() => const {};

  bool isScanning(PdfPage page) => _inFlight.contains(_key(page));

  List<ScanResult>? resultsFor(PdfPage page) => state[_key(page)];

  /// Renders [page] at ~200 dpi and scans it for diagrams.
  Future<void> scan(PdfPage page) async {
    final key = _key(page);
    if (_inFlight.contains(key) || state.containsKey(key)) return;
    _inFlight.add(key);
    ref.notifyListeners();
    try {
      final scale = 200 / 72; // PDF points are 72 dpi.
      final image = await page.render(
        fullWidth: page.width * scale,
        fullHeight: page.height * scale,
      );
      if (image == null) return;
      final results = await scanPageInIsolate(ScanRequest(
        bgra: image.pixels,
        width: image.width,
        height: image.height,
        templatePngs: await _loadTemplates(),
      ));
      image.dispose();
      state = {...state, key: results};
    } finally {
      _inFlight.remove(key);
      ref.notifyListeners();
    }
  }

  String _key(PdfPage page) =>
      '${page.document.sourceName}#${page.pageNumber}';

  static Map<String, Uint8List>? _templateCache;

  Future<Map<String, Uint8List>> _loadTemplates() async {
    if (_templateCache != null) return _templateCache!;
    const ids = [
      'wK', 'wQ', 'wR', 'wB', 'wN', 'wP',
      'bK', 'bQ', 'bR', 'bB', 'bN', 'bP',
    ];
    final map = <String, Uint8List>{};
    for (final id in ids) {
      final data = await rootBundle
          .load('packages/chessground/assets/piece_sets/merida/$id.png');
      map[id] = data.buffer.asUint8List();
    }
    return _templateCache = map;
  }
}

final diagramScansProvider =
    NotifierProvider<DiagramScans, Map<String, List<ScanResult>>>(
        DiagramScans.new);
