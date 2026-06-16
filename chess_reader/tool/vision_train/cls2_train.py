"""Train the 2-channel (mask-aware) square classifier and export to ONNX.

Usage:
  python cls2_train.py --assets <piece_sets dir> --out ../../assets/models/square_classifier2.onnx
"""
import argparse
import os

import torch
import torch.nn as nn
from torch.utils.data import DataLoader

from cls2_dataset import Square2Dataset
from cls2_model import SquareCNN2
from model import CELL, CLASSES, NUM_CLASSES


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--assets", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--epochs", type=int, default=7)
    ap.add_argument("--batch", type=int, default=256)
    ap.add_argument("--train-size", type=int, default=70000)
    ap.add_argument("--val-size", type=int, default=9000)
    args = ap.parse_args()

    device = "cuda" if torch.cuda.is_available() else "cpu"
    print(f"device: {device}")
    tr = Square2Dataset(args.assets, length=args.train_size, seed=1)
    va = Square2Dataset(args.assets, length=args.val_size, seed=999)
    workers = min(8, os.cpu_count() or 1)
    trdl = DataLoader(tr, batch_size=args.batch, shuffle=True,
                      num_workers=workers, persistent_workers=workers > 0)
    vadl = DataLoader(va, batch_size=args.batch, num_workers=workers,
                      persistent_workers=workers > 0)

    model = SquareCNN2().to(device)
    print(f"params: {sum(p.numel() for p in model.parameters()):,}")
    opt = torch.optim.Adam(model.parameters(), lr=1e-3, weight_decay=1e-4)
    sched = torch.optim.lr_scheduler.CosineAnnealingLR(opt, args.epochs)
    loss_fn = nn.CrossEntropyLoss()

    for epoch in range(args.epochs):
        model.train()
        run = 0.0
        for i, (x, y) in enumerate(trdl):
            x, y = x.to(device), y.to(device)
            opt.zero_grad()
            loss = loss_fn(model(x), y)
            loss.backward()
            opt.step()
            run += loss.item()
            if i % 50 == 0:
                print(f"  epoch {epoch} step {i}/{len(trdl)} loss {loss.item():.4f}")
        sched.step()

        model.eval()
        correct = total = 0
        per_c = [0] * NUM_CLASSES
        per_t = [0] * NUM_CLASSES
        with torch.no_grad():
            for x, y in vadl:
                x, y = x.to(device), y.to(device)
                pred = model(x).argmax(1)
                correct += (pred == y).sum().item()
                total += y.numel()
                for t, p in zip(y.tolist(), pred.tolist()):
                    per_t[t] += 1
                    if t == p:
                        per_c[t] += 1
        acc = correct / total
        worst = sorted((per_c[c] / max(1, per_t[c]), CLASSES[c] or "·")
                       for c in range(NUM_CLASSES))[:4]
        print(f"epoch {epoch}: train_loss {run/len(trdl):.4f} val_acc {acc:.4f}")
        print("  worst: " + ", ".join(f"{l}={a:.3f}" for a, l in worst))

    model = model.cpu().eval()
    ckpt = os.path.join(os.path.dirname(__file__), "square_classifier2.pth")
    torch.save(model.state_dict(), ckpt)
    print(f"saved {ckpt}")
    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    dummy = torch.zeros(1, 2, CELL, CELL)
    torch.onnx.export(model, dummy, args.out,
                      input_names=["cells"], output_names=["logits"],
                      dynamic_axes={"cells": {0: "b"}, "logits": {0: "b"}},
                      opset_version=17, dynamo=False)
    print(f"exported ONNX -> {args.out}")


if __name__ == "__main__":
    main()
