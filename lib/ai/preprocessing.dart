import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Stateless image → tensor preprocessing. Pure Dart so it runs inside
/// an isolate worker; no Flutter, no `dart:ui`.

/// Memory layout the model expects.
enum TensorLayout {
  /// `[batch, channels, height, width]` — PyTorch / most ImageNet models.
  nchw,

  /// `[batch, height, width, channels]` — TensorFlow / Keras / NIMA.
  nhwc,
}

/// Pixel normalization scheme.
enum Normalization {
  /// `(x - mean) / std`, with ImageNet stats by default.
  imagenet,

  /// `(x / 127.5) - 1.0` — MobileNet / NIMA / many TF models.
  mobilenet,

  /// `x / 255.0` — raw 0..1 floats, no centering.
  unit,
}

class PreprocessConfig {
  const PreprocessConfig({
    this.inputSize = 224,
    this.layout = TensorLayout.nhwc,
    this.normalization = Normalization.mobilenet,
    this.mean = const [0.485, 0.456, 0.406],
    this.std = const [0.229, 0.224, 0.225],
  });

  final int inputSize;
  final TensorLayout layout;
  final Normalization normalization;
  final List<double> mean;
  final List<double> std;

  /// Default for the PINTO-style ONNX exports of NIMA MobileNet
  /// (aesthetic / technical), which are transposed to NCHW during
  /// conversion even though the original Keras model is NHWC.
  ///   - 224×224 NCHW
  ///   - MobileNet preprocessing: `(x/127.5) - 1.0`
  static const nimaMobileNet = PreprocessConfig(
    inputSize: 224,
    layout: TensorLayout.nchw,
    normalization: Normalization.mobilenet,
  );

  /// Same as [nimaMobileNet] but NHWC for Keras-native ONNX exports.
  static const nimaMobileNetNhwc = PreprocessConfig(
    inputSize: 224,
    layout: TensorLayout.nhwc,
    normalization: Normalization.mobilenet,
  );

  /// MANIQA (e.g. `maniqa_kadid10k.onnx`) — PyTorch original, NCHW,
  /// ImageNet mean/std normalization. The model returns a scalar quality
  /// score in roughly [0, 1].
  static const maniqaImageNet = PreprocessConfig(
    inputSize: 224,
    layout: TensorLayout.nchw,
    normalization: Normalization.imagenet,
  );

  /// Safe generic fallback for unknown ONNX models — NCHW, ImageNet
  /// normalization (covers most PyTorch-exported vision models).
  static const genericImageNet = PreprocessConfig(
    inputSize: 224,
    layout: TensorLayout.nchw,
    normalization: Normalization.imagenet,
  );

  /// Picks the right preset based on the model file name. We can't read
  /// preprocessing requirements from ONNX metadata reliably, so we match
  /// by name — extend this list as more models are added.
  static PreprocessConfig forModelFileName(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.contains('nima')) return nimaMobileNet;
    if (lower.contains('maniqa')) return maniqaImageNet;
    return genericImageNet;
  }
}

class ImagePreprocessor {
  const ImagePreprocessor({this.config = PreprocessConfig.nimaMobileNet});

  final PreprocessConfig config;

  /// Decode → resize → normalize → flatten to Float32List.
  /// Returns null if bytes can't be decoded as an image.
  ({Float32List tensor, List<int> shape})? buildTensor(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;

    final size = config.inputSize;
    final resized = img.copyResize(
      decoded,
      width: size,
      height: size,
      interpolation: img.Interpolation.linear,
    );

    final tensor = Float32List(3 * size * size);
    final norm = config.normalization;
    final mean = config.mean;
    final std = config.std;

    if (config.layout == TensorLayout.nhwc) {
      // [1, H, W, 3] — channel is the fastest-varying axis.
      var idx = 0;
      for (var y = 0; y < size; y++) {
        for (var x = 0; x < size; x++) {
          final px = resized.getPixel(x, y);
          tensor[idx++] = _norm(px.rNormalized, 0, norm, mean, std);
          tensor[idx++] = _norm(px.gNormalized, 1, norm, mean, std);
          tensor[idx++] = _norm(px.bNormalized, 2, norm, mean, std);
        }
      }
      return (tensor: tensor, shape: [1, size, size, 3]);
    } else {
      // [1, 3, H, W] — channel is the slowest-varying axis.
      final plane = size * size;
      for (var y = 0; y < size; y++) {
        for (var x = 0; x < size; x++) {
          final px = resized.getPixel(x, y);
          final i = y * size + x;
          tensor[i] = _norm(px.rNormalized, 0, norm, mean, std);
          tensor[plane + i] = _norm(px.gNormalized, 1, norm, mean, std);
          tensor[2 * plane + i] = _norm(px.bNormalized, 2, norm, mean, std);
        }
      }
      return (tensor: tensor, shape: [1, 3, size, size]);
    }
  }

  static double _norm(
    num v,
    int channel,
    Normalization n,
    List<double> mean,
    List<double> std,
  ) {
    final d = v.toDouble();
    switch (n) {
      case Normalization.imagenet:
        return (d - mean[channel]) / std[channel];
      case Normalization.mobilenet:
        // d is already 0..1 (rNormalized = r / 255). Convert to -1..1.
        return d * 2.0 - 1.0;
      case Normalization.unit:
        return d;
    }
  }
}
