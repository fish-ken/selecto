/// Stable error taxonomy used across layers. Throw the concrete subtype;
/// boundary code wraps in [Result.err] so the UI can pattern-match.
sealed class Failure implements Exception {
  const Failure(this.message);
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

final class FileSystemFailure extends Failure {
  const FileSystemFailure(super.message);
}

final class DecodeFailure extends Failure {
  const DecodeFailure(super.message);
}

final class InferenceFailure extends Failure {
  const InferenceFailure(super.message);
}

final class CacheFailure extends Failure {
  const CacheFailure(super.message);
}
