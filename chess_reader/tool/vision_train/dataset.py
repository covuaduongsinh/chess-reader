"""Synthetic per-square training data.

Composites chessground piece PNGs (40 styles) onto randomized square
backgrounds and applies heavy augmentation. The goal is shape invariance
that transfers to printed book diagrams, whose figurine fonts we don't have
but which resemble the silhouette-style sets (alpha, mono, letter, leipzig).

The augmentations that bridge the domain gap to print:
- grayscale (print diagrams are usually B&W)
- random downscale->upscale (low print resolution)
- blur, gaussian noise (scan/print artifacts)
- random binary threshold (line-art diagrams)
- random contrast/brightness (ink density, paper tone)
- grid lines at cell edges (the board grid bleeds into cells)
- annotation marks (arrows / highlight rings) drawn over the cell, with the
  label kept as the true underlying content so the model learns to see through
  them instead of reading a phantom piece
"""

import math
import os
import random

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
import torch
from torch.utils.data import Dataset

from model import CELL, CLASSES

# Piece id per non-empty class label.
_PIECE_ID = {
    "K": "wK", "Q": "wQ", "R": "wR", "B": "wB", "N": "wN", "P": "wP",
    "k": "bK", "q": "bQ", "r": "bR", "b": "bB", "n": "bN", "p": "bP",
}

# Sets that resemble traditional printed-book diagrams. Joke/abstract sets
# (xkcd stick figures, shapes, disguised, pixel...) teach wrong silhouettes
# and are excluded — book figurines are conventional piece shapes where white
# pieces are light/outline and black pieces are dark/filled.
_BOOK_LIKE_SETS = {
    "alpha", "california", "cardinal", "cburnett", "celtic", "companion",
    "cooke", "fantasy", "fresca", "gioco", "governor", "kosal", "leipzig",
    "maestro", "merida", "monarchy", "mpchess", "pirouetti", "reillycraig",
    "staunty", "tatiana",
}


def _load_piece_sets(assets_dir):
    """Returns {set_name: {piece_id: RGBA Image}} for book-like sets found."""
    sets = {}
    for name in sorted(os.listdir(assets_dir)):
        if name not in _BOOK_LIKE_SETS:
            continue
        set_dir = os.path.join(assets_dir, name)
        if not os.path.isdir(set_dir):
            continue
        pieces = {}
        ok = True
        for pid in _PIECE_ID.values():
            path = os.path.join(set_dir, pid + ".png")
            if not os.path.exists(path):
                ok = False
                break
            pieces[pid] = Image.open(path).convert("RGBA")
        if ok:
            sets[name] = pieces
    if not sets:
        raise SystemExit(f"No piece sets found in {assets_dir}")
    return sets


def _rand_square_color():
    """A light or dark square tone, spanning board themes and B&W print."""
    if random.random() < 0.5:
        # Light: cream/white/light-gray.
        v = random.randint(200, 255)
        return (v, random.randint(v - 20, v), random.randint(v - 40, v))
    # Dark: brown/gray/medium.
    v = random.randint(90, 180)
    return (v, random.randint(max(0, v - 30), v), random.randint(0, v))


def _make_background(work, rng):
    """A grayscale square background.

    Models a range of board styles, crucially the print convention where
    "dark" squares are a light paper tone overlaid with a darker pattern
    (diagonal hatching, cross-hatch, or stipple) rather than a solid fill —
    as in the Gambit test book. Returns a (work, work) uint8 array.
    """
    style = rng.random()
    if style < 0.45:
        # Solid (light or dark), as in digital boards.
        v = rng.randint(60, 255)
        return np.full((work, work), v, np.uint8)

    # Patterned "dark" square: light paper + darker marks.
    paper = rng.randint(205, 255)
    ink = rng.randint(40, 150)
    arr = np.full((work, work), paper, np.uint8)
    yy, xx = np.mgrid[0:work, 0:work]
    spacing = rng.randint(3, 7)
    thickness = rng.randint(1, 2)
    kind = rng.random()
    if kind < 0.4:
        mask = ((xx + yy) % spacing) < thickness          # diagonal hatch /
    elif kind < 0.65:
        mask = ((xx - yy) % spacing) < thickness          # diagonal hatch \
    elif kind < 0.85:
        mask = (((xx + yy) % spacing) < thickness) | \
               (((xx - yy) % spacing) < thickness)        # cross-hatch
    else:
        dots = np.zeros((work, work), bool)
        dots[::spacing, ::spacing] = True                 # stipple
        mask = dots
    arr[mask] = ink
    return arr


class SquareDataset(Dataset):
    def __init__(self, assets_dir, length=60000, seed=0):
        self.sets = _load_piece_sets(assets_dir)
        self.set_names = list(self.sets.keys())
        self.length = length
        self.base_seed = seed

    def __len__(self):
        return self.length

    def __getitem__(self, idx):
        rng = random.Random(self.base_seed * 1_000_003 + idx)
        np_rng = np.random.RandomState(rng.randrange(2**31))

        # ~22% empty squares (real boards average ~half empty, but pieces are
        # the hard classes — bias toward them while keeping empties common).
        label = "" if rng.random() < 0.22 else rng.choice(CLASSES[:12])

        # Slightly larger working canvas, cropped later for jitter.
        work = 48
        bg_arr = _make_background(work, rng)
        cell = Image.fromarray(bg_arr, mode="L").convert("RGBA")

        if label:
            pid = _PIECE_ID[label]
            piece = self.sets[rng.choice(self.set_names)][pid]
            scale = rng.uniform(0.78, 0.98)
            size = max(8, int(work * scale))
            piece_r = piece.resize((size, size), Image.LANCZOS)
            ox = rng.randint(0, work - size)
            oy = rng.randint(0, work - size)
            cell.alpha_composite(piece_r, (ox, oy))

        # Annotation marks (arrows / highlight rings) over whatever is in the
        # cell. The label is left unchanged, so the model learns these are NOT
        # pieces: an arrow on an empty square stays empty; an arrow over a piece
        # keeps that piece. Biased higher on empties — the failure mode we fix.
        if rng.random() < (0.42 if not label else 0.33):
            cell = _add_annotation(cell, work, rng)

        img = cell.convert("L")

        # Grid lines at random edges.
        if rng.random() < 0.5:
            img = _add_grid(img, rng)

        # Jitter-crop back to a square region.
        pad = work - CELL
        cx = rng.randint(0, pad)
        cy = rng.randint(0, pad)
        img = img.crop((cx, cy, cx + CELL, cy + CELL))

        arr = np.asarray(img, dtype=np.float32)

        # Downscale->upscale (low print resolution). Kept mild so piece
        # outlines — the white/black cue — survive.
        if rng.random() < 0.5:
            f = rng.uniform(0.55, 0.9)
            small = Image.fromarray(arr.astype(np.uint8)).resize(
                (max(6, int(CELL * f)),) * 2, Image.BILINEAR
            ).resize((CELL, CELL), Image.BILINEAR)
            arr = np.asarray(small, dtype=np.float32)

        # Blur.
        if rng.random() < 0.5:
            blurred = Image.fromarray(arr.astype(np.uint8)).filter(
                ImageFilter.GaussianBlur(rng.uniform(0.3, 1.0))
            )
            arr = np.asarray(blurred, dtype=np.float32)

        # Contrast / brightness (ink density, paper tone) — does not flip
        # piece fill, so white/black discrimination is preserved.
        contrast = rng.uniform(0.7, 1.4)
        brightness = rng.uniform(-25, 25)
        mean = arr.mean()
        arr = (arr - mean) * contrast + mean + brightness

        # Light gaussian noise.
        if rng.random() < 0.4:
            arr = arr + np_rng.normal(0, rng.uniform(2, 8), arr.shape)

        arr = np.clip(arr, 0, 255)

        # Normalize to [-1, 1] — replicated exactly in Dart.
        x = (arr / 255.0 - 0.5) / 0.5
        x = torch.from_numpy(x).float().unsqueeze(0)  # (1, CELL, CELL)
        y = CLASSES.index(label)
        return x, y


def _edge_point(work, rng):
    """A random point on the cell border (where a multi-square arrow enters)."""
    side = rng.randint(0, 3)
    t = rng.uniform(0, work - 1)
    if side == 0:
        return (t, 0.0)
    if side == 1:
        return (t, work - 1.0)
    if side == 2:
        return (0.0, t)
    return (work - 1.0, t)


def _add_annotation(cell, work, rng):
    """Draw a monochrome annotation mark over an RGBA [cell].

    Models what a single 1/8-of-a-board cell actually sees of a hand-drawn
    overlay. Real printed annotations the classifier hallucinated into pieces:
    - move arrows: near-black with a SOLID filled triangular head ~piece-sized,
      on a thick shaft (not a hairline barb);
    - the long thin shaft of such an arrow crossing empty squares end to end;
    - bent / zigzag (routed) shafts;
    - small star/asterisk or dot markers on a square;
    - square-highlight boxes (and rings) around a square.
    The caller keeps the original label, so the model learns to see through all
    of these. Returns a new composited RGBA image.
    """
    overlay = Image.new("RGBA", (work, work), (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    ink = rng.randint(0, 80)              # arrows are near-black
    alpha = rng.randint(170, 255)         # solid, occasionally a little soft
    color = (ink, ink, ink, alpha)
    kind = rng.random()

    if kind < 0.12:
        # Square-highlight box or ring around the border.
        m = rng.randint(1, 4)
        wd = rng.randint(2, 4)
        box = [m, m, work - 1 - m, work - 1 - m]
        if rng.random() < 0.5:
            draw.rectangle(box, outline=color, width=wd)
        else:
            draw.ellipse(box, outline=color, width=wd)
        return Image.alpha_composite(cell, overlay)

    if kind < 0.24:
        # Small marker: asterisk/star or filled dot near the centre.
        cx = rng.uniform(0.35 * work, 0.65 * work)
        cy = rng.uniform(0.35 * work, 0.65 * work)
        if rng.random() < 0.55:
            rad = rng.uniform(0.12 * work, 0.28 * work)
            wd = rng.randint(2, 4)
            rays = rng.choice((3, 4))     # 3 -> 6-point asterisk, 4 -> 8-point
            for k in range(rays):
                ang = math.pi * k / rays
                dx, dy = math.cos(ang) * rad, math.sin(ang) * rad
                draw.line([(cx - dx, cy - dy), (cx + dx, cy + dy)],
                          fill=color, width=wd)
        else:
            rad = rng.uniform(0.08 * work, 0.18 * work)
            draw.ellipse([cx - rad, cy - rad, cx + rad, cy + rad], fill=color)
        return Image.alpha_composite(cell, overlay)

    if kind < 0.40:
        # Bent / zigzag shaft (a routed move arrow doubling back through the
        # cell — the "^" peak that was misread as a bishop). Thin, two segments,
        # usually no head.
        a = _edge_point(work, rng)
        mid = (rng.uniform(0.2 * work, 0.8 * work),
               rng.uniform(0.2 * work, 0.8 * work))
        b = _edge_point(work, rng)
        draw.line([a, mid, b], fill=color, width=rng.randint(2, 5),
                  joint="curve")
        return Image.alpha_composite(cell, overlay)

    if kind < 0.60:
        # The long thin shaft of an arrow crossing the cell (a cell in the
        # middle of a multi-square arrow). Often straight through the centre —
        # a file-/diagonal-long shaft passing over a square or right through a
        # piece on it (the part read as a stray rook, or that turned a pawn into
        # a rook). Drawn here over whatever the cell already holds.
        if rng.random() < 0.6:
            ang = rng.uniform(0, math.pi)
            cx = work / 2 + rng.uniform(-6, 6)
            cy = work / 2 + rng.uniform(-6, 6)
            dx, dy = math.cos(ang) * work, math.sin(ang) * work
            a, b = (cx - dx, cy - dy), (cx + dx, cy + dy)
        else:
            a, b = _edge_point(work, rng), _edge_point(work, rng)
        draw.line([a, b], fill=color, width=rng.randint(2, 6))
        return Image.alpha_composite(cell, overlay)

    # Arrow shaft. A cell sees either a slice crossing it (both ends on the
    # border) or the tip region (one end in the interior, where the head sits).
    wdt = rng.randint(3, 7)
    p0 = _edge_point(work, rng)
    interior_tip = rng.random() < 0.6
    if interior_tip:
        p1 = (rng.uniform(0.2 * work, 0.8 * work),
              rng.uniform(0.2 * work, 0.8 * work))
    else:
        p1 = _edge_point(work, rng)
    draw.line([p0, p1], fill=color, width=wdt)

    # Solid filled arrowhead at the tip — the piece-sized dark triangle.
    if interior_tip or rng.random() < 0.3:
        dx, dy = p1[0] - p0[0], p1[1] - p0[1]
        norm = math.hypot(dx, dy) or 1.0
        ux, uy = dx / norm, dy / norm       # shaft direction
        px, py = -uy, ux                    # perpendicular
        hl = rng.uniform(11, 22)            # head length (up to ~half a cell)
        hw = rng.uniform(6, 13)             # head half-width
        bx, by = p1[0] - ux * hl, p1[1] - uy * hl
        draw.polygon(
            [(p1[0], p1[1]), (bx + px * hw, by + py * hw),
             (bx - px * hw, by - py * hw)],
            fill=color,
        )

    return Image.alpha_composite(cell, overlay)


def _add_grid(img, rng):
    a = np.asarray(img).copy()
    line = rng.randint(0, 80)
    if rng.random() < 0.5:
        a[0:1, :] = line
    if rng.random() < 0.5:
        a[-1:, :] = line
    if rng.random() < 0.5:
        a[:, 0:1] = line
    if rng.random() < 0.5:
        a[:, -1:] = line
    return Image.fromarray(a)
