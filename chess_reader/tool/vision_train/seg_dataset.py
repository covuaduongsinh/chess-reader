"""Synthetic whole-board images with annotation masks for arrow segmentation.

Composites pieces on a randomized board, draws move arrows / boxes / star
markers across it, and records the exact pixels drawn as the target mask. The
segmentation model trained on this learns to find annotation strokes (near-black
thin shafts + solid heads spanning squares) regardless of the pieces underneath
— the multi-square context a per-square classifier can never see.
"""
import math
import random

import numpy as np
import torch
from PIL import Image, ImageDraw, ImageFilter
from torch.utils.data import Dataset

from dataset import _PIECE_ID, _load_piece_sets
from model import CLASSES

CELLP = 24
BOARD = CELLP * 8  # 192


def _board_background(rng):
    light = rng.randint(205, 255)
    arr = np.full((BOARD, BOARD), light, np.uint8)
    style = rng.random()
    yy, xx = np.mgrid[0:CELLP, 0:CELLP]
    if style < 0.4:
        dark = np.full((CELLP, CELLP), rng.randint(90, 180), np.uint8)
    else:
        paper = rng.randint(205, 255)
        ink = rng.randint(40, 150)
        spacing = rng.randint(3, 7)
        thick = rng.randint(1, 2)
        k = rng.random()
        if k < 0.4:
            m = ((xx + yy) % spacing) < thick
        elif k < 0.7:
            m = ((xx - yy) % spacing) < thick
        else:
            m = (((xx + yy) % spacing) < thick) | (((xx - yy) % spacing) < thick)
        dark = np.full((CELLP, CELLP), paper, np.uint8)
        dark[m] = ink
    for r in range(8):
        for f in range(8):
            if (r + f) % 2 == 1:
                arr[r * CELLP:(r + 1) * CELLP, f * CELLP:(f + 1) * CELLP] = dark
    return Image.fromarray(arr, "L").convert("RGBA")


def _place_pieces(cell_img, sets, names, rng):
    for r in range(8):
        for f in range(8):
            if rng.random() > 0.4:
                continue
            lab = rng.choice(CLASSES[:12])
            piece = sets[rng.choice(names)][_PIECE_ID[lab]]
            sz = max(8, int(CELLP * rng.uniform(0.8, 1.0)))
            pr = piece.resize((sz, sz), Image.LANCZOS)
            ox = f * CELLP + rng.randint(0, CELLP - sz)
            oy = r * CELLP + rng.randint(0, CELLP - sz)
            cell_img.alpha_composite(pr, (ox, oy))


def _draw_annotations(board, mask, rng):
    d = ImageDraw.Draw(board)
    md = ImageDraw.Draw(mask)
    for _ in range(rng.randint(1, 3)):
        ink = rng.randint(0, 70)
        col = (ink, ink, ink, rng.randint(185, 255))
        w = rng.randint(2, 5)
        kind = rng.random()
        if kind < 0.15:                                    # box around a square
            r, f = rng.randint(0, 7), rng.randint(0, 7)
            m = rng.randint(1, 3)
            box = [f * CELLP + m, r * CELLP + m,
                   (f + 1) * CELLP - m, (r + 1) * CELLP - m]
            d.rectangle(box, outline=col, width=w)
            md.rectangle(box, outline=255, width=w + 2)
        elif kind < 0.25:                                  # star / asterisk
            cx, cy = rng.uniform(0, BOARD), rng.uniform(0, BOARD)
            rad = rng.uniform(6, 13)
            for k in range(rng.choice((3, 4))):
                ang = math.pi * k / 3
                dx, dy = math.cos(ang) * rad, math.sin(ang) * rad
                d.line([(cx - dx, cy - dy), (cx + dx, cy + dy)], fill=col, width=w)
                md.line([(cx - dx, cy - dy), (cx + dx, cy + dy)], fill=255,
                        width=w + 2)
        else:                                              # arrow across squares
            r0, f0, r1, f1 = (rng.randint(0, 7) for _ in range(4))
            if abs(r0 - r1) + abs(f0 - f1) == 0:
                continue
            p0 = (f0 * CELLP + CELLP / 2, r0 * CELLP + CELLP / 2)
            p1 = (f1 * CELLP + CELLP / 2, r1 * CELLP + CELLP / 2)
            d.line([p0, p1], fill=col, width=w)
            md.line([p0, p1], fill=255, width=w + 2)
            dx, dy = p1[0] - p0[0], p1[1] - p0[1]
            nm = math.hypot(dx, dy) or 1.0
            ux, uy, px, py = dx / nm, dy / nm, -dy / nm, dx / nm
            hl, hw = rng.uniform(8, 16), rng.uniform(4, 8)
            bx, by = p1[0] - ux * hl, p1[1] - uy * hl
            tri = [(p1[0], p1[1]), (bx + px * hw, by + py * hw),
                   (bx - px * hw, by - py * hw)]
            d.polygon(tri, fill=col)
            md.polygon(tri, fill=255)


def _degrade(arr, rng, np_rng):
    if rng.random() < 0.5:
        f = rng.uniform(0.6, 0.95)
        s = max(8, int(BOARD * f))
        arr = np.asarray(Image.fromarray(arr.astype(np.uint8)).resize(
            (s, s), Image.BILINEAR).resize((BOARD, BOARD), Image.BILINEAR),
            np.float32)
    if rng.random() < 0.5:
        arr = np.asarray(Image.fromarray(arr.astype(np.uint8)).filter(
            ImageFilter.GaussianBlur(rng.uniform(0.3, 1.0))), np.float32)
    contrast, bright = rng.uniform(0.8, 1.3), rng.uniform(-20, 20)
    arr = (arr - arr.mean()) * contrast + arr.mean() + bright
    if rng.random() < 0.4:
        arr = arr + np_rng.normal(0, rng.uniform(2, 8), arr.shape)
    return np.clip(arr, 0, 255)


class SegDataset(Dataset):
    def __init__(self, assets_dir, length=8000, seed=0):
        self.sets = _load_piece_sets(assets_dir)
        self.names = list(self.sets.keys())
        self.length = length
        self.seed = seed

    def __len__(self):
        return self.length

    def __getitem__(self, idx):
        rng = random.Random(self.seed * 1_000_003 + idx)
        np_rng = np.random.RandomState(rng.randrange(2**31))
        board = _board_background(rng)
        _place_pieces(board, self.sets, self.names, rng)
        mask = Image.new("L", (BOARD, BOARD), 0)
        _draw_annotations(board, mask, rng)
        gray = _degrade(np.asarray(board.convert("L"), np.float32), rng, np_rng)
        x = torch.from_numpy((gray / 255.0 - 0.5) / 0.5).float().unsqueeze(0)
        y = torch.from_numpy(
            (np.asarray(mask, np.float32) > 127).astype(np.float32)).unsqueeze(0)
        return x, y
