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

      // Most quality scorers expose a single input. If yours uses a
      // different name, change 'input' to match the model's metadata.
      final outputs = session.run(runOptions, {'input': inputTensor});

      // Decode outputs defensively — different models expose different
      // heads. Adapt this once you know the exact graph.
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

_DecodedOutputs _decodeOutputs(List<OrtValue?> outputs) {
  // Default decoding assumes a single output tensor with one or more
  // floats in [quality, sharpness, face_prob, blink_prob] order.
  // Adjust to fit your real model.
  final first = outputs.first?.value;
  if (first is List && first.isNotEmpty) {
    final flat = _flatten(first).cast<num>();
    final values = flat.map((n) => n.toDouble()).toList(growable: false);
    return _DecodedOutputs(
      quality: values.isNotEmpty ? values[0].clamp(0.0, 1.0) : 0.0,
      sharpness: values.length > 1 ? values[1].clamp(0.0, 1.0) : 0.0,
      faceCount: values.length > 2 ? values[2].round() : 0,
      hasBlink: values.length > 3 ? values[3] > 0.5 : false,
    );
  }
  if (first is Float32List && first.isNotEmpty) {
    return _DecodedOutputs(
      quality: first[0].clamp(0.0, 1.0),
      sharpness: first.length > 1 ? first[1].clamp(0.0, 1.0) : 0.0,
      faceCount: first.length > 2 ? first[2].round() : 0,
      hasBlink: first.length > 3 ? first[3] > 0.5 : false,
    );
  }
  return const _DecodedOutputs(
    quality: 0,
    sharpness: 0,
    faceCount: 0,
    hasBlink: false,
  );
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
