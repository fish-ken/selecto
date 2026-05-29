import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../ai/ai_service.dart';
import '../ai/model_configs/model_configs.dart';
import '../ai/onnx_ai_service.dart';
import '../data/local/app_database.dart';
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

/// The fixed registry of bundled models — see [kModelConfigs] in
/// `lib/ai/model_config.dart`. Each entry is a `ModelConfig` subclass that
/// owns its own preprocessing + output decoding. No disk scanning.
@Riverpod(keepAlive: true)
List<ModelConfig> availableModels(AvailableModelsRef ref) => kModelConfigs;

/// Currently active model. Changing this rebuilds [aiServiceProvider],
/// which disposes the old isolate pool and spawns a fresh one with the
/// new weights. Defaults to the first entry in [kModelConfigs].
@Riverpod(keepAlive: true)
class SelectedModel extends _$SelectedModel {
  @override
  ModelConfig build() => ref.watch(availableModelsProvider).first;

  void select(ModelConfig model) => state = model;
}

/// Recreated whenever [selectedModelProvider] changes. The old service's
/// `dispose` runs via `ref.onDispose`, tearing down the isolate pool
/// before the new one spins up.
@Riverpod(keepAlive: true)
AiService aiService(AiServiceRef ref) {
  final selected = ref.watch(selectedModelProvider);
  final service = OnnxAiService(model: selected);
  ref.onDispose(service.dispose);
  return service;
}

@Riverpod(keepAlive: true)
AiAnalysisRepository aiAnalysisRepository(AiAnalysisRepositoryRef ref) {
  final service = ref.watch(aiServiceProvider);
  // Caching disabled — repository is a passthrough to the AI service.
  return AiAnalysisRepositoryImpl(service: service);
}

@riverpod
ScanDirectory scanDirectory(ScanDirectoryRef ref) =>
    ScanDirectory(ref.watch(photoRepositoryProvider));

@riverpod
AnalyzePhotos analyzePhotos(AnalyzePhotosRef ref) =>
    AnalyzePhotos(ref.watch(aiAnalysisRepositoryProvider));

@riverpod
SelectBestShots selectBestShots(SelectBestShotsRef ref) =>
    const SelectBestShots();
