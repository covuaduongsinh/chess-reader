"""Measure how a square classifier handles annotation marks (arrows / rings).

Builds controlled cells with the SAME pieces/backgrounds the trainer uses, then
forces an annotation overlay on top, and reports — for a given ONNX model — how
often each bucket is read correctly. Mirrors infer_cells.py preprocessing and
the Dart emptiness gate so the numbers reflect the shipped pipeline.

Usage:
  python eval_arrows.py <model.onnx> [--n 1500]

Buckets:
  empty + arrow   -> should read EMPTY (the bug: it read a phantom piece)
  piece + arrow   -> should still read the correct PIECE
  empty (control)  / piece (control) -> no-arrow baselines
"""
import argparse
import random

import numpy as np
import onnxruntime as ort
from PIL import Image

from dataset import _PIECE_ID, _add_annotation, _load_piece_sets, _make_background
from model import CELL, CLASSES

_EMPTY_STD = 0.08  # mirror onnx_square_classifier.dart emptiness gate


def _build(assets, n, seed, *, piece, arrow):
    sets = _load_piece_sets(assets)
    names = list(sets.keys())
    rng = random.Random(seed)
    work = 48
    cells = np.zeros((n, 1, CELL, CELL), np.float32)
    labels = []
    for i in range(n):
        bg = _make_background(work, rng)
        cell = Image.fromarray(bg, mode="L").convert("RGBA")
        if piece:
            lab = rng.choice(CLASSES[:12])
            pid = _PIECE_ID[lab]
            sz = max(8, int(work * rng.uniform(0.78, 0.98)))
            pr = sets[rng.choice(names)][pid].resize((sz, sz), Image.LANCZOS)
            cell.alpha_composite(pr, (rng.randint(0, work - sz),
                                      rng.randint(0, work - sz)))
        else:
            lab = ""
        if arrow:
            cell = _add_annotation(cell, work, rng)
        # Center-crop work->CELL and normalize like preprocessCell.
        off = (work - CELL) // 2
        arr = np.asarray(cell.convert("L").crop(
            (off, off, off + CELL, off + CELL)), np.float32)
        cells[i, 0] = (arr / 255.0 - 0.5) / 0.5
        labels.append(lab)
    return cells, labels


def _predict(sess, in_name, cells):
    logits = sess.run(None, {in_name: cells})[0]
    out = []
    for i in range(len(cells)):
        if float(cells[i, 0].std()) < _EMPTY_STD:
            out.append("")
        else:
            out.append(CLASSES[int(logits[i].argmax())])
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("model")
    ap.add_argument("--assets", required=True)
    ap.add_argument("--n", type=int, default=1500)
    args = ap.parse_args()

    sess = ort.InferenceSession(args.model)
    in_name = sess.get_inputs()[0].name

    def report(tag, piece, arrow, seed):
        cells, labels = _build(args.assets, args.n, seed, piece=piece, arrow=arrow)
        preds = _predict(sess, in_name, cells)
        exact = np.mean([p == l for p, l in zip(preds, labels)])
        empty = np.mean([p == "" for p in preds])
        print(f"  {tag:18s} exact={exact:6.3f}  read_empty={empty:6.3f}")

    print(f"model: {args.model}")
    report("empty+arrow", False, True, 101)   # want exact(=empty) HIGH
    report("empty control", False, False, 202)
    report("piece+arrow", True, True, 303)     # want exact HIGH, read_empty LOW
    report("piece control", True, False, 404)


if __name__ == "__main__":
    main()
