"""Prototype: remove arrow/annotation lines from a board crop before slicing.

Pure numpy/PIL so the algorithm ports straight to Dart (image package). Idea:
- threshold dark pixels;
- separate THICK structures (piece bodies = morphological opening) from THIN
  ones (arrow shafts, box/piece outlines = dark & not-thick);
- Hough over the THIN mask to find LONG straight lines (arrow shafts span
  multiple squares; piece outlines / hatching do not);
- erase only THIN pixels lying on a detected long line, filling with the local
  background (grayscale closing) — so a shaft passing THROUGH a piece is removed
  while the piece body (thick) survives.
"""
import sys

import numpy as np
from PIL import Image


def _shifts(k):
    r = k // 2
    return [(dy, dx) for dy in range(-r, r + 1) for dx in range(-r, r + 1)]


def erode(mask, k):
    out = mask.copy()
    for dy, dx in _shifts(k):
        out &= np.roll(np.roll(mask, dy, 0), dx, 1)
    return out


def dilate(mask, k):
    out = mask.copy()
    for dy, dx in _shifts(k):
        out |= np.roll(np.roll(mask, dy, 0), dx, 1)
    return out


def gray_close(img, k):
    # max then min filter (dilate/erode on intensity) — fills dark thin lines.
    def mx(a):
        o = a.copy()
        for dy, dx in _shifts(k):
            o = np.maximum(o, np.roll(np.roll(a, dy, 0), dx, 1))
        return o

    def mn(a):
        o = a.copy()
        for dy, dx in _shifts(k):
            o = np.minimum(o, np.roll(np.roll(a, dy, 0), dx, 1))
        return o
    return mn(mx(img))


def remove_arrows(board, *, thresh=110, open_k=5, close_k=9,
                  ang_step=2, min_frac=1.6, band=2.0):
    """Returns (cleaned board, debug overlay)."""
    h, w = board.shape
    cell = (h + w) / 16.0
    dark = board < thresh
    thick = dilate(erode(dark, open_k), open_k)      # piece bodies
    thin = dark & ~thick                             # shafts / outlines

    core = erode(dark, open_k)               # definite piece interiors
    protected = dilate(core, open_k + 2)     # keep pieces (and box+piece) intact

    ys, xs = np.nonzero(thin)
    thetas = np.deg2rad(np.arange(0, 180, ang_step))
    cos, sin = np.cos(thetas), np.sin(thetas)
    diag = int(np.hypot(h, w)) + 1
    rho = (np.outer(xs, cos) + np.outer(ys, sin)).astype(np.int32) + diag
    acc = np.zeros((len(thetas), 2 * diag + 1), np.int32)
    for t in range(len(thetas)):
        np.add.at(acc[t], rho[:, t], 1)

    min_votes = int(min_frac * cell)
    band_mask = np.zeros((h, w), bool)
    yy, xx = np.mgrid[0:h, 0:w]
    # Peaks, greedily, with light NMS.
    work = acc.copy()
    lines = []
    for _ in range(60):
        t, r = np.unravel_index(int(work.argmax()), work.shape)
        if work[t, r] < min_votes:
            break
        lines.append((thetas[t], r - diag))
        work[max(0, t - 1):t + 2, max(0, r - 6):r + 7] = 0   # suppress neighbourhood
    for th, rr in lines:
        dist = np.abs(xx * np.cos(th) + yy * np.sin(th) - rr)
        band_mask |= dist <= band
    # Erase every dark pixel on a detected line EXCEPT protected piece cores, so
    # a shaft through a piece is removed while the piece body survives.
    erase = band_mask & dark & ~protected

    bg = gray_close(board, close_k)
    cleaned = board.copy()
    cleaned[erase] = bg[erase]
    dbg = np.stack([board] * 3, -1)
    dbg[erase] = [255, 0, 0]
    return cleaned, dbg, len(lines)


def stitch(bdir):
    rows = []
    for r in range(8):
        cols = [np.asarray(Image.open(f'{bdir}/cell_{r}{f}.png').convert('L'))
                for f in range(8)]
        hh = min(c.shape[0] for c in cols)
        rows.append(np.hstack([c[:hh] for c in cols]))
    ww = min(r.shape[1] for r in rows)
    return np.vstack([r[:, :ww] for r in rows])


if __name__ == '__main__':
    bdir = sys.argv[1]
    board = stitch(bdir)
    cleaned, dbg, n = remove_arrows(board)
    print(f'{bdir}: {n} lines removed, board {board.shape}')
    tag = bdir.rstrip('/').replace('/', '_').replace('\\', '_')
    Image.fromarray(dbg).resize((400, 400), Image.NEAREST).save(f'_dbg_{tag}.png')
    Image.fromarray(cleaned).resize((400, 400), Image.NEAREST).save(
        f'_clean_{tag}.png')
