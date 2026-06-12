/// One `info` line from a UCI engine, reduced to what the UI shows.
class UciInfo {
  const UciInfo({
    this.depth,
    this.scoreCp,
    this.scoreMate,
    this.nodes,
    this.nps,
    this.pvUci = const [],
  });

  final int? depth;

  /// Centipawns from the side to move's perspective.
  final int? scoreCp;

  /// Moves until mate (negative: side to move gets mated).
  final int? scoreMate;
  final int? nodes;
  final int? nps;

  /// Principal variation as UCI moves (e.g. `e2e4`).
  final List<String> pvUci;

  bool get hasScore => scoreCp != null || scoreMate != null;
}

/// Parses `info ...` lines. Returns null for lines that carry no usable
/// search information (e.g. `info string ...`, currmove-only updates).
UciInfo? parseInfoLine(String line) {
  if (!line.startsWith('info ')) return null;
  final parts = line.split(RegExp(r'\s+'));

  int? depth;
  int? scoreCp;
  int? scoreMate;
  int? nodes;
  int? nps;
  List<String> pv = const [];

  for (var i = 1; i < parts.length; i++) {
    switch (parts[i]) {
      case 'depth':
        depth = int.tryParse(parts[++i]);
      case 'score':
        final kind = parts[++i];
        final value = int.tryParse(parts[++i]);
        if (kind == 'cp') scoreCp = value;
        if (kind == 'mate') scoreMate = value;
      case 'nodes':
        nodes = int.tryParse(parts[++i]);
      case 'nps':
        nps = int.tryParse(parts[++i]);
      case 'string':
        return null;
      case 'pv':
        pv = parts.sublist(i + 1);
        i = parts.length;
    }
  }
  if (depth == null && scoreCp == null && scoreMate == null) return null;
  return UciInfo(
    depth: depth,
    scoreCp: scoreCp,
    scoreMate: scoreMate,
    nodes: nodes,
    nps: nps,
    pvUci: pv,
  );
}

/// Returns the best move of a `bestmove ...` line, or null otherwise.
String? parseBestmove(String line) {
  if (!line.startsWith('bestmove')) return null;
  final parts = line.split(RegExp(r'\s+'));
  return parts.length > 1 ? parts[1] : null;
}
