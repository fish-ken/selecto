import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

/// Cached analysis results keyed by (Photo.cacheKey, modelId).
/// Survives app restarts so we don't re-run inference on unchanged files.
/// The modelId column was added in schemaVersion 2; upgrading from v1 drops
/// and recreates the table (old single-key entries can't be reused anyway).
///
/// `@DataClassName` is required because Drift's default naming would turn
/// `CachedAnalyses` into `CachedAnalyse` (just stripping the trailing 's'),
/// which is grammatically wrong for the irregular plural "analyses".
@DataClassName('CachedAnalysis')
class CachedAnalyses extends Table {
  TextColumn get cacheKey => text()();

  /// Stable model identity (ModelConfig.id = asset path). Ensures results
  /// from one model aren't shown when a different model is selected.
  TextColumn get modelId => text()();

  TextColumn get path => text()();
  RealColumn get qualityScore => real()();
  RealColumn get sharpnessScore => real()();
  IntColumn get faceCount => integer()();
  BoolColumn get hasBlink => boolean()();
  DateTimeColumn get computedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {cacheKey, modelId};
}

@DriftDatabase(tables: [CachedAnalyses])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            // modelId was added to the primary key — drop and recreate.
            // Cached scores from v1 are lost; users re-run analysis once.
            await m.drop(cachedAnalyses);
            await m.createTable(cachedAnalyses);
          }
        },
      );

  Future<CachedAnalysis?> findByCacheKeyAndModel(
      String cacheKey, String modelId) {
    return (select(cachedAnalyses)
          ..where(
              (t) => t.cacheKey.equals(cacheKey) & t.modelId.equals(modelId)))
        .getSingleOrNull();
  }

  /// Returns all cached rows matching [cacheKeys] + [modelId].
  /// Queries are chunked in batches of 900 to stay within SQLite's
  /// default bound-variable limit (999).
  Future<List<CachedAnalysis>> findAllByModel(
      List<String> cacheKeys, String modelId) async {
    if (cacheKeys.isEmpty) return const [];
    const batchSize = 900;
    final result = <CachedAnalysis>[];
    for (var offset = 0; offset < cacheKeys.length; offset += batchSize) {
      final end = (offset + batchSize).clamp(0, cacheKeys.length);
      final batch = cacheKeys.sublist(offset, end);
      result.addAll(await (select(cachedAnalyses)
            ..where(
                (t) => t.cacheKey.isIn(batch) & t.modelId.equals(modelId)))
          .get());
    }
    return result;
  }

  Future<void> upsert(CachedAnalysesCompanion row) {
    return into(cachedAnalyses).insertOnConflictUpdate(row);
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationSupportDirectory();
    final file = File(p.join(dir.path, 'selecto.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
