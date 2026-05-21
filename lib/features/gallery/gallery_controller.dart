import 'dart:async';

import 'package:logging/logging.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../app/providers.dart';
import '../../domain/entities/photo.dart';
import 'gallery_state.dart';

part 'gallery_controller.g.dart';

@riverpod
class GalleryController extends _$GalleryController {
  final _log = Logger('GalleryController');
  StreamSubscription<void>? _scanSub;
  StreamSubscription<void>? _analyzeSub;

  @override
  GalleryState build() {
    ref.onDispose(() {
      _scanSub?.cancel();
      _analyzeSub?.cancel();
    });
    return const GalleryState();
  }

  Future<void> openDirectory(String rootPath) async {
    await _scanSub?.cancel();
    state = state.copyWith(
      rootPath: rootPath,
      photos: const [],
      selectedIndex: 0,
      picked: const {},
      results: const {},
      scanning: true,
      clearError: true,
    );

    final scan = ref.read(scanDirectoryProvider);
    final buffer = <Photo>[];

    _scanSub = scan(rootPath).listen(
      (photo) {
        buffer.add(photo);
        // Flush in batches so we don't rebuild on every single file.
        if (buffer.length % 32 == 0) {
          state = state.copyWith(photos: List.unmodifiable(buffer));
        }
      },
      onError: (Object e, StackTrace st) {
        _log.warning('scan failed', e, st);
        state = state.copyWith(scanning: false, error: e);
      },
      onDone: () {
        state = state.copyWith(
          photos: List.unmodifiable(buffer),
          scanning: false,
        );
      },
    );
  }

  Future<void> analyzeAll() async {
    if (state.photos.isEmpty || state.analyzing) return;
    await _analyzeSub?.cancel();
    state = state.copyWith(analyzing: true, clearError: true);

    final analyze = ref.read(analyzePhotosProvider);
    final running = Map.of(state.results);

    _analyzeSub = analyze(state.photos).listen(
      (result) {
        running[result.photoCacheKey] = result;
        state = state.copyWith(results: Map.unmodifiable(running));
      },
      onError: (Object e, StackTrace st) {
        _log.warning('analysis stream errored', e, st);
        state = state.copyWith(analyzing: false, error: e);
      },
      onDone: () => state = state.copyWith(analyzing: false),
    );
  }

  void moveCursor(int delta) {
    if (state.photos.isEmpty) return;
    final next = (state.selectedIndex + delta).clamp(0, state.photos.length - 1);
    if (next == state.selectedIndex) return;
    state = state.copyWith(selectedIndex: next);
  }

  void setCursor(int index) {
    if (state.photos.isEmpty) return;
    final next = index.clamp(0, state.photos.length - 1);
    state = state.copyWith(selectedIndex: next);
  }

  void togglePickCurrent() {
    final photo = state.currentPhoto;
    if (photo == null) return;
    final picked = {...state.picked};
    if (!picked.add(photo.path)) picked.remove(photo.path);
    state = state.copyWith(picked: picked);
  }

  void pickAll() {
    state = state.copyWith(
      picked: state.photos.map((p) => p.path).toSet(),
    );
  }

  void unpickAll() => state = state.copyWith(picked: const {});

  /// Auto-select the best shots from analysis results.
  void selectBest({int? topK, double minSharpness = 0.4}) {
    final selector = ref.read(selectBestShotsProvider);
    final best = selector(
      photos: state.photos,
      resultsByCacheKey: state.results,
      minSharpness: minSharpness,
      topK: topK,
    );
    state = state.copyWith(picked: best.map((p) => p.path).toSet());
  }
}
