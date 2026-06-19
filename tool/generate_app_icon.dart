// Generates a placeholder app icon at assets/icon/app_icon.png:
// a brand-indigo rounded square with a centered white star (matching the
// app's BestShots star motif). Replace assets/icon/app_icon.png with a real
// design later, then re-run `dart run flutter_launcher_icons`.
//
//   dart run tool/generate_app_icon.dart
import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

void main() {
  const size = 1024;
  final image = img.Image(width: size, height: size, numChannels: 4);
  img.fill(image, color: img.ColorRgba8(0, 0, 0, 0)); // transparent

  // Rounded-square brand background with a small transparent margin.
  const inset = 64;
  img.fillRect(
    image,
    x1: inset,
    y1: inset,
    x2: size - inset - 1,
    y2: size - inset - 1,
    color: img.ColorRgba8(0x3D, 0x5A, 0xFE, 0xFF), // indigo
    radius: 190,
  );

  // Centered white 5-point star.
  const cx = size / 2.0;
  const cy = size / 2.0;
  const outer = size * 0.30;
  const inner = outer * 0.42;
  final vertices = <img.Point>[
    for (var i = 0; i < 10; i++)
      () {
        final r = i.isEven ? outer : inner;
        final a = -math.pi / 2 + i * math.pi / 5;
        return img.Point(cx + r * math.cos(a), cy + r * math.sin(a));
      }(),
  ];
  img.fillPolygon(
    image,
    vertices: vertices,
    color: img.ColorRgba8(255, 255, 255, 255),
  );

  final out = File('assets/icon/app_icon.png');
  out.parent.createSync(recursive: true);
  out.writeAsBytesSync(img.encodePng(image));
  stdout.writeln('wrote ${out.path} (${size}x$size)');
}
