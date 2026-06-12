/// Builders for "open this position elsewhere" links. Pure functions —
/// unit-tested; launching is the caller's concern.
library;

String lichessAnalysisUrl(String fen) =>
    'https://lichess.org/analysis/standard/${fen.replaceAll(' ', '_')}';

String chessComAnalysisUrl(String fen) =>
    'https://www.chess.com/analysis?fen=${Uri.encodeQueryComponent(fen)}';
