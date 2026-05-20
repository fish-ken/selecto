import '../entities/photo.dart';
import '../repositories/photo_repository.dart';

class ScanDirectory {
  const ScanDirectory(this._repo);
  final PhotoRepository _repo;

  Stream<Photo> call(String rootPath) => _repo.scanDirectory(rootPath);
}
