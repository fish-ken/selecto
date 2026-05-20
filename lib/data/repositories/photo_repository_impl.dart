import 'dart:io';

import '../../domain/entities/photo.dart';
import '../../domain/repositories/photo_repository.dart';
import '../local/directory_scanner.dart';

class PhotoRepositoryImpl implements PhotoRepository {
  PhotoRepositoryImpl({DirectoryScanner? scanner})
      : _scanner = scanner ?? const DirectoryScanner();

  final DirectoryScanner _scanner;

  @override
  Stream<Photo> scanDirectory(String rootPath) => _scanner.scan(rootPath);

  @override
  Future<List<Photo>> listDirectory(String rootPath) =>
      _scanner.scan(rootPath).toList();

  @override
  Future<List<int>> readBytes(String path) => File(path).readAsBytes();
}
