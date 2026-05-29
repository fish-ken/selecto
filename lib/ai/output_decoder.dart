import 'dart:typed_data';

import 'package:onnxruntime_v2/onnxruntime_v2.dart';

/// Decoded scalar metrics from a single ONNX inference, on the project's
/// 0..10 reporting scale.
///
/// A score of exactly `0` is reserved as a "not analyzed / decode
/// failure" sentinel — real NIMA / MANIQA outputs can't reach it
/// because the MOS path is bounded below by 1, and the sigmoid path
/// scales a strictly positive sigmoid output.
class DecodedScore {
  const DecodedScore({
    required this.quality,
    required this.sharpness,
    required this.faceCount,
    required this.hasBlink,
  });

  /// "Decode failed" / "not analyzed" sentinel. All fields are the
  /// zero-value of their type.
  static const empty = DecodedScore(
    quality: 0,
    sharpness: 0,
    faceCount: 0,
    hasBlink: false,
  );

  final double quality;
  final double sharpness;
  final int faceCount;
  final bool hasBlink;
}

/// The shape of a model's output head — how its raw output tensor maps
/// onto the project's 0..10 quality scale. Declared per-model on its
/// [ModelConfig] (see `lib/ai/model_config.dart`) so each model's output
/// contract lives in exactly one place instead of being sniffed at runtime.
enum OutputKind {
  /// **NIMA** — length-10 softmax distribution. Decoded as the mean
  /// opinion score `Σ (i+1)·p_i ∈ [1, 10]`, the NIMA paper's reporting
  /// scale.
  nimaDistribution,

  /// **Scalar IQA** (MANIQA, MUSIQ, CLIP-IQA, …) — a single float treated
  /// as a sigmoid-bounded `[0, 1]` value, scaled ×10. Extra trailing
  /// values, if present, fill sharpness / faceCount / blink.
  scalarSigmoid,
}

/// Converts the raw outputs of an `OrtSession.run` call into a
/// [DecodedScore], using the [kind] declared by the active model's
/// [ModelConfig].
///
/// To support a fundamentally different output format (e.g. multi-label
/// classifier, regression in an unbounded range), add a value to
/// [OutputKind] and a matching branch below.
DecodedScore decodeScore(List<OrtValue?> outputs, OutputKind kind) {
  if (outputs.isEmpty) return DecodedScore.empty;
  final flat = _flattenToDoubles(outputs.first?.value);
  if (flat.isEmpty) return DecodedScore.empty;

  return switch (kind) {
    OutputKind.nimaDistribution => _decodeNima(flat),
    OutputKind.scalarSigmoid => _decodeScalar(flat),
  };
}

/// NIMA — 10-bin probability distribution → MOS in [1, 10].
DecodedScore _decodeNima(List<double> flat) {
  var mos = 0.0;
  final n = flat.length < 10 ? flat.length : 10;
  for (var i = 0; i < n; i++) {
    mos += (i + 1) * flat[i];
  }
  return DecodedScore(
    quality: mos.clamp(0.0, 10.0),
    sharpness: 0,
    faceCount: 0,
    hasBlink: false,
  );
}

/// MANIQA / MUSIQ / CLIP-IQA — single sigmoid-style float in roughly
/// [0, 1], scaled onto the 0..10 axis.
DecodedScore _decodeScalar(List<double> flat) {
  return DecodedScore(
    quality: (flat[0] * 10.0).clamp(0.0, 10.0),
    sharpness: flat.length > 1 ? (flat[1] * 10.0).clamp(0.0, 10.0) : 0.0,
    faceCount: flat.length > 2 ? flat[2].round() : 0,
    hasBlink: flat.length > 3 ? flat[3] > 0.5 : false,
  );
}

/// Flattens whatever `OrtValue.value` returned (`Float32List`, nested
/// `List`s of arbitrary depth, or scalars) into a single `List<double>`.
List<double> _flattenToDoubles(Object? value) {
  if (value == null) return const [];
  if (value is Float32List) return value.toList(growable: false);
  if (value is List) {
    return _walkFlat(value)
        .whereType<num>()
        .map((n) => n.toDouble())
        .toList(growable: false);
  }
  return const [];
}

Iterable<Object?> _walkFlat(Object? v) sync* {
  if (v is Iterable) {
    for (final x in v) {
      yield* _walkFlat(x);
    }
  } else {
    yield v;
  }
}
