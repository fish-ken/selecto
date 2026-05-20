import 'dart:isolate';

/// Wire format between the pool and its workers. Kept small + sendable.

class WorkerInit {
  const WorkerInit({
    required this.modelAssetPath,
    required this.replyPort,
  });
  final String modelAssetPath;
  final SendPort replyPort;
}

class InferenceRequest {
  const InferenceRequest({
    required this.id,
    required this.photoPath,
    required this.photoCacheKey,
  });
  final int id;
  final String photoPath;
  final String photoCacheKey;
}

sealed class WorkerMessage {
  const WorkerMessage();
}

class WorkerReady extends WorkerMessage {
  const WorkerReady(this.commandPort);
  final SendPort commandPort;
}

class InferenceSuccess extends WorkerMessage {
  const InferenceSuccess({
    required this.id,
    required this.photoCacheKey,
    required this.qualityScore,
    required this.sharpnessScore,
    required this.faceCount,
    required this.hasBlink,
  });
  final int id;
  final String photoCacheKey;
  final double qualityScore;
  final double sharpnessScore;
  final int faceCount;
  final bool hasBlink;
}

class InferenceError extends WorkerMessage {
  const InferenceError({required this.id, required this.error});
  final int id;
  final String error;
}
