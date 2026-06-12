/// Normalizes book text so the tokenizer sees plain SAN.
///
/// Two layers:
/// 1. Standard Unicode figurines (♘ → N) — always applied.
/// 2. Font profiles: ordered, context-anchored rules for fonts that extract
///    as garbage sequences (no ToUnicode table). Profiles were built
///    empirically with `tool/dump_pdf_text.dart`; see
///    docs/figurine-extraction-notes.md. All profiles are applied — rules are
///    written with enough context (lookaheads) to be no-ops on other books,
///    and a wrong repair still has to pass the resolver's legality check.
library;

const Map<int, String> _unicodeFigurines = {
  // White pieces.
  0x2654: 'K', 0x2655: 'Q', 0x2656: 'R', 0x2657: 'B', 0x2658: 'N',
  // Black pieces map to the same SAN letters: notation is color-agnostic.
  0x265A: 'K', 0x265B: 'Q', 0x265C: 'R', 0x265D: 'B', 0x265E: 'N',
  // Pawn figurines: pawn moves carry no letter in SAN.
  0x2659: '', 0x265F: '',
};

/// One anchored rewrite rule: when [pattern] matches at the current scan
/// position, emit [replacement] instead.
class _Rule {
  _Rule(String pattern, this.replacement) : pattern = RegExp(pattern);
  final RegExp pattern;
  final String replacement;
}

/// A square, capture or disambiguated destination must follow for
/// piece-sequence rules to fire — this is what keeps them from mangling
/// prose ("i.e." stays untouched because "e." is not a square). `l` is
/// accepted as a rank digit because this font prints rank 1 as lowercase L;
/// the digit-repair rule fixes it afterwards.
const _sq = r'(?=[a-h1-8]?x?[a-h][1-8l]|[a-h]?x)';

/// Gambit Publications house font (e.g. "Secrets of Positional Chess").
final List<_Rule> _gambitRules = [
  // Knight: lt:J etc.
  _Rule('lt:J$_sq', 'N'),
  _Rule("lt'l$_sq", 'N'),
  _Rule('lLl$_sq', 'N'),
  _Rule('ll:l$_sq', 'N'),
  _Rule("ll'l$_sq", 'N'),
  _Rule('ttJ$_sq', 'N'),
  _Rule('tt:J$_sq', 'N'),
  // Rook: many ligature variants.
  _Rule(r'l:!\.' + _sq, 'R'),
  _Rule(r'l:r\.' + _sq, 'R'),
  _Rule('l::t$_sq', 'R'),
  _Rule('l:t$_sq', 'R'),
  _Rule(r'l!\.' + _sq, 'R'),
  _Rule('ll$_sq', 'R'),
  // Bishop.
  _Rule(r'i\.' + _sq, 'B'),
  // Queen: leading quote/degree + iV / ii' / ilf soup.
  _Rule('["\'°]i[Vi]\'?$_sq', 'Q'),
  _Rule("'ilf$_sq", 'Q'),
  _Rule('"ii\'?$_sq', 'Q'),
  _Rule('°ii\'?$_sq', 'Q'),
  _Rule("°i:i'?$_sq", 'Q'),
  _Rule('iV$_sq', 'Q'),
  // King: unmapped glyph collapsed to U+FFFD by PDFium.
  _Rule('�(?=[a-h]?[1-8l])', 'K'),
  // "..." printed as bullets.
  _Rule('•', '.'),
  // Bold-font glyph collisions, tightly scoped:
  // "f5" prints as the standalone word "rs"; rank 5 as capital S ("exfS").
  // Rank 1 printing as lowercase L ("Qcl" = Qc1) is handled by the
  // tokenizer, whose word boundaries protect prose like "personal".
  _Rule(r'(?<![A-Za-z])rs(?![A-Za-z0-9])', 'f5'),
  _Rule('(?<=[a-h])S(?![A-Za-z0-9])', '5'),
];

/// Result of normalizing book text: figurines replaced by SAN letters, plus
/// a map from each code unit of [text] back to its offset in the original
/// string (needed to draw tap targets over the original glyphs).
class NormalizedText {
  const NormalizedText(this.text, this.sourceOffsets);

  final String text;

  /// `sourceOffsets[i]` is the offset in the original string of the character
  /// that produced `text[i]`. Length is `text.length + 1`; the final entry
  /// maps the end of the normalized text to the end of the original.
  final List<int> sourceOffsets;
}

NormalizedText normalizeFigurines(String original) {
  final buffer = StringBuffer();
  final offsets = <int>[];
  var i = 0;
  scan:
  while (i < original.length) {
    for (final rule in _gambitRules) {
      final match = rule.pattern.matchAsPrefix(original, i);
      if (match != null && match.end > match.start) {
        buffer.write(rule.replacement);
        for (var j = 0; j < rule.replacement.length; j++) {
          offsets.add(i);
        }
        i = match.end;
        continue scan;
      }
    }
    final code = original.codeUnitAt(i);
    final mapped = _unicodeFigurines[code];
    if (mapped == null) {
      buffer.writeCharCode(code);
      offsets.add(i);
    } else {
      buffer.write(mapped);
      for (var j = 0; j < mapped.length; j++) {
        offsets.add(i);
      }
    }
    i++;
  }
  offsets.add(original.length);
  return NormalizedText(buffer.toString(), offsets);
}
