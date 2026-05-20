import '../entities/photo.dart';

/// Owns the photo set on disk. Implementations live in `data/`.
abstract interface class PhotoRepository {
  /// Recursively scan [rootPath] and yield photos as they are found.
  /// Streamed so the UI can render the grid incrementally without
  /// blocking on huge directories.
  Stream<Photo> scanDirectory(String rootPath);

  /// One-shot variant for small dirs or tests.
  Future<List<Photo>> listDirectory(String rootPath);

  /// Read raw bytes (used by AI preprocessing inside an isolate).
  Future<List<int>> readBytes(String path);
}
