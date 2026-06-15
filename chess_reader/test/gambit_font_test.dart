import 'package:flutter_test/flutter_test.dart';

import 'package:chess_reader/features/reader/domain/figurine_map.dart';
import 'package:chess_reader/features/reader/domain/move_resolver.dart';
import 'package:chess_reader/features/reader/domain/san_tokenizer.dart';

void main() {
  group('Gambit font profile', () {
    test('maps piece sequences observed in the test book', () {
      expect(normalizeFigurines('lt:Jf6').text, 'Nf6');
      expect(normalizeFigurines('i.e3').text, 'Be3');
      expect(normalizeFigurines('l:!.c3').text, 'Rc3');
      expect(normalizeFigurines('l:r.c3').text, 'Rc3');
      expect(normalizeFigurines('llh3').text, 'Rh3');
      expect(normalizeFigurines('"iVf2').text, 'Qf2');
      expect(normalizeFigurines("°ii'h6").text, 'Qh6');
      expect(normalizeFigurines('�g2').text, 'Kg2');
      expect(normalizeFigurines("ll'lf7+").text, 'Nf7+');
    });

    test('maps mid-book variants seen on page 15 (Petrosian–Larsen)', () {
      // Knight without the colon, and the "4J" form.
      expect(normalizeFigurines('ltJe8').text, 'Ne8');
      expect(normalizeFigurines('ltJg7').text, 'Ng7');
      expect(normalizeFigurines('4Jf5').text, 'Nf5');
      expect(normalizeFigurines('4Jxf6').text, 'Nxf6');
      // Queen variants "il and 'fi.
      expect(normalizeFigurines('"ile7').text, 'Qe7');
      expect(normalizeFigurines("'fia7").text, 'Qa7');
      // The new rules stay no-ops on prose.
      expect(normalizeFigurines("the final word").text, 'the final word');
      expect(normalizeFigurines('a literal').text, 'a literal');
    });

    test('repairs bold-font glyph collisions in move context only', () {
      // Rank 1 prints as lowercase L; the tokenizer repairs it inside move
      // tokens only.
      expect(SanTokenizer.tokenize("29 °ii'cl").single.san, 'Qc1');
      expect(SanTokenizer.tokenize('14 l:!.fdl').single.san, 'Rfd1');
      expect(normalizeFigurines('exfS').text, 'exf5'); // 5 prints as S
      expect(normalizeFigurines('32 rs').text, '32 f5'); // f5 prints as rs
      // Prose stays untouched.
      expect(normalizeFigurines('i.e. the plan').text, 'i.e. the plan');
      expect(normalizeFigurines('all the moves').text, 'all the moves');
      expect(normalizeFigurines('personal').text, 'personal');
      expect(SanTokenizer.tokenize('a personal deal, ideally'), isEmpty);
    });

    test('bullets become dots so black move numbers parse', () {
      final tokens = SanTokenizer.tokenize('26 ••• �e8 27 �e3');
      expect(tokens.map((t) => t.san).toList(), ['Ke8', 'Ke3']);
      expect(tokens[0].moveNumber, 26);
      expect(tokens[0].isWhiteHint, false);
      expect(tokens[1].isWhiteHint, true);
    });

    test('bare move numbers without dots (Gambit style)', () {
      final tokens = SanTokenizer.tokenize('38 l:r.c3 c5! 39 g4?');
      expect(tokens.map((t) => t.san).toList(), ['Rc3', 'c5', 'g4']);
      expect(tokens[0].moveNumber, 38);
      expect(tokens[0].isWhiteHint, true);
      expect(tokens[1].moveNumber, 38);
      expect(tokens[1].isWhiteHint, false);
    });
  });

  group('MoveResolver v2', () {
    test('reseeds at a new game start mid-text', () {
      final tokens = SanTokenizer.tokenize(
          '1.d4 d5 2.c4 dxc4 and later, a new game: 1.e4 e5 2.Nf3 Nc6');
      final line = MoveResolver.resolve(tokens);
      expect(line.moves.map((m) => m.token.san).toList(),
          ['d4', 'd5', 'c4', 'dxc4', 'e4', 'e5', 'Nf3', 'Nc6']);
      // The second game's e4 must come from the initial position.
      expect(line.moves[4].positionBefore.fullmoves, 1);
    });

    test('move-number resync recovers prose-embedded variations', () {
      // "3.Nc3 loses to ... However, 3.Nf3 is better": both 3rd moves must
      // resolve from the same branch point.
      final tokens = SanTokenizer.tokenize(
          '1.d4 d5 2.c4 e6 3.Nc3 is one option. However, 3.Nf3 keeps it calm '
          'and after 3...Nf6 4.g3 White is comfortable.');
      final line = MoveResolver.resolve(tokens);
      final sans = line.moves.map((m) => m.token.san).toList();
      expect(sans, ['d4', 'd5', 'c4', 'e6', 'Nc3', 'Nf3', 'Nf6', 'g3']);
      final nc3 = line.moves[4];
      final nf3 = line.moves[5];
      expect(nf3.positionBefore.fen, nc3.positionBefore.fen);
    });
  });
}
