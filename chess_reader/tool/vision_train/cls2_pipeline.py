"""End-to-end mask-aware recognition on real board crops.

segmenter -> arrow mask; peel frame (like the Dart slicer); slice board AND mask
into 64 cells; classify each cell with the 2-channel model. Prints the 1-channel
baseline (current square_classifier.onnx) vs the 2-channel result.

Usage: python cls2_pipeline.py [board.png ...]
"""
import glob
import os
import sys

import numpy as np
import onnxruntime as ort
from PIL import Image

from model import CELL, CLASSES
from seg_test import predict_mask

_CLS1 = ort.InferenceSession('../../assets/models/square_classifier.onnx')
_CLS2 = ort.InferenceSession('../../assets/models/square_classifier2.onnx')
_EMPTY_STD = 0.08


def _crop_inside_frame(gray):
    """Mirror board_slicer._cropInsideFrame: peel near-fully-dark edge rows/cols."""
    n = gray.shape[0]
    maxpeel = n // 8
    t, b, l, r = 0, n - 1, 0, n - 1
    while t < maxpeel and (gray[t] < 128).mean() > 0.8:
        t += 1
    while b > n - 1 - maxpeel and (gray[b] < 128).mean() > 0.8:
        b -= 1
    while l < maxpeel and (gray[:, l] < 128).mean() > 0.8:
        l += 1
    while r > n - 1 - maxpeel and (gray[:, r] < 128).mean() > 0.8:
        r -= 1
    return t, b, l, r


def _cells(gray, mask):
    t, b, l, r = _crop_inside_frame(gray)
    g = gray[t:b + 1, l:r + 1]
    m = mask[t:b + 1, l:r + 1]
    h, w = g.shape
    ch1 = np.zeros((64, 1, CELL, CELL), np.float32)
    ch2 = np.zeros((64, 2, CELL, CELL), np.float32)
    for r_ in range(8):
        for f in range(8):
            ys, ye = round(r_ * h / 8), round((r_ + 1) * h / 8)
            xs, xe = round(f * w / 8), round((f + 1) * w / 8)
            gc = np.asarray(Image.fromarray(g[ys:ye, xs:xe]).resize(
                (CELL, CELL), Image.BILINEAR), np.float32)
            mc = np.asarray(Image.fromarray(
                (m[ys:ye, xs:xe] * 255).astype(np.uint8)).resize(
                (CELL, CELL), Image.BILINEAR), np.float32) / 255.0
            gn = (gc / 255.0 - 0.5) / 0.5
            ch1[r_ * 8 + f, 0] = gn
            ch2[r_ * 8 + f, 0] = gn
            ch2[r_ * 8 + f, 1] = mc
    return ch1, ch2


def _decode(sess, cells, in_name='cells'):
    logits = sess.run(None, {in_name: cells})[0]
    out = []
    for i in range(64):
        std = float(cells[i, 0].std())
        out.append('.' if std < _EMPTY_STD else CLASSES[int(logits[i].argmax())])
    return out


def main():
    paths = sys.argv[1:] or sorted(glob.glob('../real_cells/pdf*/p1_b*/board.png'))
    for p in paths:
        gray = np.asarray(Image.open(p).convert('L'))
        mask = predict_mask(gray)
        ch1, ch2 = _cells(gray, mask)
        before = _decode(_CLS1, ch1)
        after = _decode(_CLS2, ch2)
        tag = os.path.basename(os.path.dirname(p))
        ch = sum(1 for a, b in zip(before, after) if a != b)
        print(f'\n{tag}  ({ch} squares differ)')
        print('      1ch BASELINE                    2ch MASK-AWARE')
        for r in range(8):
            bb = ' '.join((x or '.').rjust(2) for x in before[r * 8:r * 8 + 8])
            aa = ' '.join((x or '.').rjust(2) for x in after[r * 8:r * 8 + 8])
            print(f'  {8 - r}  {bb}     {aa}')


if __name__ == '__main__':
    main()
