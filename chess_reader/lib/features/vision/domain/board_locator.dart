import 'package:image/image.dart' as img;

/// A candidate chess diagram found on a page image, in pixel coordinates.
class LocatedBoard {
  const LocatedBoard({
    required this.left,
    required this.top,
    required this.size,
  });

  final int left;
  final int top;

  /// Boards are square; size is the side length.
  final int size;
}

/// Finds printed chess diagrams on a page raster.
///
/// Classical CV, pure Dart: printed diagrams are axis-aligned, high-contrast
/// squares with a connected dark frame (or dark-square fill), so a connected-
/// component scan over the thresholded image finds them as large, square-ish
/// components. No perspective handling — that's the camera pipeline's job
/// (future), which will replace this stage behind the same interface.
abstract class BoardLocator {
  List<LocatedBoard> locate(img.Image page);
}

class ConnectedComponentBoardLocator implements BoardLocator {
  const ConnectedComponentBoardLocator({
    this.minRelativeSize = 0.18,
    this.maxAspectError = 0.12,
  });

  /// Minimum board side relative to the page's shorter dimension.
  final double minRelativeSize;

  /// Allowed |width-height|/size deviation from a perfect square.
  final double maxAspectError;

  @override
  List<LocatedBoard> locate(img.Image page) {
    final gray = img.grayscale(img.Image.from(page));
    final w = gray.width, h = gray.height;
    final threshold = _otsu(gray);

    // Two-pass connected-component labeling over dark pixels with union-find.
    final labels = List<int>.filled(w * h, 0);
    final parent = <int>[0];
    int find(int x) {
      var root = x;
      while (parent[root] != root) {
        root = parent[root];
      }
      while (parent[x] != root) {
        final next = parent[x];
        parent[x] = root;
        x = next;
      }
      return root;
    }

    void union(int a, int b) {
      final ra = find(a), rb = find(b);
      if (ra != rb) parent[rb] = ra;
    }

    var nextLabel = 1;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        if (gray.getPixel(x, y).r >= threshold) continue;
        final left = x > 0 ? labels[y * w + x - 1] : 0;
        final up = y > 0 ? labels[(y - 1) * w + x] : 0;
        if (left == 0 && up == 0) {
          labels[y * w + x] = nextLabel;
          parent.add(nextLabel);
          nextLabel++;
        } else if (left != 0 && up != 0) {
          labels[y * w + x] = left;
          union(left, up);
        } else {
          labels[y * w + x] = left != 0 ? left : up;
        }
      }
    }

    // Collect component bounding boxes.
    final minX = <int, int>{}, minY = <int, int>{};
    final maxX = <int, int>{}, maxY = <int, int>{};
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final raw = labels[y * w + x];
        if (raw == 0) continue;
        final root = find(raw);
        minX.update(root, (v) => v < x ? v : x, ifAbsent: () => x);
        maxX.update(root, (v) => v > x ? v : x, ifAbsent: () => x);
        minY.update(root, (v) => v < y ? v : y, ifAbsent: () => y);
        maxY.update(root, (v) => v > y ? v : y, ifAbsent: () => y);
      }
    }

    final minSide = (w < h ? w : h) * minRelativeSize;
    final boards = <LocatedBoard>[];
    for (final label in minX.keys) {
      final bw = maxX[label]! - minX[label]! + 1;
      final bh = maxY[label]! - minY[label]! + 1;
      final size = (bw + bh) ~/ 2;
      if (size < minSide) continue;
      if ((bw - bh).abs() / size > maxAspectError) continue;
      boards.add(LocatedBoard(left: minX[label]!, top: minY[label]!, size: size));
    }
    // Largest first; drop boards nested inside another (frame + fill can
    // produce two components for the same diagram).
    boards.sort((a, b) => b.size.compareTo(a.size));
    final result = <LocatedBoard>[];
    for (final b in boards) {
      final nested = result.any((r) =>
          b.left >= r.left - r.size ~/ 16 &&
          b.top >= r.top - r.size ~/ 16 &&
          b.left + b.size <= r.left + r.size + r.size ~/ 16 &&
          b.top + b.size <= r.top + r.size + r.size ~/ 16);
      if (!nested) result.add(b);
    }
    return result;
  }

  /// Otsu's threshold over the grayscale histogram.
  int _otsu(img.Image gray) {
    final hist = List<int>.filled(256, 0);
    for (final p in gray) {
      hist[p.r.toInt()]++;
    }
    final total = gray.width * gray.height;
    var sum = 0.0;
    for (var i = 0; i < 256; i++) {
      sum += i * hist[i];
    }
    var sumB = 0.0, wB = 0, best = 0.0;
    var threshold = 127;
    for (var i = 0; i < 256; i++) {
      wB += hist[i];
      if (wB == 0) continue;
      final wF = total - wB;
      if (wF == 0) break;
      sumB += i * hist[i];
      final mB = sumB / wB;
      final mF = (sum - sumB) / wF;
      final between = wB * wF * (mB - mF) * (mB - mF);
      if (between > best) {
        best = between;
        threshold = i;
      }
    }
    return threshold;
  }
}
