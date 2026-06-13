"""Run exported board cells (from tool/dump_board_cells.dart) through the
ONNX model and print the assembled FEN per board — validates print-font
transfer on real book diagrams.

Usage: python eval_cells.py --model <onnx> --cells <dir with p*_b* subdirs>
"""

import argparse
import glob
import os

import numpy as np
import onnxruntime as ort
from PIL import Image

from model import CELL, CLASSES


def _assemble_fen(labels):
    ranks = []
    for r in range(8):
        s, empty = "", 0
        for f in range(8):
            lab = labels[r * 8 + f]
            if lab == "":
                empty += 1
            else:
                if empty:
                    s += str(empty)
                    empty = 0
                s += lab
        if empty:
            s += str(empty)
        ranks.append(s)
    return "/".join(ranks)


def _preprocess(path):
    cell = Image.open(path).convert("L").resize((CELL, CELL), Image.BILINEAR)
    arr = np.asarray(cell, np.float32)
    return (arr / 255.0 - 0.5) / 0.5


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", required=True)
    ap.add_argument("--cells", required=True)
    args = ap.parse_args()

    sess = ort.InferenceSession(args.model)
    boards = sorted(glob.glob(os.path.join(args.cells, "p*_b*")))
    if not boards:
        print(f"no board dirs under {args.cells}")
        return
    for board_dir in boards:
        batch = np.zeros((64, 1, CELL, CELL), np.float32)
        for r in range(8):
            for f in range(8):
                p = os.path.join(board_dir, f"cell_{r}{f}.png")
                batch[r * 8 + f, 0] = _preprocess(p)
        logits = sess.run(None, {sess.get_inputs()[0].name: batch})[0]
        labels = [CLASSES[i] for i in logits.argmax(1)]
        print(f"{os.path.basename(board_dir)}: {_assemble_fen(labels)}")


if __name__ == "__main__":
    main()
