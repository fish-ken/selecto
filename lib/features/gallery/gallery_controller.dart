import 'dart:async';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
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
    // When the user switches models, wipe in-memory results so the UI
    // doesn't show scores from the previous model and cancel any analysis
    // still streaming from the old model's isolate pool.
    ref.listen(selectedModelProvider, (prev, next) {
      if (prev == next) return;
      _analyzeSub?.cancel();
      state = state.copyWith(
        results: const {},
        analyzing: false,
      );
    });

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
        state = state.copyWith(scanning: false, error: e, errorStack: st);
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
    final analyze = ref.read(analyzePhotosProvider);
    await _analyzeSub?.cancel();
    state = state.copyWith(analyzing: true, clearError: true);

    final running = Map.of(state.results);
    final startCount = running.length;
    final totalRequested = state.photos.length;

    Object? streamError;
    _analyzeSub = analyze(state.photos).listen(
      (result) {
        running[result.photoCacheKey] = result;
        state = state.copyWith(results: Map.unmodifiable(running));
      },
      onError: (Object e, StackTrace st) {
        _log.warning('analysis stream errored', e, st);
        // Capture without flipping analyzing yet — onDone still fires
        // after the error event (we don't set cancelOnError).
        streamError = e;
        state = state.copyWith(error: e, errorStack: st);
      },
      cancelOnError: false,
      onDone: () {
        final newlyAnalyzed = running.length - startCount;
        // If the stream completed but yielded nothing AND no explicit
        // error came through, surface a generic hint so the user isn't
        // stuck staring at unchanged scores.
        if (newlyAnalyzed == 0 && totalRequested > 0 && streamError == null) {
          state = state.copyWith(
            analyzing: false,
            error: StateError(
              'Analysis produced 0 results for $totalRequested photos. '
              'Check the model input name / shape — see VS Code Debug Console '
              'for "inference failed" log lines.',
            ),
            errorStack: StackTrace.current,
          );
        } else {
          state = state.copyWith(analyzing: false);
        }
      },
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
    togglePickByPath(photo.path);
  }

  /// Toggle pick on a specific photo regardless of cursor position.
  /// Used by right-click handlers in the grid and filmstrip — the user
  /// can pick a photo without moving the keyboard cursor away from
  /// wherever it currently is.
  void togglePickByPath(String path) {
    final picked = {...state.picked};
    if (!picked.add(path)) picked.remove(path);
    state = state.copyWith(picked: picked);
  }

  void pickAll() {
    state = state.copyWith(
      picked: state.photos.map((p) => p.path).toSet(),
    );
  }

  void unpickAll() => state = state.copyWith(picked: const {});

  /// Auto-select the best shots from analysis results.
  /// Picks every photo whose qualityScore is at or above the
  /// `(1 - topPercentile)` quantile of the current run's scores.
  ///
  /// Existing picks are preserved — the selection is *added* to whatever
  /// the user has already chosen by hand. To start clean, call
  /// [unpickAll] first.
  void selectBest({double topPercentile = 0.2}) {
    final selector = ref.read(selectBestShotsProvider);
    final best = selector(
      photos: state.photos,
      resultsByCacheKey: state.results,
      topPercentile: topPercentile,
    );
    state = state.copyWith(
      picked: {...state.picked, ...best.map((p) => p.path)},
    );
  }

  /// Move every picked photo into a `BestShots` subfolder of the currently
  /// open directory (created if missing), then drop the moved photos from
  /// the in-memory gallery so they don't reappear under the new location.
  ///
  /// Returns the number of files actually moved. Per-file failures are
  /// logged and surfaced via [GalleryState.error]; the successfully moved
  /// files are still removed from state.
  Future<int> moveSelectedToBestShots() async {
    final root = state.rootPath;
    if (root == null || state.picked.isEmpty) return 0;

    final repo = ref.read(photoRepositoryProvider);
    final destDir = p.join(root, 'BestShots');

    final toMove =
        state.photos.where((ph) => state.picked.contains(ph.path)).toList();

    final movedPaths = <String>{};
    Object? lastError;
    StackTrace? lastStack;
    for (final photo in toMove) {
      try {
        await repo.movePhoto(photo, destDir);
        movedPaths.add(photo.path);
      } catch (e, st) {
        _log.warning('failed to move ${photo.path}', e, st);
        lastError = e;
        lastStack = st;
      }
    }

    if (movedPaths.isEmpty) {
      if (lastError != null) {
        state = state.copyWith(error: lastError, errorStack: lastStack);
      }
      return 0;
    }

    // Drop moved photos from the gallery and from the in-memory caches.
    final remaining =
        state.photos.where((ph) => !movedPaths.contains(ph.path)).toList();
    final movedKeys = {
      for (final ph in toMove)
        if (movedPaths.contains(ph.path)) ph.cacheKey,
    };
    final results = {...state.results}..removeWhere((k, _) => movedKeys.contains(k));
    final picked = {...state.picked}..removeAll(movedPaths);

    state = state.copyWith(
      photos: List.unmodifiable(remaining),
      picked: picked,
      results: Map.unmodifiable(results),
      selectedIndex: state.selectedIndex.clamp(
        0,
        remaining.isEmpty ? 0 : remaining.length - 1,
      ),
      // Report any partial failure, but keep the successful moves applied.
      error: lastError,
      errorStack: lastStack,
    );
    return movedPaths.length;
  }
}
