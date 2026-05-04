import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'path_simplifier.dart';

class EdgeDetectionResult {
  final List<List<ui.Offset>> paths;
  final ui.Size imageSize;

  const EdgeDetectionResult({required this.paths, required this.imageSize});
}

class EdgeDetectionService {
  static Future<EdgeDetectionResult> detect(
    File imageFile, {
    double highThreshold = 0.20,
    int minPathLength = 15,
  }) async {
    final bytes = await imageFile.readAsBytes();
    final result = await compute(_detectInIsolate, {
      'bytes': bytes,
      'highThreshold': highThreshold,
      'minPathLength': minPathLength,
    });
    return result;
  }

  static Future<EdgeDetectionResult> detectFromBytes(
    Uint8List bytes, {
    double highThreshold = 0.20,
    int minPathLength = 15,
  }) async {
    final result = await compute(_detectInIsolate, {
      'bytes': bytes,
      'highThreshold': highThreshold,
      'minPathLength': minPathLength,
    });
    return result;
  }
}

EdgeDetectionResult _detectInIsolate(Map<String, dynamic> params) {
  final Uint8List bytes = params['bytes'];
  final double highThreshold = params['highThreshold'];
  final int minPathLength = params['minPathLength'];

  // Step 1: Decode and resize
  var decoded = img.decodeImage(bytes);
  if (decoded == null) {
    return const EdgeDetectionResult(paths: [], imageSize: ui.Size(0, 0));
  }

  final maxDim = 600;
  if (decoded.width > maxDim || decoded.height > maxDim) {
    if (decoded.width > decoded.height) {
      decoded = img.copyResize(decoded, width: maxDim);
    } else {
      decoded = img.copyResize(decoded, height: maxDim);
    }
  }

  final w = decoded.width;
  final h = decoded.height;

  // Step 2: Grayscale
  final gray = List<List<int>>.generate(
    h,
    (y) => List<int>.generate(w, (x) {
      final pixel = decoded!.getPixel(x, y);
      final r = pixel.r.toInt();
      final g = pixel.g.toInt();
      final b = pixel.b.toInt();
      return (0.299 * r + 0.587 * g + 0.114 * b).round().clamp(0, 255);
    }),
  );

  // Step 3: Gaussian blur (3x3)
  final blurred = List<List<int>>.generate(h, (y) => List<int>.filled(w, 0));
  const kernel = [
    [1, 2, 1],
    [2, 4, 2],
    [1, 2, 1],
  ];
  for (int y = 1; y < h - 1; y++) {
    for (int x = 1; x < w - 1; x++) {
      int sum = 0;
      for (int ky = -1; ky <= 1; ky++) {
        for (int kx = -1; kx <= 1; kx++) {
          sum += gray[y + ky][x + kx] * kernel[ky + 1][kx + 1];
        }
      }
      blurred[y][x] = (sum ~/ 16).clamp(0, 255);
    }
  }

  // Step 4: Sobel edge detection
  final magnitude = List<List<double>>.generate(h, (y) => List<double>.filled(w, 0));
  final direction = List<List<double>>.generate(h, (y) => List<double>.filled(w, 0));
  double maxMag = 0;

  const gx = [
    [-1, 0, 1],
    [-2, 0, 2],
    [-1, 0, 1],
  ];
  const gy = [
    [-1, -2, -1],
    [0, 0, 0],
    [1, 2, 1],
  ];

  for (int y = 1; y < h - 1; y++) {
    for (int x = 1; x < w - 1; x++) {
      double sumX = 0, sumY = 0;
      for (int ky = -1; ky <= 1; ky++) {
        for (int kx = -1; kx <= 1; kx++) {
          final val = blurred[y + ky][x + kx].toDouble();
          sumX += val * gx[ky + 1][kx + 1];
          sumY += val * gy[ky + 1][kx + 1];
        }
      }
      final mag = sqrt(sumX * sumX + sumY * sumY);
      magnitude[y][x] = mag;
      direction[y][x] = atan2(sumY, sumX);
      if (mag > maxMag) maxMag = mag;
    }
  }

  // Step 5: Thresholding with hysteresis
  final highT = maxMag * highThreshold;
  final lowT = highT * 0.4;

  // 0 = none, 1 = weak, 2 = strong
  final edgeType = List<List<int>>.generate(h, (y) => List<int>.filled(w, 0));

  for (int y = 1; y < h - 1; y++) {
    for (int x = 1; x < w - 1; x++) {
      if (magnitude[y][x] >= highT) {
        edgeType[y][x] = 2;
      } else if (magnitude[y][x] >= lowT) {
        edgeType[y][x] = 1;
      }
    }
  }

  // Step 6: Non-maximum suppression (simplified)
  final suppressed = List<List<int>>.generate(h, (y) => List<int>.filled(w, 0));
  for (int y = 1; y < h - 1; y++) {
    for (int x = 1; x < w - 1; x++) {
      if (edgeType[y][x] == 0) continue;

      final angle = direction[y][x];
      final deg = (angle * 180 / pi) % 180;
      double n1 = 0, n2 = 0;

      if (deg < 22.5 || deg >= 157.5) {
        n1 = magnitude[y][x - 1];
        n2 = magnitude[y][x + 1];
      } else if (deg < 67.5) {
        n1 = magnitude[y - 1][x + 1];
        n2 = magnitude[y + 1][x - 1];
      } else if (deg < 112.5) {
        n1 = magnitude[y - 1][x];
        n2 = magnitude[y + 1][x];
      } else {
        n1 = magnitude[y - 1][x - 1];
        n2 = magnitude[y + 1][x + 1];
      }

      if (magnitude[y][x] >= n1 && magnitude[y][x] >= n2) {
        suppressed[y][x] = edgeType[y][x];
      }
    }
  }

  // Step 6b: Promote weak edges connected to strong edges
  bool changed = true;
  while (changed) {
    changed = false;
    for (int y = 1; y < h - 1; y++) {
      for (int x = 1; x < w - 1; x++) {
        if (suppressed[y][x] != 1) continue;
        bool hasStrong = false;
        for (int dy = -1; dy <= 1 && !hasStrong; dy++) {
          for (int dx = -1; dx <= 1 && !hasStrong; dx++) {
            if (dx == 0 && dy == 0) continue;
            if (suppressed[y + dy][x + dx] == 2) hasStrong = true;
          }
        }
        if (hasStrong) {
          suppressed[y][x] = 2;
          changed = true;
        }
      }
    }
  }

  // Step 7: Chain edge pixels into paths using flood-fill tracing
  final visited = List<List<bool>>.generate(h, (y) => List<bool>.filled(w, false));
  final chains = <List<ui.Offset>>[];

  for (int y = 1; y < h - 1; y++) {
    for (int x = 1; x < w - 1; x++) {
      if (suppressed[y][x] != 2 || visited[y][x]) continue;

      final chain = <ui.Offset>[];
      _traceChain(x, y, w, h, suppressed, visited, chain);

      if (chain.length >= minPathLength) {
        chains.add(chain);
      }
    }
  }

  // Step 8: Simplify each chain with RDP
  final simplified = chains.map((chain) {
    return PathSimplifier.rdpSimplify(chain, 2.5);
  }).where((c) => c.length >= 2).toList();

  return EdgeDetectionResult(
    paths: simplified,
    imageSize: ui.Size(w.toDouble(), h.toDouble()),
  );
}

void _traceChain(
  int startX,
  int startY,
  int w,
  int h,
  List<List<int>> edges,
  List<List<bool>> visited,
  List<ui.Offset> chain,
) {
  final stack = <(int, int)>[(startX, startY)];

  while (stack.isNotEmpty) {
    final (cx, cy) = stack.removeLast();
    if (cx < 0 || cx >= w || cy < 0 || cy >= h) continue;
    if (visited[cy][cx] || edges[cy][cx] != 2) continue;

    visited[cy][cx] = true;
    chain.add(ui.Offset(cx.toDouble(), cy.toDouble()));

    // 8-connected neighbors — prefer continuing in a line
    final neighbors = <(int, int)>[];
    for (int dy = -1; dy <= 1; dy++) {
      for (int dx = -1; dx <= 1; dx++) {
        if (dx == 0 && dy == 0) continue;
        final nx = cx + dx;
        final ny = cy + dy;
        if (nx >= 0 && nx < w && ny >= 0 && ny < h && !visited[ny][nx] && edges[ny][nx] == 2) {
          neighbors.add((nx, ny));
        }
      }
    }

    // Add neighbors to stack (only the first unvisited to keep chain-like)
    if (neighbors.isNotEmpty) {
      stack.add(neighbors.first);
    }
  }
}
