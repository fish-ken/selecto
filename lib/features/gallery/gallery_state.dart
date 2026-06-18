import 'package:path/path.dart' as p;

import '../../domain/entities/analysis_result.dart';
import '../../domain/entities/photo.dart';

/// One row in the gallery's subfolder side panel: a directory that directly
/// contains photos, plus how many.
class SubfolderEntry {
  const SubfolderEntry({
    required this.dir,
    required this.label,
    required this.count,
  });

  /// Absolute directory path — the value stored in
  /// [GalleryState.subfolderFilter] when this row is selected.
  final String dir;

  /// Path relative to the gallery root, for display. The root directory
  /// itself shows its own folder name.
  final String label;

  /// Number of photos whose immediate directory is exactly [dir].
  final int count;
}

/// Immutable snapshot of the gallery for one render.
class GalleryState {
  const GalleryState({
    this.rootPath,
    this.photos = const [],
    this.visiblePhotos = const [],
    this.subfolders = const [],
    this.subfolderFilter,
    this.selectedIndex = 0,
    this.selectionAnchor = 0,
    this.picked = const {},
    this.results = const {},
    this.scanning = false,
    this.analyzing = false,
    this.error,
    this.errorStack,
  });

  final String? rootPath;

  /// Every scanned photo across all subfolders — the source of truth and
  /// the basis for BestShots moves (which always use each photo's real path).
  final List<Photo> photos;

  /// The photos actually shown in the grid/viewer: [photos] restricted to
  /// [subfolderFilter] (or all of them when the filter is null). Stored
  /// rather than computed on access so Riverpod `select`s get a stable
  /// reference and don't rebuild every frame.
  final List<Photo> visiblePhotos;

  /// Distinct photo-containing directories under the root, for the side
  /// panel. Derived from [photos]; empty when there's nothing to navigate.
  final List<SubfolderEntry> subfolders;

  /// When non-null, only photos whose immediate directory equals this path
  /// are visible. A pure view filter: it never changes [rootPath] or any
  /// photo's path, so the top-left folder label and BestShots moves
  /// (which act on `dirname(photo.path)`) are unaffected by it.
  final String? subfolderFilter;

  /// Index of the cursor photo, into [visiblePhotos].
  final int selectedIndex;

  /// Fixed anchor index for shift-range selection. Repeated shift-clicks
  /// re-range from this start point until a plain/ctrl click moves it.
  final int selectionAnchor;

  /// Paths of photos the user has explicitly picked (Space).
  final Set<String> picked;

  /// Analysis indexed by [Photo.cacheKey].
  final Map<String, AnalysisResult> results;

  final bool scanning;
  final bool analyzing;
  final Object? error;

  /// Optional stack trace paired with [error]. Used by the SnackBar
  /// "Copy Log" button to put a useful, paste-able report on the clipboard.
  final StackTrace? errorStack;

  Photo? get currentPhoto => visiblePhotos.isEmpty
      ? null
      : visiblePhotos[selectedIndex.clamp(0, visiblePhotos.length - 1)];

  GalleryState copyWith({
    String? rootPath,
    List<Photo>? photos,
    int? selectedIndex,
    int? selectionAnchor,
    Set<String>? picked,
    Map<String, AnalysisResult>? results,
    bool? scanning,
    bool? analyzing,
    Object? error,
    StackTrace? errorStack,
    bool clearError = false,
    String? subfolderFilter,
    bool clearSubfolderFilter = false,
  }) {
    final nextPhotos = photos ?? this.photos;
    final nextRoot = rootPath ?? this.rootPath;
    final nextFilter =
        clearSubfolderFilter ? null : (subfolderFilter ?? this.subfolderFilter);

    // Only recompute the derived lists when their inputs actually change —
    // a plain cursor/pick update shouldn't refilter thousands of photos.
    final photosChanged = photos != null;
    final filterChanged = nextFilter != this.subfolderFilter;
    final nextVisible = (photosChanged || filterChanged)
        ? _filterPhotos(nextPhotos, nextFilter)
        : visiblePhotos;
    final nextSubfolders = photosChanged
        ? _computeSubfolders(nextPhotos, nextRoot)
        : subfolders;

    return GalleryState(
      rootPath: nextRoot,
      photos: nextPhotos,
      visiblePhotos: nextVisible,
      subfolders: nextSubfolders,
      subfolderFilter: nextFilter,
      selectedIndex: selectedIndex ?? this.selectedIndex,
      selectionAnchor: selectionAnchor ?? this.selectionAnchor,
      picked: picked ?? this.picked,
      results: results ?? this.results,
      scanning: scanning ?? this.scanning,
      analyzing: analyzing ?? this.analyzing,
      error: clearError ? null : (error ?? this.error),
      errorStack: clearError ? null : (errorStack ?? this.errorStack),
    );
  }

  /// Photos whose immediate directory is [filter]. Returns [photos]
  /// unchanged (same reference) when there's no filter.
  static List<Photo> _filterPhotos(List<Photo> photos, String? filter) {
    if (filter == null) return photos;
    return List.unmodifiable([
      for (final ph in photos)
        if (p.dirname(ph.path) == filter) ph,
    ]);
  }

  /// Groups [photos] by their immediate directory, one [SubfolderEntry] per
  /// directory, sorted by display label.
  static List<SubfolderEntry> _computeSubfolders(
    List<Photo> photos,
    String? rootPath,
  ) {
    if (photos.isEmpty) return const [];
    final counts = <String, int>{};
    for (final ph in photos) {
      final dir = p.dirname(ph.path);
      counts[dir] = (counts[dir] ?? 0) + 1;
    }
    final entries = [
      for (final entry in counts.entries)
        SubfolderEntry(
          dir: entry.key,
          label: rootPath == null || entry.key == rootPath
              ? p.basename(entry.key)
              : p.relative(entry.key, from: rootPath),
          count: entry.value,
        ),
    ]..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    return List.unmodifiable(entries);
  }
}
