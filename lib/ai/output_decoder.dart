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

/// Converts the raw outputs of an `OrtSession.run` call into a
/// [DecodedScore]. Dispatches purely on the output tensor's *shape* and
/// *value distribution*, not on model name, so adding a new model with a
/// recognized output format requires no changes here.
///
/// Currently supported output formats:
///   * **NIMA** — length-10 softmax distribution. Decoded as
///     mean opinion score `Σ (i+1)·p_i ∈ [1, 10]`, the NIMA paper's
///     reporting scale.
///   * **Scalar IQA** (MANIQA, MUSIQ, CLIP-IQA, …) — single float
///     treated as a sigmoid-bounded `[0, 1]` value, scaled ×10.
///
/// To support a fundamentally different output format (e.g. multi-label
/// classifier, regression in an unbounded range), add a new branch ABOVE
/// the scalar fallback below.
DecodedScore decodeScore(List<OrtValue?> outputs) {
  if (outputs.isEmpty) return DecodedScore.empty;
  final flat = _flattenToDoubles(outputs.first?.value);
  if (flat.isEmpty) return DecodedScore.empty;

  // NIMA — 10-bin probability distribution → MOS in [1, 10].
  if (flat.length == 10 && _isProbabilityDistribution(flat)) {
    var mos = 0.0;
    for (var i = 0; i < 10; i++) {
      mos += (i + 1) * flat[i];
    }
    return DecodedScore(
      quality: mos.clamp(0.0, 10.0),
      sharpness: 0,
      faceCount: 0,
      hasBlink: false,
    );
  }

  // Generic scalar fallback — MANIQA / MUSIQ / CLIP-IQA emit a single
  // sigmoid-style float in roughly [0, 1]. Scale onto the 0..10 axis.
  return DecodedScore(
    quality: (flat[0] * 10.0).clamp(0.0, 10.0),
    sharpness:
        flat.length > 1 ? (flat[1] * 10.0).clamp(0.0, 10.0) : 0.0,
    faceCount: flat.length > 2 ? flat[2].round() : 0,
    hasBlink: flat.length > 3 ? flat[3] > 0.5 : false,
  );
}

/// Heuristic — values all in `[0, 1]` summing close to 1.0 → softmax.
bool _isProbabilityDistribution(List<double> values) {
  var sum = 0.0;
  for (final x in values) {
    if (x < -0.001 || x > 1.001) return false;
    sum += x;
  }
  return (sum - 1.0).abs() < 0.05;
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
