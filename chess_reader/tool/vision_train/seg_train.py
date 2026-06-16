"""Train the arrow-segmentation U-Net and export to ONNX.

Usage:
  python seg_train.py --assets <piece_sets dir> --out ../../assets/models/arrow_seg.onnx
"""
import argparse
import os

import torch
import torch.nn as nn
from torch.utils.data import DataLoader

from seg_dataset import SegDataset
from seg_model import SEG_SIZE, ArrowUNet


def dice_bce(logits, target, pos_weight):
    bce = nn.functional.binary_cross_entropy_with_logits(
        logits, target, pos_weight=pos_weight)
    p = torch.sigmoid(logits)
    inter = (p * target).sum((1, 2, 3))
    dice = 1 - (2 * inter + 1) / (p.sum((1, 2, 3)) + target.sum((1, 2, 3)) + 1)
    return bce + dice.mean()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--assets", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--epochs", type=int, default=6)
    ap.add_argument("--batch", type=int, default=16)
    ap.add_argument("--train-size", type=int, default=8000)
    ap.add_argument("--val-size", type=int, default=1000)
    args = ap.parse_args()

    device = "cuda" if torch.cuda.is_available() else "cpu"
    print(f"device: {device}")
    tr = SegDataset(args.assets, length=args.train_size, seed=1)
    va = SegDataset(args.assets, length=args.val_size, seed=999)
    workers = min(8, os.cpu_count() or 1)
    trdl = DataLoader(tr, batch_size=args.batch, shuffle=True,
                      num_workers=workers, persistent_workers=workers > 0)
    vadl = DataLoader(va, batch_size=args.batch, num_workers=workers,
                      persistent_workers=workers > 0)

    model = ArrowUNet().to(device)
    print(f"params: {sum(p.numel() for p in model.parameters()):,}")
    opt = torch.optim.Adam(model.parameters(), lr=1e-3, weight_decay=1e-4)
    sched = torch.optim.lr_scheduler.CosineAnnealingLR(opt, args.epochs)
    pos_weight = torch.tensor([8.0], device=device)

    for epoch in range(args.epochs):
        model.train()
        run = 0.0
        for i, (x, y) in enumerate(trdl):
            x, y = x.to(device), y.to(device)
            opt.zero_grad()
            loss = dice_bce(model(x), y, pos_weight)
            loss.backward()
            opt.step()
            run += loss.item()
            if i % 50 == 0:
                print(f"  epoch {epoch} step {i}/{len(trdl)} loss {loss.item():.4f}")
        sched.step()

        model.eval()
        inter = union = tp = fp = fn = 0.0
        with torch.no_grad():
            for x, y in vadl:
                x, y = x.to(device), y.to(device)
                p = (torch.sigmoid(model(x)) > 0.5).float()
                inter += (p * y).sum().item()
                union += ((p + y) > 0).sum().item()
                tp += (p * y).sum().item()
                fp += (p * (1 - y)).sum().item()
                fn += ((1 - p) * y).sum().item()
        iou = inter / max(1, union)
        prec = tp / max(1, tp + fp)
        rec = tp / max(1, tp + fn)
        print(f"epoch {epoch}: train_loss {run/len(trdl):.4f} "
              f"IoU {iou:.3f} precision {prec:.3f} recall {rec:.3f}")

    model = model.cpu().eval()
    ckpt = os.path.join(os.path.dirname(__file__), "arrow_seg.pth")
    torch.save(model.state_dict(), ckpt)
    print(f"saved {ckpt}")
    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    dummy = torch.zeros(1, 1, SEG_SIZE, SEG_SIZE)
    torch.onnx.export(model, dummy, args.out,
                      input_names=["board"], output_names=["mask"],
                      dynamic_axes={"board": {0: "b"}, "mask": {0: "b"}},
                      opset_version=17, dynamo=False)
    print(f"exported ONNX -> {args.out}")


if __name__ == "__main__":
    main()
