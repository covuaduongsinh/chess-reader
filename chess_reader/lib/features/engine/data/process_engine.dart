import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../domain/uci_engine.dart';

/// Desktop engine: official Stockfish binary spoken to over stdin/stdout.
/// Crashes stay outside the app process — the reader can never go down with
/// the engine.
class ProcessEngine implements UciEngine {
  ProcessEngine(this.executablePath);

  final String executablePath;

  Process? _process;
  final _lines = StreamController<String>.broadcast();

  @override
  Stream<String> get lines => _lines.stream;

  @override
  Future<void> start() async {
    final process = await Process.start(executablePath, const []);
    _process = process;
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_lines.add, onDone: () {
      if (!_lines.isClosed) _lines.close();
    });
    process.stderr.drain<void>();

    final uciok = lines.firstWhere((l) => l == 'uciok');
    send('uci');
    await uciok.timeout(const Duration(seconds: 10));
  }

  @override
  void send(String command) {
    _process?.stdin.writeln(command);
  }

  @override
  Future<void> dispose() async {
    final process = _process;
    if (process == null) return;
    send('quit');
    _process = null;
    try {
      await process.exitCode.timeout(const Duration(seconds: 3));
    } on TimeoutException {
      process.kill();
    }
    if (!_lines.isClosed) await _lines.close();
  }
}
