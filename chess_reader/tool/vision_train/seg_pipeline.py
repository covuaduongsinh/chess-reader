"""End-to-end check: segment arrows on a real board crop, erase them, re-slice,
and classify before vs after. Mirrors what the Dart pipeline would do.

Usage: python seg_pipeline.py [board.png ...]
"""
import glob
import os
import sys

import numpy as np
import onnxruntime as ort
from PIL import Image

from arrow_proto import dilate
from model import CELL, CLASSES
from seg_test import predict_mask

_CLS = ort.InferenceSession('../../assets/models/square_classifier.onnx')


def _inpaint(gray, mask, iters=60):
    """Smoothly diffuse known background into the masked region (no hard band)."""
    out = gray.astype(np.float32)
    known = (~mask).astype(np.float32)
    val = out * known
    nb = [(-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (-1, 1), (1, -1), (1, 1)]
    for _ in range(iters):
        s = np.zeros_like(out)
        c = np.zeros_like(out)
        for dy, dx in nb:
            s += np.roll(np.roll(val, dy, 0), dx, 1)
            c += np.roll(np.roll(known, dy, 0), dx, 1)
        fill = (c > 0) & (known < 0.5)
        val = val.copy()
        val[fill] = s[fill] / c[fill]
        known = known.copy()
        known[fill] = 1.0
    return val


def clean_board(gray, *, thr=0.5, grow=2, border=14):
    """Erase predicted arrow pixels, filling with diffused local background."""
    m = predict_mask(gray) > thr
    m = dilate(m, grow * 2 + 1)
    # The model never saw a board frame in training, so it flags the dark border
    # as an arrow. The frame isn't board content — exclude it.
    if border:
        m[:border] = m[-border:] = m[:, :border] = m[:, -border:] = False
    return _inpaint(gray, m).astype(np.uint8), m


def classify(gray, *, peel=8):
    b = gray[peel:gray.shape[0] - peel, peel:gray.shape[1] - peel]
    h, w = b.shape
    cells = np.zeros((64, 1, CELL, CELL), np.float32)
    for r in range(8):
        for f in range(8):
            c = b[round(r * h / 8):round((r + 1) * h / 8),
                  round(f * w / 8):round((f + 1) * w / 8)]
            g = np.asarray(Image.fromarray(c).resize((CELL, CELL), Image.BILINEAR),
                           np.float32)
            cells[r * 8 + f, 0] = (g / 255.0 - 0.5) / 0.5
    logits = _CLS.run(None, {'cells': cells})[0]
    return [('.' if float(cells[i, 0].std()) < 0.08
             else CLASSES[int(logits[i].argmax())]) for i in range(64)]


def main():
    paths = sys.argv[1:] or sorted(glob.glob('../real_cells/pdf*/p1_b*/board.png'))
    for p in paths:
        gray = np.asarray(Image.open(p).convert('L'))
        before = classify(gray)
        cleaned, _ = clean_board(gray)
        after = classify(cleaned)
        tag = os.path.basename(os.path.dirname(p))
        ch = sum(1 for a, b in zip(before, after) if a != b)
        print(f'\n{tag}  ({ch} squares changed)')
        print('      BEFORE                          AFTER')
        for r in range(8):
            bb = ' '.join((x or '.').rjust(2) for x in before[r * 8:r * 8 + 8])
            aa = ' '.join((x or '.').rjust(2) for x in after[r * 8:r * 8 + 8])
            print(f'  {8 - r}  {bb}     {aa}')


if __name__ == '__main__':
    main()
