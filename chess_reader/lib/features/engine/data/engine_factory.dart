import 'dart:io';

import '../domain/uci_engine.dart';
import 'engine_locator.dart';
import 'ffi_engine.dart';
import 'process_engine.dart';

/// Thrown when no engine is available on this machine (desktop without a
/// bundled or installed Stockfish).
class EngineUnavailable implements Exception {
  const EngineUnavailable(this.message);
  final String message;

  @override
  String toString() => message;
}

UciEngine createEngine() {
  if (Platform.isAndroid || Platform.isIOS) {
    return FfiEngine();
  }
  final path = locateStockfish();
  if (path == null) {
    throw const EngineUnavailable(
      'Stockfish not found. Place the binary in assets/engines/ or set '
      'STOCKFISH_PATH.',
    );
  }
  return ProcessEngine(path);
}
