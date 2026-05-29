import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Image → float tensor conversion for IQA models. Pure Dart so this
/// runs inside the worker isolate (no Flutter, no `dart:ui`).
///
/// Two pieces:
///   * [PreprocessConfig] — value object describing how a model wants
///     its input: tensor layout (NCHW vs NHWC), normalization scheme,
///     input size, channel statistics. Per-model presets live as
///     `static const` fields on this class.
///   * [ImagePreprocessor] — stateless tensor builder driven by a
///     [PreprocessConfig].

/// Memory layout the model expects for its input tensor.
enum TensorLayout {
  /// `[batch, channels, height, width]` — PyTorch / most ImageNet models.
  nchw,

  /// `[batch, height, width, channels]` — TensorFlow / Keras / NIMA.
  nhwc,
}

/// Pixel value normalization scheme.
enum Normalization {
  /// `(x - mean) / std`, ImageNet stats by default.
  imagenet,

  /// `(x / 127.5) - 1.0` — MobileNet / NIMA / many TF exports.
  mobilenet,

  /// `x / 255.0` — raw [0, 1] floats, no centering.
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

  // ───── Per-model presets ────────────────────────────────────────────
  //
  // Each preset is referenced by a `ModelConfig` subclass in
  // `model_config.dart`, which is the single source of truth for which
  // model uses which preprocessing. To add a model: add a preset here (if
  // its layout/normalization is new), then point a new `ModelConfig` at it.
  //
  // If the model's output format is also new (not a 10-bin softmax or
  // a [0, 1] sigmoid scalar), see `output_decoder.dart`.

  /// NIMA MobileNet aesthetic / technical — PINTO-style exports.
  ///   - 224×224 NCHW
  ///   - MobileNet preprocessing `(x/127.5) - 1.0`
  static const nimaMobileNet = PreprocessConfig(
    inputSize: 224,
    layout: TensorLayout.nchw,
    normalization: Normalization.mobilenet,
  );

  /// NIMA Keras-native (NHWC) export — input name typically `input_1`.
  static const nimaMobileNetNhwc = PreprocessConfig(
    inputSize: 224,
    layout: TensorLayout.nhwc,
    normalization: Normalization.mobilenet,
  );

  /// MANIQA / KADID10K — PyTorch original, ImageNet normalization,
  /// sigmoid scalar quality score output.
  static const maniqaImageNet = PreprocessConfig(
    inputSize: 224,
    layout: TensorLayout.nchw,
    normalization: Normalization.imagenet,
  );

  /// Catch-all default. NCHW + ImageNet covers most PyTorch-exported
  /// vision networks; reference it from a `ModelConfig` when a model
  /// doesn't need its own preset.
  static const genericImageNet = PreprocessConfig(
    inputSize: 224,
    layout: TensorLayout.nchw,
    normalization: Normalization.imagenet,
  );
}

/// Stateless tensor builder. Decodes the bytes of a JPEG/PNG/etc,
/// resizes to the model's input dimensions, applies the normalization
/// scheme, and packs the floats according to the requested layout.
class ImagePreprocessor {
  const ImagePreprocessor({this.config = PreprocessConfig.nimaMobileNet});

  final PreprocessConfig config;

  /// Decode → resize → normalize → pack. Returns `null` if the bytes
  /// can't be decoded (corrupt image, unsupported codec).
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
          tensor[idx++] = _normalize(px.rNormalized, 0, norm, mean, std);
          tensor[idx++] = _normalize(px.gNormalized, 1, norm, mean, std);
          tensor[idx++] = _normalize(px.bNormalized, 2, norm, mean, std);
        }
      }
      return (tensor: tensor, shape: [1, size, size, 3]);
    }

    // NCHW: [1, 3, H, W] — channel is the slowest-varying axis.
    final plane = size * size;
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        final px = resized.getPixel(x, y);
        final i = y * size + x;
        tensor[i] = _normalize(px.rNormalized, 0, norm, mean, std);
        tensor[plane + i] = _normalize(px.gNormalized, 1, norm, mean, std);
        tensor[2 * plane + i] = _normalize(px.bNormalized, 2, norm, mean, std);
      }
    }
    return (tensor: tensor, shape: [1, 3, size, size]);
  }

  static double _normalize(
    num value,
    int channel,
    Normalization scheme,
    List<double> mean,
    List<double> std,
  ) {
    final v = value.toDouble();
    switch (scheme) {
      case Normalization.imagenet:
        return (v - mean[channel]) / std[channel];
      case Normalization.mobilenet:
        // `rNormalized` etc. are already 0..1, so * 2 - 1 maps to -1..1.
        return v * 2.0 - 1.0;
      case Normalization.unit:
        return v;
    }
  }
}
