/// Builds a FEN from 64 per-square labels (rank 8 → rank 1, file a → h,
/// i.e. reading order with White at the bottom).
///
/// A diagram cannot show side to move, castling rights or en passant:
/// side defaults to [whiteToMove] (caption heuristics upstream), castling
/// is inferred from kings/rooks on home squares, en passant is unknown.
String assembleFen(List<String> labels, {bool whiteToMove = true}) {
  assert(labels.length == 64);
  final ranks = <String>[];
  for (var r = 0; r < 8; r++) {
    final buffer = StringBuffer();
    var empty = 0;
    for (var f = 0; f < 8; f++) {
      final label = labels[r * 8 + f];
      if (label.isEmpty) {
        empty++;
      } else {
        if (empty > 0) {
          buffer.write(empty);
          empty = 0;
        }
        buffer.write(label);
      }
    }
    if (empty > 0) buffer.write(empty);
    ranks.add(buffer.toString());
  }
  final placement = ranks.join('/');

  String at(String square) {
    final file = square.codeUnitAt(0) - 'a'.codeUnitAt(0);
    final rank = int.parse(square[1]);
    return labels[(8 - rank) * 8 + file];
  }

  var castling = '';
  if (at('e1') == 'K') {
    if (at('h1') == 'R') castling += 'K';
    if (at('a1') == 'R') castling += 'Q';
  }
  if (at('e8') == 'k') {
    if (at('h8') == 'r') castling += 'k';
    if (at('a8') == 'r') castling += 'q';
  }
  if (castling.isEmpty) castling = '-';

  return '$placement ${whiteToMove ? 'w' : 'b'} $castling - 0 1';
}
