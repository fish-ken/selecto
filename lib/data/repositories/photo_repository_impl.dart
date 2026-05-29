import 'dart:io';

import 'package:path/path.dart' as p;

import '../../domain/entities/photo.dart';
import '../../domain/repositories/photo_repository.dart';
import '../local/directory_scanner.dart';

class PhotoRepositoryImpl implements PhotoRepository {
  PhotoRepositoryImpl({DirectoryScanner? scanner})
      : _scanner = scanner ?? DirectoryScanner();

  final DirectoryScanner _scanner;

  @override
  Stream<Photo> scanDirectory(String rootPath) => _scanner.scan(rootPath);

  @override
  Future<List<Photo>> listDirectory(String rootPath) =>
      _scanner.scan(rootPath).toList();

  @override
  Future<List<int>> readBytes(String path) => File(path).readAsBytes();

  @override
  Future<String> movePhoto(Photo photo, String destDir) async {
    await Directory(destDir).create(recursive: true);

    final source = File(photo.path);
    final base = p.basenameWithoutExtension(photo.path);
    final ext = p.extension(photo.path);

    // Resolve collisions: "name.jpg" → "name (1).jpg" → "name (2).jpg" …
    var dest = p.join(destDir, '$base$ext');
    var n = 1;
    while (await File(dest).exists() || await Directory(dest).exists()) {
      dest = p.join(destDir, '$base ($n)$ext');
      n++;
    }

    try {
      // Fast path: same volume → atomic rename.
      await source.rename(dest);
    } on FileSystemException {
      // Cross-volume move (rename can't span drives): copy then delete.
      await source.copy(dest);
      await source.delete();
    }
    return dest;
  }
}
