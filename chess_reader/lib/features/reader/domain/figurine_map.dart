/// Maps figurine chess glyphs to SAN piece letters.
///
/// Standard Unicode chess symbols are handled here. PDF chess fonts without
/// ToUnicode tables surface as Private Use Area codepoints; per-font override
/// tables are added to [puaOverrides] as they are discovered in real books
/// (Phase 3).
library;

const Map<int, String> _unicodeFigurines = {
  // White pieces.
  0x2654: 'K', 0x2655: 'Q', 0x2656: 'R', 0x2657: 'B', 0x2658: 'N',
  // Black pieces map to the same SAN letters: notation is color-agnostic.
  0x265A: 'K', 0x265B: 'Q', 0x265C: 'R', 0x265D: 'B', 0x265E: 'N',
  // Pawn figurines: pawn moves carry no letter in SAN.
  0x2659: '', 0x265F: '',
};

/// Per-font PUA codepoint → SAN letter tables, discovered empirically from
/// test books. Applied on top of the standard table.
const Map<int, String> puaOverrides = {};

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
  for (var i = 0; i < original.length; i++) {
    final code = original.codeUnitAt(i);
    final mapped = puaOverrides[code] ?? _unicodeFigurines[code];
    if (mapped == null) {
      buffer.writeCharCode(code);
      offsets.add(i);
    } else {
      buffer.write(mapped);
      for (var j = 0; j < mapped.length; j++) {
        offsets.add(i);
      }
    }
  }
  offsets.add(original.length);
  return NormalizedText(buffer.toString(), offsets);
}
