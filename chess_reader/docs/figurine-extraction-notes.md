# Figurine extraction findings (Phase 3 input)

Observed via `dart run tool/dump_pdf_text.dart <book> [pages...]`.

## secrets-of-positional-chess.pdf (Gambit Publications, 226 pages)

The figurine font has no usable ToUnicode table. PDFium extracts piece
glyphs as multi-character ASCII sequences, NOT unicode figurines or PUA
codepoints. The mapping table for Phase 3 must therefore support
**sequence replacement**, not just codepoint mapping:

| Extracted sequence(s)              | Piece | Example                      |
|------------------------------------|-------|------------------------------|
| `lt:J`, `lLl`, `ll:l`, `lt'l`, `ll'l` | N   | `lt:Jf6` = Nf6               |
| `i.`                               | B     | `i.e3` = Be3                 |
| `l:!.`, `l:t`, `l::t`, `l:r.`, `ll`, `.l:!.` | R | `l:!.c3` = Rc3        |
| `�` (U+FFFD, 3371 occurrences)     | K     | `�g2` = Kg2                  |
| `"iV`, `°iV`, `"ii'`, `°ii'`, `'ilf`, `'ii` | Q | `"iVf2` = Qf2         |
| `•••` (U+2022 ×3, 2073 occurrences of •) | … | `26 ••• �e8` = 26...Ke8 |

Additional hazards seen in bold (figurine-font) move text:
- digit/letter substitutions: `f`→`r`, `5`→`s`, `1`→`l` (`32 rs` = "32 f5",
  `°ii'cl` = "Qc1")
- spurious spaces inside squares: `40 l:!.c 1` = "40 Rc1"
- Gambit numbering style has NO dot after the move number (`38 l:!.c3`),
  and `(D)` marks a diagram reference.

Baseline with naive v1 (no sequence mapping, per-page resolve from the
initial position): 9921 tokens, 2138 resolved, 213/226 pages with at
least one resolved move. Games annotated from move 1 resolve cleanly;
mid-game pages need Phase 3 anchors.

U+FFFD is lossy (any unmapped glyph collapses to it) — treat a `�`
followed by a square as a king move *candidate*, validated by legality,
never a certainty. True fidelity may require font-name-keyed tables via
PDFium font APIs later.

## Mid-book variants (page 15, Petrosian–Larsen)

The page-1 table above missed forms that appear deeper in the book; added to
`_gambitRules`:

| Extracted sequence(s) | Piece | Example            |
|-----------------------|-------|--------------------|
| `ltJ` (no colon), `4J` | N    | `ltJe8`, `4Jxf6`   |
| `"il`, `'fi`          | Q     | `"ile7`, `'fia7`   |

Effect across the book: resolved moves 1647 → 1811 (pages with ≥1 resolved
move unchanged at 195/226). Residual gaps remain — this font has extensive,
bold/italic-dependent glyph collisions (e.g. rank 5 as lowercase `s` in
`ii.gs` = Bg5, rook as `A` in `Axc4` = Rxc4) that are not yet mapped.
