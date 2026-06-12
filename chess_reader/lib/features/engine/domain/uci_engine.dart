/// Transport-agnostic UCI engine: desktop talks to a Stockfish process over
/// stdin/stdout, mobile to an in-process FFI build. Consumers only ever see
/// this interface.
abstract class UciEngine {
  /// Starts the engine and completes once it answered `uciok`.
  Future<void> start();

  /// Sends one UCI command (without trailing newline).
  void send(String command);

  /// Engine output, one line per event. Broadcast stream.
  Stream<String> get lines;

  /// Stops the engine. The instance cannot be restarted.
  Future<void> dispose();
}
