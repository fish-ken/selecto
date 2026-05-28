import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../ai/ai_service.dart';
import '../ai/onnx_ai_service.dart';
import '../data/local/app_database.dart';
import '../data/local/model_catalog.dart';
import '../data/repositories/ai_analysis_repository_impl.dart';
import '../data/repositories/photo_repository_impl.dart';
import '../domain/repositories/ai_analysis_repository.dart';
import '../domain/repositories/photo_repository.dart';
import '../domain/usecases/analyze_photos.dart';
import '../domain/usecases/scan_directory.dart';
import '../domain/usecases/select_best_shots.dart';

part 'providers.g.dart';

@Riverpod(keepAlive: true)
AppDatabase appDatabase(AppDatabaseRef ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
}

@Riverpod(keepAlive: true)
PhotoRepository photoRepository(PhotoRepositoryRef ref) {
  return PhotoRepositoryImpl();
}

@Riverpod(keepAlive: true)
ModelCatalog modelCatalog(ModelCatalogRef ref) => const ModelCatalog();

/// Discovered `.onnx` models. Loaded once at startup; call `ref.invalidate`
/// to force a rescan after the user drops new files into `assets/models/`.
@Riverpod(keepAlive: true)
Future<List<ModelEntry>> availableModels(AvailableModelsRef ref) {
  return ref.watch(modelCatalogProvider).list();
}

/// Currently active model. Changing this rebuilds [aiServiceProvider],
/// which disposes the old isolate pool and spawns a fresh one with the
/// new weights. Defaults to the first model found alphabetically.
@Riverpod(keepAlive: true)
class SelectedModel extends _$SelectedModel {
  @override
  ModelEntry? build() {
    final async = ref.watch(availableModelsProvider);
    return async.maybeWhen(
      data: (list) => list.isEmpty ? null : list.first,
      orElse: () => null,
    );
  }

  void select(ModelEntry model) => state = model;
}

/// Recreated whenever [selectedModelProvider] changes. The old service's
/// `dispose` runs via `ref.onDispose`, tearing down the isolate pool
/// before the new one spins up.
@Riverpod(keepAlive: true)
AiService? aiService(AiServiceRef ref) {
  final selected = ref.watch(selectedModelProvider);
  if (selected == null) return null;
  final service = OnnxAiService(modelPath: selected.path);
  ref.onDispose(service.dispose);
  return service;
}

@Riverpod(keepAlive: true)
AiAnalysisRepository? aiAnalysisRepository(AiAnalysisRepositoryRef ref) {
  final service = ref.watch(aiServiceProvider);
  if (service == null) return null;
  // Caching disabled — repository is a passthrough to the AI service.
  return AiAnalysisRepositoryImpl(service: service);
}

@riverpod
ScanDirectory scanDirectory(ScanDirectoryRef ref) =>
    ScanDirectory(ref.watch(photoRepositoryProvider));

@riverpod
AnalyzePhotos? analyzePhotos(AnalyzePhotosRef ref) {
  final repo = ref.watch(aiAnalysisRepositoryProvider);
  return repo == null ? null : AnalyzePhotos(repo);
}

@riverpod
SelectBestShots selectBestShots(SelectBestShotsRef ref) =>
    const SelectBestShots();
