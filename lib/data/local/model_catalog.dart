import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

/// Discovers `.onnx` model files under `assets/models/`.
///
/// Uses the dev-mode convention that cwd is the project root and assets
/// live as plain files on disk. For packaged builds the loader would need
/// to switch to `rootBundle.load(...)` + an `AssetManifest` lookup; that's
/// a future concern — Selecto isn't shipping yet.
class ModelCatalog {
  const ModelCatalog({this.modelsDir = 'assets/models'});

  final String modelsDir;

  static final _log = Logger('ModelCatalog');

  /// Returns absolute (or cwd-relative) paths of every `.onnx` file in
  /// `modelsDir`, sorted by filename for stable UI ordering.
  Future<List<ModelEntry>> list() async {
    final dir = Directory(modelsDir);
    if (!await dir.exists()) {
      _log.warning('models directory missing: $modelsDir');
      return const [];
    }

    final entries = <ModelEntry>[];
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      if (p.extension(entity.path).toLowerCase() != '.onnx') continue;
      entries.add(
        ModelEntry(
          fileName: p.basename(entity.path),
          path: entity.path,
        ),
      );
    }
    entries.sort((a, b) => a.fileName.compareTo(b.fileName));
    return entries;
  }
}

class ModelEntry {
  const ModelEntry({required this.fileName, required this.path});

  /// File name only — used as the stable model identifier in cache keys
  /// and as the dropdown label.
  final String fileName;

  /// Full filesystem path passed to `OrtSession`.
  final String path;

  @override
  bool operator ==(Object other) =>
      other is ModelEntry && other.fileName == fileName;

  @override
  int get hashCode => fileName.hashCode;
}
