"""Per-square chess piece classifier.

Small CNN: a 32x32 grayscale cell -> one of 13 classes. Kept tiny (~150k
params) so it runs fast on CPU/mobile via ONNX Runtime.
"""

import torch
import torch.nn as nn

# Canonical class order. MUST match Dart `squareLabels` in
# lib/features/vision/domain/square_classifier.dart.
CLASSES = ["K", "Q", "R", "B", "N", "P", "k", "q", "r", "b", "n", "p", ""]
NUM_CLASSES = len(CLASSES)
CELL = 32


class SquareCNN(nn.Module):
    def __init__(self, num_classes: int = NUM_CLASSES):
        super().__init__()
        self.features = nn.Sequential(
            nn.Conv2d(1, 16, 3, padding=1),
            nn.BatchNorm2d(16),
            nn.ReLU(inplace=True),
            nn.MaxPool2d(2),  # 16
            nn.Conv2d(16, 32, 3, padding=1),
            nn.BatchNorm2d(32),
            nn.ReLU(inplace=True),
            nn.MaxPool2d(2),  # 8
            nn.Conv2d(32, 64, 3, padding=1),
            nn.BatchNorm2d(64),
            nn.ReLU(inplace=True),
            nn.MaxPool2d(2),  # 4
        )
        self.classifier = nn.Sequential(
            nn.Flatten(),
            nn.Linear(64 * 4 * 4, 128),
            nn.ReLU(inplace=True),
            nn.Dropout(0.3),
            nn.Linear(128, num_classes),
        )

    def forward(self, x):
        return self.classifier(self.features(x))
