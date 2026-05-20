import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Stateless image → tensor preprocessing. Pure Dart so it runs inside
/// an isolate worker; no Flutter, no `dart:ui`.
///
/// Layout: NCHW Float32, normalized to mean/std. The defaults match
/// standard ImageNet preprocessing — adjust per your model card.
class ImagePreprocessor {
  const ImagePreprocessor({
    this.inputSize = 224,
    this.mean = const [0.485, 0.456, 0.406],
    this.std = const [0.229, 0.224, 0.225],
  });

  final int inputSize;
  final List<double> mean;
  final List<double> std;

  /// Decode → resize → normalize → flatten to NCHW Float32List.
  /// Returns null if the bytes can't be decoded as an image.
  ({Float32List tensor, List<int> shape})? buildTensor(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;

    final resized = img.copyResize(
      decoded,
      width: inputSize,
      height: inputSize,
      interpolation: img.Interpolation.linear,
    );

    final n = inputSize * inputSize;
    final tensor = Float32List(3 * n);

    // NCHW: R-plane, then G-plane, then B-plane.
    for (var y = 0; y < inputSize; y++) {
      for (var x = 0; x < inputSize; x++) {
        final px = resized.getPixel(x, y);
        final i = y * inputSize + x;
        tensor[i] = (px.rNormalized - mean[0]) / std[0];
        tensor[n + i] = (px.gNormalized - mean[1]) / std[1];
        tensor[2 * n + i] = (px.bNormalized - mean[2]) / std[2];
      }
    }

    return (tensor: tensor, shape: [1, 3, inputSize, inputSize]);
  }
}
