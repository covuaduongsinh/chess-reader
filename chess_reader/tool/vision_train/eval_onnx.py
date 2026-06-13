"""Evaluate the exported ONNX model on rendered boards.

Renders full 8x8 diagrams (random FENs across book-like piece sets), slices
into cells, applies the EXACT Dart preprocessing (grayscale -> 32x32 ->
(x/255-0.5)/0.5), runs onnxruntime, and reports per-square and whole-board
accuracy — both on clean renders and degraded "print-like" renders.

Usage:
  python eval_onnx.py --assets <piece_sets dir> --model ../../assets/models/square_classifier.onnx
"""

import argparse
import os
import random

import numpy as np
import onnxruntime as ort
from PIL import Image, ImageFilter

from dataset import _BOOK_LIKE_SETS, _PIECE_ID, _rand_square_color
from model import CELL, CLASSES

_PIECES = "KQRBNP"


def _random_placement(rng):
    """A plausible sparse board: kings + a random scatter of pieces."""
    board = [["" for _ in range(8)] for _ in range(8)]
    squares = [(r, f) for r in range(8) for f in range(8)]
    rng.shuffle(squares)
    wk, bk = squares[0], squares[1]
    board[wk[0]][wk[1]] = "K"
    board[bk[0]][bk[1]] = "k"
    n = rng.randint(6, 20)
    for r, f in squares[2:2 + n]:
        p = rng.choice(_PIECES)
        board[r][f] = p if rng.random() < 0.5 else p.lower()
    return board


def _load_sets(assets_dir):
    sets = {}
    for name in sorted(os.listdir(assets_dir)):
        if name not in _BOOK_LIKE_SETS:
            continue
        d = os.path.join(assets_dir, name)
        if not os.path.isdir(d):
            continue
        sets[name] = {
            pid: Image.open(os.path.join(d, pid + ".png")).convert("RGBA")
            for pid in _PIECE_ID.values()
        }
    return sets


def _render_board(board, pieces, rng, cell_px=48, degrade=False):
    light = _rand_square_color()
    dark = _rand_square_color()
    if sum(light) < sum(dark):
        light, dark = dark, light
    size = cell_px * 8
    img = Image.new("RGBA", (size, size))
    for r in range(8):
        for f in range(8):
            bg = light if (r + f) % 2 == 0 else dark
            x, y = f * cell_px, r * cell_px
            for yy in range(y, y + cell_px):
                for xx in range(x, x + cell_px):
                    img.putpixel((xx, yy), bg + (255,))
            label = board[r][f]
            if label:
                piece = pieces[_PIECE_ID[label]]
                scale = rng.uniform(0.82, 0.96)
                ps = int(cell_px * scale)
                pr = piece.resize((ps, ps), Image.LANCZOS)
                off = (cell_px - ps) // 2
                img.alpha_composite(pr, (x + off, y + off))
    gray = img.convert("L")
    if degrade:
        f = rng.uniform(0.5, 0.8)
        gray = gray.resize((int(size * f),) * 2, Image.BILINEAR).resize(
            (size, size), Image.BILINEAR)
        gray = gray.filter(ImageFilter.GaussianBlur(rng.uniform(0.4, 1.0)))
    return gray


def _preprocess_cells(gray):
    """Slice into 64 cells, replicate Dart preprocessing."""
    size = gray.width
    cp = size / 8
    out = np.zeros((64, 1, CELL, CELL), np.float32)
    for r in range(8):
        for f in range(8):
            cell = gray.crop((round(f * cp), round(r * cp),
                              round(f * cp) + round(cp),
                              round(r * cp) + round(cp)))
            cell = cell.resize((CELL, CELL), Image.BILINEAR)
            arr = np.asarray(cell, np.float32)
            out[r * 8 + f, 0] = (arr / 255.0 - 0.5) / 0.5
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--assets", required=True)
    ap.add_argument("--model", required=True)
    ap.add_argument("--boards", type=int, default=200)
    args = ap.parse_args()

    sets = _load_sets(args.assets)
    sess = ort.InferenceSession(args.model)
    rng = random.Random(42)

    for degrade in (False, True):
        sq_correct = sq_total = 0
        board_correct = 0
        for _ in range(args.boards):
            board = _random_placement(rng)
            pieces = sets[rng.choice(list(sets))]
            gray = _render_board(board, pieces, rng, degrade=degrade)
            cells = _preprocess_cells(gray)
            logits = sess.run(None, {sess.get_inputs()[0].name: cells})[0]
            pred = logits.argmax(1)
            truth = [CLASSES.index(board[r][f]) for r in range(8) for f in range(8)]
            ok = True
            for i in range(64):
                if pred[i] == truth[i]:
                    sq_correct += 1
                else:
                    ok = False
                sq_total += 1
            if ok:
                board_correct += 1
        tag = "degraded" if degrade else "clean"
        print(f"[{tag}] per-square acc {sq_correct/sq_total:.4f}  "
              f"whole-board acc {board_correct/args.boards:.4f}")


if __name__ == "__main__":
    main()
