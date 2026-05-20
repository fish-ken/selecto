import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

/// Cached analysis results keyed by Photo.cacheKey (path::mtime::size).
/// Survives app restarts so we don't re-run inference on unchanged files.
class CachedAnalyses extends Table {
  TextColumn get cacheKey => text()();
  TextColumn get path => text()();
  RealColumn get qualityScore => real()();
  RealColumn get sharpnessScore => real()();
  IntColumn get faceCount => integer()();
  BoolColumn get hasBlink => boolean()();
  DateTimeColumn get computedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {cacheKey};
}

@DriftDatabase(tables: [CachedAnalyses])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;

  Future<CachedAnalysis?> findByCacheKey(String key) {
    return (select(cachedAnalyses)..where((t) => t.cacheKey.equals(key)))
        .getSingleOrNull();
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
