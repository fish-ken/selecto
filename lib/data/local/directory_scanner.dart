import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

import '../../domain/entities/photo.dart';
import 'raw_preview_cache.dart';

/// Recursively walks a directory and emits [Photo]s for supported files.
/// Uses [Directory.list] with `followLinks: false` to avoid symlink cycles.
///
/// On Windows, `recursive: true` will hit folders like
/// `System Volume Information` and throw `FileSystemException`. We swallow
/// per-entity errors via `handleError` so one bad folder doesn't kill the
/// whole scan.
///
/// RAW files (.NEF / .CR2 / .ARW / …) are routed through
/// [RawPreviewCache] which extracts their embedded JPEG preview with a
/// built-in pure-Dart scanner. Only when that fails (no embedded
/// preview, corrupt file) is the RAW skipped silently — see the log file.
class DirectoryScanner {
  DirectoryScanner({RawPreviewCache? rawCache})
      : _rawCache = rawCache ?? RawPreviewCache();

  final RawPreviewCache _rawCache;

  static final _log = Logger('DirectoryScanner');

  static const _decodableExts = <String>{
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
      final isDecodable = _decodableExts.contains(ext);
      final isRaw = RawPreviewCache.isRaw(entity.path);
      if (!isDecodable && !isRaw) continue;

      final FileStat stat;
      try {
        stat = await entity.stat();
      } on FileSystemException catch (e) {
        _log.fine('stat failed for ${entity.path}: $e');
        continue;
      }

      String? previewPath;
      if (isRaw) {
        previewPath = await _rawCache.extractPreview(
          entity,
          mtime: stat.modified,
          size: stat.size,
        );
        // Couldn't extract a preview → skip rather than yield a Photo
        // that grid/AI can't actually decode.
        if (previewPath == null) continue;
      }

      yield Photo(
        path: entity.path,
        byteSize: stat.size,
        modifiedAt: stat.modified,
        previewPath: previewPath,
      );
    }
  }
}
