/// A live source of board positions external to the book — a phone camera
/// watching a physical board, or a Bluetooth smart board (DGT, Chessnut).
///
/// Extension point only (no implementations yet). The vision diagram pipeline
/// and the future camera/BLE pipelines all converge on a stream of FEN +
/// confidence that the game session can consume; defining the contract now
/// keeps those additions from reshaping existing code.
///
/// A camera implementation would reuse `features/vision` (board detection →
/// square classifier → FEN); a BLE implementation would decode the board's
/// protocol. Both would surface here.
abstract class PositionSource {
  /// Human-readable name (e.g. "Camera", "Chessnut Air").
  String get name;

  /// Emits a recognized position whenever the source's board changes.
  Stream<PositionReading> get readings;

  Future<void> start();
  Future<void> stop();
}

class PositionReading {
  const PositionReading({required this.fen, required this.confidence});

  final String fen;

  /// 0..1; consumers may ignore low-confidence readings or require stability
  /// across several frames before applying them.
  final double confidence;
}
