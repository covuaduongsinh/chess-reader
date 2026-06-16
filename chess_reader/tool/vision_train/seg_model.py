"""Tiny U-Net for annotation (arrow) segmentation of a board crop."""
import torch
import torch.nn as nn

SEG_SIZE = 192  # input is 1 x SEG_SIZE x SEG_SIZE, must be divisible by 4


class _Block(nn.Module):
    def __init__(self, i, o):
        super().__init__()
        self.c = nn.Sequential(
            nn.Conv2d(i, o, 3, padding=1), nn.BatchNorm2d(o), nn.ReLU(inplace=True),
            nn.Conv2d(o, o, 3, padding=1), nn.BatchNorm2d(o), nn.ReLU(inplace=True),
        )

    def forward(self, x):
        return self.c(x)


class ArrowUNet(nn.Module):
    def __init__(self, ch=16):
        super().__init__()
        self.d1 = _Block(1, ch)
        self.d2 = _Block(ch, ch * 2)
        self.d3 = _Block(ch * 2, ch * 4)
        self.pool = nn.MaxPool2d(2)
        self.u2 = nn.ConvTranspose2d(ch * 4, ch * 2, 2, 2)
        self.c2 = _Block(ch * 4, ch * 2)
        self.u1 = nn.ConvTranspose2d(ch * 2, ch, 2, 2)
        self.c1 = _Block(ch * 2, ch)
        self.out = nn.Conv2d(ch, 1, 1)

    def forward(self, x):
        x1 = self.d1(x)
        x2 = self.d2(self.pool(x1))
        x3 = self.d3(self.pool(x2))
        y = self.u2(x3)
        y = self.c2(torch.cat([y, x2], 1))
        y = self.u1(y)
        y = self.c1(torch.cat([y, x1], 1))
        return self.out(y)  # logits
