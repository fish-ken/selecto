import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:onnxruntime/onnxruntime.dart';

import 'isolate_messages.dart';
import 'preprocessing.dart';

/// Entry point for a worker isolate.
///
/// Lifecycle: receives [WorkerInit] → loads ONNX session → posts
/// [WorkerReady] with its command port → processes [InferenceRequest]s.
///
/// CRITICAL: `OrtSession` is NOT thread-safe. One session lives per
/// isolate for the worker's whole life; never shared, never moved.
Future<void> aiWorkerEntry(WorkerInit init) async {
  OrtEnv.instance.init();

  final modelBytes = await File(init.modelAssetPath).readAsBytes();
  final session = OrtSession.fromBuffer(
    modelBytes,
    OrtSessionOptions(),
  );

  // The hardcoded 'input' name was the #1 source of silent inference
  // failure — Keras-exported ONNX models use 'input_1', PyTorch exports
  // might use 'image', etc. Query the graph instead of guessing.
  final inputName = session.inputNames.isNotEmpty
      ? session.inputNames.first
      : 'input';

  const preprocessor = ImagePreprocessor();
  final runOptions = OrtRunOptions();

  final commands = ReceivePort();
  init.replyPort.send(WorkerReady(commands.sendPort));

  await for (final msg in commands) {
    if (msg is! InferenceRequest) continue;

    try {
      final bytes = await File(msg.photoPath).readAsBytes();
      final pre = preprocessor.buildTensor(bytes);
      if (pre == null) {
        init.replyPort.send(
          InferenceError(id: msg.id, error: 'decode failed'),
        );
        continue;
      }

      final inputTensor = OrtValueTensor.createTensorWithDataList(
        pre.tensor,
        pre.shape,
      );

      final inputs = <String, OrtValue>{inputName: inputTensor};
      final outputs = session.run(runOptions, inputs);

      final result = _decodeOutputs(outputs);

      inputTensor.release();
      for (final o in outputs) {
        o?.release();
      }

      init.replyPort.send(
        InferenceSuccess(
          id: msg.id,
          photoCacheKey: msg.photoCacheKey,
          qualityScore: result.quality,
          sharpnessScore: result.sharpness,
          faceCount: result.faceCount,
          hasBlink: result.hasBlink,
        ),
      );
    } catch (e) {
      init.replyPort.send(InferenceError(id: msg.id, error: e.toString()));
    }
  }
}

class _DecodedOutputs {
  const _DecodedOutputs({
    required this.quality,
    required this.sharpness,
    required this.faceCount,
    required this.hasBlink,
  });
  final double quality;
  final double sharpness;
  final int faceCount;
  final bool hasBlink;
}

/// Output decoder.
///
/// NIMA exposes a `[1, 10]` softmax distribution. We compute the mean
/// opinion score (MOS = Σ (i+1) · p_i, i = 0..9), which by construction
/// lies in [1, 10] and matches the NIMA paper's reporting scale.
///
/// Scores are stored on a **0..10 scale** in [AnalysisResult]. A score
/// of exactly 0 is reserved as a "not analyzed / decode failure" sentinel
/// — real NIMA outputs can't reach it.
///
/// For other models the fallback path treats the first scalar as
/// quality directly, clamped to [0, 10].
_DecodedOutputs _decodeOutputs(List<OrtValue?> outputs) {
  if (outputs.isEmpty) {
    return const _DecodedOutputs(
      quality: 0,
      sharpness: 0,
      faceCount: 0,
      hasBlink: false,
    );
  }
  final first = outputs.first?.value;
  final flat = _toDoubleList(first);
  if (flat.isEmpty) {
    return const _DecodedOutputs(
      quality: 0,
      sharpness: 0,
      faceCount: 0,
      hasBlink: false,
    );
  }

  // NIMA-style 10-bin probability distribution → MOS in [1, 10].
  if (flat.length == 10 && _isProbabilityDistribution(flat)) {
    var mos = 0.0;
    for (var i = 0; i < 10; i++) {
      mos += (i + 1) * flat[i];
    }
    return _DecodedOutputs(
      quality: mos.clamp(0.0, 10.0),
      sharpness: 0,
      faceCount: 0,
      hasBlink: false,
    );
  }

  // Generic fallback — first scalar is the quality, optional extras for
  // sharpness / face / blink. Useful when wiring a brand-new model.
  return _DecodedOutputs(
    quality: flat[0].clamp(0.0, 10.0),
    sharpness: flat.length > 1 ? flat[1].clamp(0.0, 10.0) : 0.0,
    faceCount: flat.length > 2 ? flat[2].round() : 0,
    hasBlink: flat.length > 3 ? flat[3] > 0.5 : false,
  );
}

List<double> _toDoubleList(Object? value) {
  if (value == null) return const [];
  if (value is Float32List) return value.toList(growable: false);
  if (value is List) {
    return _flatten(value)
        .whereType<num>()
        .map((n) => n.toDouble())
        .toList(growable: false);
  }
  return const [];
}

/// Heuristic — sums close to 1.0 with all non-negative values → softmax.
bool _isProbabilityDistribution(List<double> v) {
  var sum = 0.0;
  for (final x in v) {
    if (x < -0.001 || x > 1.001) return false;
    sum += x;
  }
  return (sum - 1.0).abs() < 0.05;
}

Iterable<Object?> _flatten(Object? value) sync* {
  if (value is Iterable) {
    for (final v in value) {
      yield* _flatten(v);
    }
  } else {
    yield value;
  }
}
