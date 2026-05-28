import 'dart:io';
import 'dart:isolate';

import 'package:onnxruntime_v2/onnxruntime_v2.dart';
import 'package:path/path.dart' as p;

import 'isolate_messages.dart';
import 'output_decoder.dart';
import 'preprocessing.dart';

/// Entry point for each AI worker isolate. Spawned by `WorkerPool`.
///
/// Lifecycle:
///   1. Receive [WorkerInit] (model path + reply port).
///   2. Load the ONNX model. Pick the right [PreprocessConfig] by file
///      name. Auto-discover the model's input tensor name.
///   3. Send [WorkerReady] so the pool can start queueing requests.
///   4. Loop: pull [InferenceRequest]s from the command port,
///      run inference, reply with [InferenceSuccess] or [InferenceError].
///
/// CRITICAL invariant: [OrtSession] is NOT thread-safe. The session
/// belongs to this isolate for its entire life — never share it, never
/// move it.
Future<void> aiWorkerEntry(WorkerInit init) async {
  OrtEnv.instance.init();

  final modelBytes = await File(init.modelAssetPath).readAsBytes();
  final sessionOptions = OrtSessionOptions()..appendDefaultProviders();
  final session = OrtSession.fromBuffer(modelBytes, sessionOptions);

  // Auto-discover the model's input tensor name. Hard-coding `'input'`
  // was historically the #1 cause of silent inference failure across
  // model families (Keras uses `input_1`, PyTorch exports use `image`,
  // etc.) — always ask the graph.
  final inputName = session.inputNames.isNotEmpty
      ? session.inputNames.first
      : 'input';

  // Per-model preprocessing is selected by file name — see
  // [PreprocessConfig.forModelFileName] for the registry and its
  // extension recipe.
  final preprocessor = ImagePreprocessor(
    config: PreprocessConfig.forModelFileName(
      p.basename(init.modelAssetPath),
    ),
  );
  final runOptions = OrtRunOptions();

  final commands = ReceivePort();
  init.replyPort.send(WorkerReady(commands.sendPort));

  await for (final msg in commands) {
    if (msg is! InferenceRequest) continue;
    await _runOne(
      msg: msg,
      session: session,
      preprocessor: preprocessor,
      runOptions: runOptions,
      inputName: inputName,
      replyPort: init.replyPort,
    );
  }
}

/// Processes a single [InferenceRequest] and posts the result back.
/// Any exception is converted to an [InferenceError] so the pool can
/// surface it to the caller's stream.
Future<void> _runOne({
  required InferenceRequest msg,
  required OrtSession session,
  required ImagePreprocessor preprocessor,
  required OrtRunOptions runOptions,
  required String inputName,
  required SendPort replyPort,
}) async {
  try {
    final bytes = await File(msg.photoPath).readAsBytes();
    final pre = preprocessor.buildTensor(bytes);
    if (pre == null) {
      replyPort.send(InferenceError(id: msg.id, error: 'decode failed'));
      return;
    }

    final inputTensor =
        OrtValueTensor.createTensorWithDataList(pre.tensor, pre.shape);
    // Explicit type on the map prevents a generic-invariance error
    // (`Map<String, OrtValueTensor>` is not `Map<String, OrtValue>`).
    final inputs = <String, OrtValue>{inputName: inputTensor};
    final outputs = session.run(runOptions, inputs);

    final score = decodeScore(outputs);

    inputTensor.release();
    for (final o in outputs) {
      o?.release();
    }

    replyPort.send(
      InferenceSuccess(
        id: msg.id,
        photoCacheKey: msg.photoCacheKey,
        qualityScore: score.quality,
        sharpnessScore: score.sharpness,
        faceCount: score.faceCount,
        hasBlink: score.hasBlink,
      ),
    );
  } catch (e) {
    replyPort.send(InferenceError(id: msg.id, error: e.toString()));
  }
}
