"""Run the arrow segmenter on the real PDF board crops and save mask overlays.

Usage: python seg_test.py [board.png ...]   (default: all real_cells/*/board.png)
"""
import glob
import os
import sys

import numpy as np
import onnxruntime as ort
from PIL import Image

from seg_model import SEG_SIZE

_SESS = ort.InferenceSession('../../assets/models/arrow_seg.onnx')


def predict_mask(gray):
    """gray: HxW uint8 board crop -> HxW float mask in [0,1] at original size."""
    h, w = gray.shape
    inp = np.asarray(Image.fromarray(gray).resize((SEG_SIZE, SEG_SIZE),
                                                   Image.BILINEAR), np.float32)
    x = ((inp / 255.0 - 0.5) / 0.5)[None, None]
    logit = _SESS.run(None, {'board': x})[0][0, 0]
    prob = 1 / (1 + np.exp(-logit))
    return np.asarray(Image.fromarray((prob * 255).astype(np.uint8)).resize(
        (w, h), Image.BILINEAR), np.float32) / 255.0


def main():
    paths = sys.argv[1:] or sorted(glob.glob('../real_cells/pdf*/p1_b*/board.png'))
    tiles = []
    for p in paths:
        gray = np.asarray(Image.open(p).convert('L'))
        m = predict_mask(gray)
        rgb = np.stack([gray] * 3, -1).astype(np.uint8)
        rgb[m > 0.5] = [255, 0, 0]
        tag = os.path.basename(os.path.dirname(p))
        tile = Image.fromarray(rgb).resize((192, 192), Image.NEAREST)
        tiles.append((tag, tile))
        print(f'{tag}: arrow px {int((m > 0.5).sum())}')
    # montage, 5 per row
    per = 5
    rows = []
    for i in range(0, len(tiles), per):
        chunk = tiles[i:i + per]
        rows.append(np.hstack([np.asarray(t) for _, t in chunk] +
                              [np.full((192, 192, 3), 255, np.uint8)] *
                              (per - len(chunk))))
    Image.fromarray(np.vstack(rows)).save('_seg_real.png')
    print('saved _seg_real.png:', [t for t, _ in tiles])


if __name__ == '__main__':
    main()
