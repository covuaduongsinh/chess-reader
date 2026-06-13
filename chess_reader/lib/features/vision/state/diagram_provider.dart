import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

import '../data/onnx_square_classifier.dart';
import '../data/vision_isolate.dart';
import '../domain/fen_assembler.dart';

/// A diagram recognized on a page, in raster pixel coordinates plus its FEN.
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

/// Recognized diagrams per PDF page, keyed by `sourceName#pageNumber`.
/// Pages are scanned on demand ("scan this page" button) and cached.
///
/// Flow: render page (pdfrx, native) → extract+preprocess board cells in an
/// isolate (heavy pure-Dart CV) → classify with ONNX on the main isolate
/// (native, non-blocking) → assemble FEN.
class DiagramScans extends Notifier<Map<String, List<ScanResult>>> {
  final Set<String> _inFlight = {};
  OnnxSquareClassifier? _classifier;
  bool _classifierLoaded = false;

  @override
  Map<String, List<ScanResult>> build() {
    ref.onDispose(() => _classifier?.dispose());
    return const {};
  }

  bool isScanning(PdfPage page) => _inFlight.contains(_key(page));

  List<ScanResult>? resultsFor(PdfPage page) => state[_key(page)];

  Future<void> scan(PdfPage page) async {
    final key = _key(page);
    if (_inFlight.contains(key) || state.containsKey(key)) return;
    _inFlight.add(key);
    ref.notifyListeners();
    try {
      const scale = 200 / 72; // PDF points are 72 dpi → ~200 dpi raster.
      final image = await page.render(
        fullWidth: page.width * scale,
        fullHeight: page.height * scale,
      );
      if (image == null) return;

      final boards = await extractBoardsInIsolate(ExtractRequest(
        bgra: image.pixels,
        width: image.width,
        height: image.height,
      ));
      image.dispose();

      final classifier = await _ensureClassifier();
      final results = <ScanResult>[];
      for (final board in boards) {
        if (classifier == null) continue;
        final labels = await classifier.classifyBoard(board.cells);
        results.add(ScanResult(
          left: board.left,
          top: board.top,
          size: board.size,
          fen: assembleFen(labels),
        ));
      }
      state = {...state, key: results};
    } finally {
      _inFlight.remove(key);
      ref.notifyListeners();
    }
  }

  Future<OnnxSquareClassifier?> _ensureClassifier() async {
    if (_classifierLoaded) return _classifier;
    _classifier = await OnnxSquareClassifier.tryLoad();
    _classifierLoaded = true;
    return _classifier;
  }

  String _key(PdfPage page) =>
      '${page.document.sourceName}#${page.pageNumber}';
}

final diagramScansProvider =
    NotifierProvider<DiagramScans, Map<String, List<ScanResult>>>(
        DiagramScans.new);
