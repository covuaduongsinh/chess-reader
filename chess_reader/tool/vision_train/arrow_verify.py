"""Classify each real board before vs after arrow removal."""
import glob
import sys

import numpy as np
import onnxruntime as ort
from PIL import Image

from arrow_proto import remove_arrows, stitch
from model import CELL, CLASSES

_SESS = ort.InferenceSession('../../assets/models/square_classifier.onnx')


def classify(board):
    h, w = board.shape
    cells = np.zeros((64, 1, CELL, CELL), np.float32)
    for r in range(8):
        for f in range(8):
            cell = board[round(r * h / 8):round((r + 1) * h / 8),
                         round(f * w / 8):round((f + 1) * w / 8)]
            g = np.asarray(Image.fromarray(cell).resize((CELL, CELL),
                                                        Image.BILINEAR),
                           np.float32)
            cells[r * 8 + f, 0] = (g / 255.0 - 0.5) / 0.5
    logits = _SESS.run(None, {'cells': cells})[0]
    out = []
    for i in range(64):
        std = float(cells[i, 0].std())
        out.append('.' if std < 0.08 else CLASSES[int(logits[i].argmax())])
    return out


def show(tag, before, after):
    print(tag)
    print('       BEFORE                         AFTER')
    for r in range(8):
        b = ' '.join((x or '.').rjust(2) for x in before[r * 8:r * 8 + 8])
        a = ' '.join((x or '.').rjust(2) for x in after[r * 8:r * 8 + 8])
        diff = '   <-- changed' if before[r * 8:r * 8 + 8] != after[r * 8:r * 8 + 8] else ''
        print(f'  {8 - r}  {b}     {8 - r}  {a}{diff}')
    print()


if __name__ == '__main__':
    dirs = sys.argv[1:] or sorted(glob.glob('../real_cells/pdf*/p1_b*'))
    for d in dirs:
        board = stitch(d)
        cleaned, _, n = remove_arrows(board)
        show(f'{d}  ({n} lines)', classify(board), classify(cleaned))
