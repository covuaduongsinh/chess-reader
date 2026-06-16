"""2-channel per-square training data: [cell grayscale, arrow-mask].

Same boards/pieces/augmentation as `dataset.py`, but each annotation also writes
a mask channel marking its pixels, and the label stays the TRUE underlying
square. The classifier learns to read the piece (or empty) while ignoring the
masked annotation — so a shaft passing through a pawn keeps the pawn. The mask
is augmented (dilate/blur/dropout, plus occasional spurious blobs on clean
cells) to mimic the real segmenter's imperfect output at inference.
"""
import math
import random

import numpy as np
import torch
from PIL import Image, ImageDraw, ImageFilter
from torch.utils.data import Dataset

from dataset import _PIECE_ID, _add_grid, _edge_point, _load_piece_sets, _make_background
from model import CELL, CLASSES


def _add_annotation_mask(cell, work, rng):
    """Like dataset._add_annotation but also returns a {0,1} mask (work x work)
    of the drawn pixels."""
    overlay = Image.new("RGBA", (work, work), (0, 0, 0, 0))
    mimg = Image.new("L", (work, work), 0)
    d = ImageDraw.Draw(overlay)
    md = ImageDraw.Draw(mimg)
    ink = rng.randint(0, 80)
    color = (ink, ink, ink, rng.randint(170, 255))
    kind = rng.random()

    def line(p, w, mw=None):
        d.line(p, fill=color, width=w)
        md.line(p, fill=255, width=mw or w + 2)

    if kind < 0.12:
        m = rng.randint(1, 4)
        w = rng.randint(2, 4)
        box = [m, m, work - 1 - m, work - 1 - m]
        if rng.random() < 0.5:
            d.rectangle(box, outline=color, width=w)
            md.rectangle(box, outline=255, width=w + 2)
        else:
            d.ellipse(box, outline=color, width=w)
            md.ellipse(box, outline=255, width=w + 2)
    elif kind < 0.24:
        cx = rng.uniform(0.35 * work, 0.65 * work)
        cy = rng.uniform(0.35 * work, 0.65 * work)
        if rng.random() < 0.55:
            rad = rng.uniform(0.12 * work, 0.28 * work)
            w = rng.randint(2, 4)
            for k in range(rng.choice((3, 4))):
                ang = math.pi * k / 3
                dx, dy = math.cos(ang) * rad, math.sin(ang) * rad
                line([(cx - dx, cy - dy), (cx + dx, cy + dy)], w)
        else:
            rad = rng.uniform(0.08 * work, 0.18 * work)
            d.ellipse([cx - rad, cy - rad, cx + rad, cy + rad], fill=color)
            md.ellipse([cx - rad - 1, cy - rad - 1, cx + rad + 1, cy + rad + 1],
                       fill=255)
    elif kind < 0.40:
        a = _edge_point(work, rng)
        mid = (rng.uniform(0.2 * work, 0.8 * work),
               rng.uniform(0.2 * work, 0.8 * work))
        b = _edge_point(work, rng)
        line([a, mid, b], rng.randint(2, 5))
    elif kind < 0.60:
        if rng.random() < 0.6:
            ang = rng.uniform(0, math.pi)
            cx = work / 2 + rng.uniform(-6, 6)
            cy = work / 2 + rng.uniform(-6, 6)
            dx, dy = math.cos(ang) * work, math.sin(ang) * work
            a, b = (cx - dx, cy - dy), (cx + dx, cy + dy)
        else:
            a, b = _edge_point(work, rng), _edge_point(work, rng)
        line([a, b], rng.randint(2, 6))
    else:
        wdt = rng.randint(3, 7)
        p0 = _edge_point(work, rng)
        p1 = (rng.uniform(0.2 * work, 0.8 * work),
              rng.uniform(0.2 * work, 0.8 * work))
        line([p0, p1], wdt)
        dx, dy = p1[0] - p0[0], p1[1] - p0[1]
        nm = math.hypot(dx, dy) or 1.0
        ux, uy, px, py = dx / nm, dy / nm, -dy / nm, dx / nm
        hl, hw = rng.uniform(11, 22), rng.uniform(6, 13)
        bx, by = p1[0] - ux * hl, p1[1] - uy * hl
        tri = [(p1[0], p1[1]), (bx + px * hw, by + py * hw),
               (bx - px * hw, by - py * hw)]
        d.polygon(tri, fill=color)
        md.polygon(tri, fill=255)

    out = Image.alpha_composite(cell, overlay)
    return out, (np.asarray(mimg, np.float32) / 255.0)


def _augment_mask(mask, rng):
    """Make a ground-truth mask look like the segmenter's noisy output."""
    img = Image.fromarray((mask * 255).astype(np.uint8))
    if rng.random() < 0.5:  # dilate (segmenter masks run a touch wide)
        img = img.filter(ImageFilter.MaxFilter(3))
    if rng.random() < 0.7:  # soft edges
        img = img.filter(ImageFilter.GaussianBlur(rng.uniform(0.5, 1.5)))
    arr = np.asarray(img, np.float32) / 255.0
    if rng.random() < 0.3:  # partial miss
        arr *= rng.uniform(0.5, 1.0)
    return np.clip(arr, 0, 1)


def _spurious_mask(rng):
    """A small false-positive blob a segmenter might emit on a clean cell."""
    m = Image.new("L", (CELL, CELL), 0)
    d = ImageDraw.Draw(m)
    if rng.random() < 0.5:
        x, y = rng.randint(0, CELL), rng.randint(0, CELL)
        d.line([(x, y), (rng.randint(0, CELL), rng.randint(0, CELL))],
               fill=255, width=rng.randint(2, 4))
    else:
        x, y = rng.randint(4, CELL - 4), rng.randint(4, CELL - 4)
        r = rng.randint(2, 5)
        d.ellipse([x - r, y - r, x + r, y + r], fill=255)
    return np.asarray(m.filter(ImageFilter.GaussianBlur(1.0)), np.float32) / 255.0


class Square2Dataset(Dataset):
    def __init__(self, assets_dir, length=60000, seed=0):
        self.sets = _load_piece_sets(assets_dir)
        self.names = list(self.sets.keys())
        self.length = length
        self.base_seed = seed

    def __len__(self):
        return self.length

    def __getitem__(self, idx):
        rng = random.Random(self.base_seed * 1_000_003 + idx)
        np_rng = np.random.RandomState(rng.randrange(2**31))

        label = "" if rng.random() < 0.22 else rng.choice(CLASSES[:12])
        work = 48
        cell = Image.fromarray(_make_background(work, rng), "L").convert("RGBA")
        if label:
            piece = self.sets[rng.choice(self.names)][_PIECE_ID[label]]
            scale = rng.uniform(0.78, 0.98)
            size = max(8, int(work * scale))
            pr = piece.resize((size, size), Image.LANCZOS)
            cell.alpha_composite(pr, (rng.randint(0, work - size),
                                      rng.randint(0, work - size)))

        mask = np.zeros((work, work), np.float32)
        if rng.random() < (0.42 if not label else 0.33):
            cell, mask = _add_annotation_mask(cell, work, rng)

        img = cell.convert("L")
        if rng.random() < 0.5:
            img = _add_grid(img, rng)

        pad = work - CELL
        cx, cy = rng.randint(0, pad), rng.randint(0, pad)
        img = img.crop((cx, cy, cx + CELL, cy + CELL))
        mask = mask[cy:cy + CELL, cx:cx + CELL]
        arr = np.asarray(img, np.float32)

        if rng.random() < 0.5:
            f = rng.uniform(0.55, 0.9)
            small = Image.fromarray(arr.astype(np.uint8)).resize(
                (max(6, int(CELL * f)),) * 2, Image.BILINEAR
            ).resize((CELL, CELL), Image.BILINEAR)
            arr = np.asarray(small, np.float32)
        if rng.random() < 0.5:
            arr = np.asarray(Image.fromarray(arr.astype(np.uint8)).filter(
                ImageFilter.GaussianBlur(rng.uniform(0.3, 1.0))), np.float32)
        mean = arr.mean()
        arr = (arr - mean) * rng.uniform(0.7, 1.4) + mean + rng.uniform(-25, 25)
        if rng.random() < 0.4:
            arr = arr + np_rng.normal(0, rng.uniform(2, 8), arr.shape)
        arr = np.clip(arr, 0, 255)

        if mask.max() > 0:
            mask = _augment_mask(mask, rng)
        elif rng.random() < 0.12:           # spurious segmenter FP on a clean cell
            mask = _spurious_mask(rng)

        gray = (arr / 255.0 - 0.5) / 0.5
        x = torch.from_numpy(np.stack([gray, mask]).astype(np.float32))
        y = CLASSES.index(label)
        return x, y
