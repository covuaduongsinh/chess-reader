# Vision model notes (Phase 5)

The diagram-to-FEN pipeline: classical-CV `BoardLocator` finds and aligns the
printed diagram, `sliceBoardCells` cuts it into 64 cells, and a per-square CNN
(`assets/models/square_classifier.onnx`) classifies each cell. Trained
entirely on synthetic data — see `tool/vision_train/`.

## Measured accuracy (model trained 2026-06-12)

- Synthetic held-out, per-square: **97.7%** clean, **96.7%** degraded.
- Synthetic whole-board (all 64 squares correct): 43% clean, 33% degraded —
  at ~97.7%/square a board averages 1–2 wrong squares.
- Real book (`secrets-of-positional-chess.pdf`, an unseen print font): board
  structure and empty squares recover correctly; residual errors are mostly
  white/black piece-colour confusions on a few squares.

## What worked / pitfalls found

1. **Don't flip piece fill colour in augmentation.** A first attempt randomly
   recoloured pieces to solid ink, collapsing the white-vs-black cue → 61%
   val acc. Removing it → 99%. White pieces are light/outline, black are
   solid; grayscale preserves this, so leave it intact.
2. **Print "dark" squares are hatched, not filled.** The Gambit book draws
   dark squares as light paper with diagonal hatching. A model trained on
   solid-fill backgrounds read every empty hatched square as a knight. Adding
   hatch / cross-hatch / stipple background textures fixed it.
3. **Frame removal before slicing is critical** — a few pixels of grid drift
   puts a neighbour-square sliver into every cell.

## Known limitation & next step

The synthetic-only model is good but not perfect on unseen print fonts
(~1–2 squares/board). Reaching reliable whole-board accuracy needs real
labelled book diagrams. The intended path (per the plan): a board-editor
correction UI that both fixes a misread diagram in place and collects labelled
cells to fine-tune the model. Until then, a misread diagram can be corrected
via the board's "Set position from FEN" dialog.
