import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

import '../../domain/entities/photo.dart';

/// Recursively walks a directory and emits [Photo]s for supported files.
/// Uses [Directory.list] with `followLinks: false` to avoid symlink cycles.
///
/// On Windows, `recursive: true` will hit folders like
/// `System Volume Information` and throw `FileSystemException`. We swallow
/// per-entity errors via `handleError` so one bad folder doesn't kill the
/// whole scan.
class DirectoryScanner {
  const DirectoryScanner();

  static final _log = Logger('DirectoryScanner');

  static const _supportedExts = <String>{
    '.jpg',
    '.jpeg',
    '.png',
    '.heic',
    '.heif',
    '.webp',
    '.tif',
    '.tiff',
    '.bmp',
  };

  Stream<Photo> scan(String rootPath) async* {
    final root = Directory(rootPath);
    if (!await root.exists()) return;

    final entities = root
        .list(recursive: true, followLinks: false)
        .handleError(
          (Object e) => _log.fine('skip entry: $e'),
          test: (e) => e is FileSystemException,
        );

    await for (final entity in entities) {
      if (entity is! File) continue;
      final ext = p.extension(entity.path).toLowerCase();
      if (!_supportedExts.contains(ext)) continue;

      try {
        final stat = await entity.stat();
        yield Photo(
          path: entity.path,
          byteSize: stat.size,
          modifiedAt: stat.modified,
        );
      } on FileSystemException catch (e) {
        _log.fine('stat failed for ${entity.path}: $e');
      }
    }
  }
}
