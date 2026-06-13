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
"""

import os
import random

import numpy as np
import torch
from PIL import Image, ImageFilter
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
