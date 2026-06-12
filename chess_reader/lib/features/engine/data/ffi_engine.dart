import 'dart:async';

import 'package:multistockfish/multistockfish.dart';

import '../domain/uci_engine.dart';

/// Mobile engine: lichess's multistockfish FFI build (SF16 with embedded
/// NNUE — fully offline). The underlying plugin is a singleton, matching our
/// app-wide single engine instance.
class FfiEngine implements UciEngine {
  final Stockfish _stockfish = Stockfish.instance;

  @override
  Stream<String> get lines => _stockfish.stdout;

  @override
  Future<void> start() async {
    // start() already performs the `uci`/`uciok` handshake internally.
    await _stockfish.start(flavor: StockfishFlavor.sf16);
  }

  @override
  void send(String command) {
    _stockfish.stdin = command;
  }

  @override
  Future<void> dispose() => _stockfish.quit();
}
