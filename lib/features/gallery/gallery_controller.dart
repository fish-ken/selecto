import 'dart:async';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../app/providers.dart';
import '../../domain/entities/analysis_result.dart';
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
      selectionAnchor: 0,
      picked: const {},
      results: const {},
      scanning: true,
      clearError: true,
      // A new root invalidates any subfolder view from the previous one.
      clearSubfolderFilter: true,
      bestShotsOnly: false,
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
    if (state.visiblePhotos.isEmpty) return;
    final next =
        (state.selectedIndex + delta).clamp(0, state.visiblePhotos.length - 1);
    if (next == state.selectedIndex) return;
    // Arrow navigation carries the single selection with the cursor: the
    // photo moved onto becomes the sole selected item and the previous one
    // is deselected. Multi-select is built with Ctrl/Shift+click; a plain
    // arrow collapses back to a single selection.
    state = state.copyWith(
      selectedIndex: next,
      selectionAnchor: next,
      picked: {state.visiblePhotos[next].path},
    );
  }

  void setCursor(int index) {
    if (state.visiblePhotos.isEmpty) return;
    final next = index.clamp(0, state.visiblePhotos.length - 1);
    state = state.copyWith(selectedIndex: next);
  }

  /// Plain click — make [index] the sole selection and the cursor/anchor.
  void selectSingle(int index) {
    if (state.visiblePhotos.isEmpty) return;
    final i = index.clamp(0, state.visiblePhotos.length - 1);
    state = state.copyWith(
      selectedIndex: i,
      selectionAnchor: i,
      picked: {state.visiblePhotos[i].path},
    );
  }

  /// Ctrl/Cmd+click — toggle [index] in the selection; it becomes the anchor.
  void toggleSelectAt(int index) {
    if (state.visiblePhotos.isEmpty) return;
    final i = index.clamp(0, state.visiblePhotos.length - 1);
    final path = state.visiblePhotos[i].path;
    final picked = {...state.picked};
    if (!picked.add(path)) picked.remove(path);
    state = state.copyWith(
      selectedIndex: i,
      selectionAnchor: i,
      picked: picked,
    );
  }

  /// Shift+click — select the contiguous range from the anchor to [index]
  /// (replacing the selection). The anchor stays fixed so repeated
  /// shift-clicks re-range from the same start.
  void selectRangeTo(int index) {
    if (state.visiblePhotos.isEmpty) return;
    final i = index.clamp(0, state.visiblePhotos.length - 1);
    final anchor = state.selectionAnchor.clamp(0, state.visiblePhotos.length - 1);
    final lo = i < anchor ? i : anchor;
    final hi = i < anchor ? anchor : i;
    final range = <String>{
      for (var k = lo; k <= hi; k++) state.visiblePhotos[k].path,
    };
    state = state.copyWith(selectedIndex: i, picked: range);
  }

  /// Shift+Arrow — extend the contiguous range selection by [delta] from the
  /// fixed anchor (selection becomes anchor..newCursor; reversing shrinks it).
  /// The keyboard analogue of [selectRangeTo].
  void extendSelection(int delta) {
    if (state.visiblePhotos.isEmpty) return;
    final next =
        (state.selectedIndex + delta).clamp(0, state.visiblePhotos.length - 1);
    if (next == state.selectedIndex) return;
    selectRangeTo(next);
  }

  /// Ctrl/Cmd+Arrow — move the cursor by [delta] and add the newly focused
  /// photo to the selection, preserving everything already selected (a plain
  /// arrow would instead collapse to a single selection). The keyboard
  /// analogue of Ctrl+click building a multi-selection.
  void addCursorSelection(int delta) {
    if (state.visiblePhotos.isEmpty) return;
    final next =
        (state.selectedIndex + delta).clamp(0, state.visiblePhotos.length - 1);
    if (next == state.selectedIndex) return;
    state = state.copyWith(
      selectedIndex: next,
      selectionAnchor: next,
      picked: {...state.picked, state.visiblePhotos[next].path},
    );
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
      picked: state.visiblePhotos.map((p) => p.path).toSet(),
    );
  }

  void unpickAll() => state = state.copyWith(picked: const {});

  /// Switch the grid/viewer to show only photos whose immediate directory is
  /// [dir] (null = show all). A pure view change: it clears the selection so
  /// actions stay scoped to what's visible, but never touches
  /// [GalleryState.rootPath] or any photo's path — so the top-left folder
  /// label is unchanged and BestShots moves still act on each photo's real
  /// on-disk directory.
  ///
  /// The cursor is parked at -1 (no active tile) rather than 0 so the newly
  /// shown folder doesn't open with its first photo wearing the faint
  /// cursor border — nothing is focused until the user clicks or arrows in.
  void setSubfolderFilter(String? dir) {
    state = state.copyWith(
      subfolderFilter: dir,
      clearSubfolderFilter: dir == null,
      bestShotsOnly: false,
      selectedIndex: -1,
      selectionAnchor: 0,
      picked: const {},
    );
  }

  /// Show every photo inside any `BestShots` folder, across all subfolders.
  /// Like [setSubfolderFilter], a pure view change that clears the selection
  /// and parks the cursor; the top-left folder label and on-disk paths are
  /// untouched.
  void setBestShotsFilter() {
    state = state.copyWith(
      bestShotsOnly: true,
      clearSubfolderFilter: true,
      selectedIndex: -1,
      selectionAnchor: 0,
      picked: const {},
    );
  }

  /// Park the cursor on the first visible photo if it's currently unfocused
  /// (-1, e.g. right after a folder switch). Called when entering the viewer
  /// so it opens on a real photo instead of the clamped fallback.
  void ensureCursor() {
    if (state.selectedIndex >= 0 || state.visiblePhotos.isEmpty) return;
    state = state.copyWith(selectedIndex: 0, selectionAnchor: 0);
  }

  /// Auto-select the best shots from analysis results.
  /// Picks every photo whose qualityScore is at or above the
  /// `(1 - topPercentile)` quantile of the current run's scores.
  ///
  /// Replaces the current selection with exactly the best shots — the
  /// multi-selection is switched to the best set, discarding any picks the
  /// user had chosen by hand.
  void selectBest({double topPercentile = 0.2}) {
    final selector = ref.read(selectBestShotsProvider);
    final best = selector(
      photos: state.visiblePhotos,
      resultsByCacheKey: state.results,
      topPercentile: topPercentile,
    );
    state = state.copyWith(
      picked: best.map((p) => p.path).toSet(),
      selectionAnchor: 0,
    );
  }

  /// Move [paths] into a `BestShots` subfolder of their current directory
  /// (created if missing). Photos STAY in the gallery with their path
  /// updated in place; analysis results and picks are re-keyed to the new
  /// path. Photos already inside a BestShots folder are skipped. Returns
  /// the number actually moved.
  Future<int> moveToBestShots(Iterable<String> paths) =>
      _relocate(paths, toBestShots: true);

  /// Move [paths] out of their `BestShots` folder back up to the parent
  /// directory. Photos not inside a BestShots folder are skipped. Returns
  /// the number actually moved.
  Future<int> removeFromBestShots(Iterable<String> paths) =>
      _relocate(paths, toBestShots: false);

  Future<int> _relocate(
    Iterable<String> paths, {
    required bool toBestShots,
  }) async {
    final targets = paths.toSet();
    if (targets.isEmpty) return 0;
    final repo = ref.read(photoRepositoryProvider);

    final photos = [...state.photos];
    final results = {...state.results};
    final picked = {...state.picked};
    var moved = 0;
    Object? lastError;
    StackTrace? lastStack;

    for (var i = 0; i < photos.length; i++) {
      final photo = photos[i];
      if (!targets.contains(photo.path)) continue;
      // Skip no-ops — already in the desired location.
      if (isInBestShotsPath(photo.path) == toBestShots) continue;

      final dir = p.dirname(photo.path);
      final destDir = toBestShots ? p.join(dir, 'A-cut') : p.dirname(dir);
      try {
        final newPath = await repo.movePhoto(photo, destDir);
        final relocated = _withPath(photo, newPath);
        photos[i] = relocated;

        // Re-key the analysis result onto the new cacheKey so the score
        // badge follows the photo to its new location.
        final prev = results.remove(photo.cacheKey);
        if (prev != null) {
          results[relocated.cacheKey] = AnalysisResult(
            photoCacheKey: relocated.cacheKey,
            qualityScore: prev.qualityScore,
            sharpnessScore: prev.sharpnessScore,
            faceCount: prev.faceCount,
            hasBlink: prev.hasBlink,
            computedAt: prev.computedAt,
          );
        }
        // Keep any selection pointing at the moved file.
        if (picked.remove(photo.path)) picked.add(newPath);
        moved++;
      } catch (e, st) {
        _log.warning('relocate failed for ${photo.path}', e, st);
        lastError = e;
        lastStack = st;
      }
    }

    if (moved == 0) {
      if (lastError != null) {
        state = state.copyWith(error: lastError, errorStack: lastStack);
      }
      return 0;
    }
    state = state.copyWith(
      photos: List.unmodifiable(photos),
      results: Map.unmodifiable(results),
      picked: picked,
      error: lastError,
      errorStack: lastStack,
    );
    return moved;
  }

  Photo _withPath(Photo photo, String newPath) => Photo(
        path: newPath,
        byteSize: photo.byteSize,
        modifiedAt: photo.modifiedAt,
        width: photo.width,
        height: photo.height,
        previewPath: photo.previewPath,
      );
}
