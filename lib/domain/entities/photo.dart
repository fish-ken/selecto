/// A single photo on disk. Pure value object — no I/O, no Flutter deps.
/// Equality is by [path]; [pickedAt] / [analysis] are mutable metadata
/// kept off the entity (held by repositories / state instead).
class Photo {
  const Photo({
    required this.path,
    required this.byteSize,
    required this.modifiedAt,
    this.width,
    this.height,
  });

  final String path;
  final int byteSize;
  final DateTime modifiedAt;
  final int? width;
  final int? height;

  /// Cache key invariant across runs: same content => same key.
  /// (path, mtime, size) is a cheap proxy for content identity.
  String get cacheKey =>
      '$path::${modifiedAt.millisecondsSinceEpoch}::$byteSize';

  @override
  bool operator ==(Object other) => other is Photo && other.path == path;

  @override
  int get hashCode => path.hashCode;
}
