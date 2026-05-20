import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../ai/ai_service.dart';
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

@Riverpod(keepAlive: true)
AiService aiService(AiServiceRef ref) {
  // Asset path resolution: in dev, assets/ is rooted at the app bundle.
  // For desktop, we resolve relative to the executable's data dir at
  // runtime (see main.dart). This provider just holds the configured path.
  final service = OnnxAiService(
    modelPath: p.join('assets', 'models', 'quality.onnx'),
  );
  ref.onDispose(service.dispose);
  return service;
}

@Riverpod(keepAlive: true)
AiAnalysisRepository aiAnalysisRepository(AiAnalysisRepositoryRef ref) {
  return AiAnalysisRepositoryImpl(
    service: ref.watch(aiServiceProvider),
    db: ref.watch(appDatabaseProvider),
  );
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
