import 'dart:io';

import 'package:path/path.dart' as p;

import '../../domain/entities/photo.dart';

/// Recursively walks a directory and emits [Photo]s for supported files.
/// Uses [Directory.list] with `followLinks: false` to avoid symlink cycles.
class DirectoryScanner {
  const DirectoryScanner();

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

    await for (final entity
        in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final ext = p.extension(entity.path).toLowerCase();
      if (!_supportedExts.contains(ext)) continue;

      final stat = await entity.stat();
      yield Photo(
        path: entity.path,
        byteSize: stat.size,
        modifiedAt: stat.modified,
      );
    }
  }
}
