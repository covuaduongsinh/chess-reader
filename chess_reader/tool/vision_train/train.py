"""Train the per-square classifier and export to ONNX.

Usage:
  python train.py --assets <chessground piece_sets dir> --out ../../assets/models/square_classifier.onnx

The piece_sets dir is the chessground package assets, e.g.
  %LOCALAPPDATA%/Pub/Cache/hosted/pub.dev/chessground-10.0.3/assets/piece_sets
"""

import argparse
import os

import torch
import torch.nn as nn
from torch.utils.data import DataLoader

from dataset import SquareDataset
from model import CELL, CLASSES, NUM_CLASSES, SquareCNN


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--assets", required=True, help="chessground piece_sets dir")
    ap.add_argument("--out", required=True, help="output ONNX path")
    ap.add_argument("--epochs", type=int, default=6)
    ap.add_argument("--batch", type=int, default=256)
    ap.add_argument("--train-size", type=int, default=60000)
    ap.add_argument("--val-size", type=int, default=8000)
    args = ap.parse_args()

    device = "cuda" if torch.cuda.is_available() else "cpu"
    print(f"device: {device}")

    train_ds = SquareDataset(args.assets, length=args.train_size, seed=1)
    val_ds = SquareDataset(args.assets, length=args.val_size, seed=999)
    print(f"piece sets: {len(train_ds.set_names)} -> {train_ds.set_names}")

    workers = min(8, os.cpu_count() or 1)
    train_dl = DataLoader(train_ds, batch_size=args.batch, shuffle=True,
                          num_workers=workers, persistent_workers=workers > 0)
    val_dl = DataLoader(val_ds, batch_size=args.batch, num_workers=workers,
                        persistent_workers=workers > 0)

    model = SquareCNN().to(device)
    n_params = sum(p.numel() for p in model.parameters())
    print(f"params: {n_params:,}")

    opt = torch.optim.Adam(model.parameters(), lr=1e-3, weight_decay=1e-4)
    sched = torch.optim.lr_scheduler.CosineAnnealingLR(opt, args.epochs)
    loss_fn = nn.CrossEntropyLoss()

    for epoch in range(args.epochs):
        model.train()
        running = 0.0
        for i, (x, y) in enumerate(train_dl):
            x, y = x.to(device), y.to(device)
            opt.zero_grad()
            out = model(x)
            loss = loss_fn(out, y)
            loss.backward()
            opt.step()
            running += loss.item()
            if i % 50 == 0:
                print(f"  epoch {epoch} step {i}/{len(train_dl)} "
                      f"loss {loss.item():.4f}")
        sched.step()

        # Validation.
        model.eval()
        correct = total = 0
        per_class_correct = [0] * NUM_CLASSES
        per_class_total = [0] * NUM_CLASSES
        with torch.no_grad():
            for x, y in val_dl:
                x, y = x.to(device), y.to(device)
                pred = model(x).argmax(1)
                correct += (pred == y).sum().item()
                total += y.numel()
                for t, p in zip(y.tolist(), pred.tolist()):
                    per_class_total[t] += 1
                    if t == p:
                        per_class_correct[t] += 1
        acc = correct / total
        print(f"epoch {epoch}: train_loss {running/len(train_dl):.4f} "
              f"val_acc {acc:.4f}")
        worst = sorted(
            ((per_class_correct[c] / max(1, per_class_total[c]), CLASSES[c] or "·")
             for c in range(NUM_CLASSES)))[:4]
        print("  worst classes: " +
              ", ".join(f"{lbl}={a:.3f}" for a, lbl in worst))

    model = model.cpu().eval()
    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    # Keep the training checkpoint beside this script, not in app assets.
    ckpt = os.path.join(os.path.dirname(__file__), "square_classifier.pth")
    torch.save(model.state_dict(), ckpt)
    print(f"saved checkpoint -> {ckpt}")
    _export_onnx(model, args.out)


def _export_onnx(model, out_path):
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    dummy = torch.zeros(1, 1, CELL, CELL)
    # Legacy TorchScript exporter (dynamo=False): stable for this simple CNN
    # and independent of the newer onnxscript-based path.
    torch.onnx.export(
        model, dummy, out_path,
        input_names=["cells"], output_names=["logits"],
        dynamic_axes={"cells": {0: "batch"}, "logits": {0: "batch"}},
        opset_version=17,
        dynamo=False,
    )
    print(f"exported ONNX -> {out_path}")

    # Sanity-check with onnxruntime.
    import numpy as np
    import onnxruntime as ort

    sess = ort.InferenceSession(out_path)
    out = sess.run(None, {"cells": np.zeros((64, 1, CELL, CELL), np.float32)})
    print(f"onnxruntime check: output shape {out[0].shape}")


if __name__ == "__main__":
    main()
