import 'dart:io';

import 'package:path/path.dart' as p;

/// Finds the Stockfish executable on desktop platforms.
///
/// Search order:
/// 1. `STOCKFISH_PATH` environment variable
/// 2. next to the app executable (release bundle: `data/engines/`, copied
///    there by the platform build — see windows/CMakeLists.txt)
/// 3. the project's `assets/engines/` directory (development runs, where the
///    working directory is the project root)
/// 4. `stockfish` on PATH
String? locateStockfish() {
  final envPath = Platform.environment['STOCKFISH_PATH'];
  if (envPath != null && File(envPath).existsSync()) return envPath;

  final ext = Platform.isWindows ? '.exe' : '';
  final exeDir = p.dirname(Platform.resolvedExecutable);
  final candidates = [
    p.join(exeDir, 'data', 'engines', 'stockfish$ext'),
    p.join(exeDir, 'engines', 'stockfish$ext'),
    p.join(exeDir, 'stockfish$ext'),
    // Dev fallback: flutter run / tests execute with cwd = project root.
    p.join(Directory.current.path, 'assets', 'engines',
        'stockfish-windows-x86-64-avx2.exe'),
  ];
  for (final c in candidates) {
    if (File(c).existsSync()) return c;
  }

  // Last resort: PATH lookup.
  final which = Platform.isWindows ? 'where' : 'which';
  try {
    final result = Process.runSync(which, ['stockfish']);
    if (result.exitCode == 0) {
      final found = (result.stdout as String).trim().split('\n').first.trim();
      if (found.isNotEmpty && File(found).existsSync()) return found;
    }
  } on ProcessException {
    // `where`/`which` unavailable: give up.
  }
  return null;
}
