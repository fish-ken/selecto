/// Tiny Result<T> for repository / use-case boundaries.
/// Keeps error-handling explicit at layer seams; lower layers throw,
/// boundary code wraps with [Result.guard] or [Result.guardAsync].
sealed class Result<T> {
  const Result();

  static Result<T> ok<T>(T value) => Ok<T>(value);
  static Result<T> err<T>(Object error, [StackTrace? stackTrace]) =>
      Err<T>(error, stackTrace);

  static Result<T> guard<T>(T Function() body) {
    try {
      return Ok<T>(body());
    } catch (e, st) {
      return Err<T>(e, st);
    }
  }

  static Future<Result<T>> guardAsync<T>(Future<T> Function() body) async {
    try {
      return Ok<T>(await body());
    } catch (e, st) {
      return Err<T>(e, st);
    }
  }

  bool get isOk => this is Ok<T>;
  bool get isErr => this is Err<T>;

  T? get valueOrNull => switch (this) {
        Ok<T>(:final value) => value,
        Err<T>() => null,
      };

  R fold<R>({
    required R Function(T value) ok,
    required R Function(Object error, StackTrace? st) err,
  }) {
    final self = this;
    return switch (self) {
      Ok<T>(:final value) => ok(value),
      Err<T>(:final error, :final stackTrace) => err(error, stackTrace),
    };
  }
}

final class Ok<T> extends Result<T> {
  const Ok(this.value);
  final T value;
}

final class Err<T> extends Result<T> {
  const Err(this.error, [this.stackTrace]);
  final Object error;
  final StackTrace? stackTrace;
}
