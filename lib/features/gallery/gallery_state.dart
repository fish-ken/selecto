import 'package:path/path.dart' as p;

import '../../domain/entities/analysis_result.dart';
import '../../domain/entities/photo.dart';
import 'similar_groups.dart';

/// One row in the gallery's subfolder side-panel tree.
class SubfolderEntry {
  const SubfolderEntry({
    required this.dir,
    required this.label,
    required this.depth,
    required this.count,
    required this.isBestShots,
  });

  /// Absolute directory path — the value stored in
  /// [GalleryState.subfolderFilter] when this row is selected.
  final String dir;

  /// Last path segment (display name). Parentage is shown via [depth], not
  /// in the label.
  final String label;

  /// Indentation level in the tree (0 = the shallowest directory shown).
  final int depth;

  /// Number of photos whose immediate directory is exactly [dir]. A count of
  /// 0 marks an intermediate ancestor included only to connect the tree —
  /// it's shown as a non-selectable header.
  final int count;

  /// Whether this directory is itself a `BestShots` folder (gets a star).
  final bool isBestShots;
}

/// Immutable snapshot of the gallery for one render.
class GalleryState {
  const GalleryState({
    this.rootPath,
    this.photos = const [],
    this.visiblePhotos = const [],
    this.subfolders = const [],
    this.subfolderFilter,
    this.bestShotsOnly = false,
    this.similarGroups = SimilarGroups.empty,
    this.groupFilter,
    this.grouping = false,
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

  /// When true, the view shows every photo inside any `BestShots` folder
  /// across all subfolders. Mutually exclusive with [subfolderFilter].
  final bool bestShotsOnly;

  /// Similar-photo clusters (`group-0`, …) from the last grouping pass.
  /// Empty until the user runs "group similar".
  final SimilarGroups similarGroups;

  /// When non-null, only photos in the group with this name are visible.
  /// Mutually exclusive with [subfolderFilter] / [bestShotsOnly].
  final String? groupFilter;

  /// True while the similarity pass is running (drives the AppBar spinner).
  final bool grouping;

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
    bool? bestShotsOnly,
    SimilarGroups? similarGroups,
    String? groupFilter,
    bool clearGroupFilter = false,
    bool? grouping,
  }) {
    final nextPhotos = photos ?? this.photos;
    final nextRoot = rootPath ?? this.rootPath;
    final nextFilter =
        clearSubfolderFilter ? null : (subfolderFilter ?? this.subfolderFilter);
    final nextBest = bestShotsOnly ?? this.bestShotsOnly;
    final nextGroups = similarGroups ?? this.similarGroups;
    final nextGroupFilter =
        clearGroupFilter ? null : (groupFilter ?? this.groupFilter);

    // Only recompute the derived lists when their inputs actually change —
    // a plain cursor/pick update shouldn't refilter thousands of photos.
    final photosChanged = photos != null;
    final modeChanged = nextFilter != this.subfolderFilter ||
        nextBest != this.bestShotsOnly ||
        nextGroupFilter != this.groupFilter ||
        !identical(nextGroups, this.similarGroups);
    final nextVisible = (photosChanged || modeChanged)
        ? _computeVisible(nextPhotos, nextFilter, nextBest, nextGroupFilter,
            nextGroups)
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
      bestShotsOnly: nextBest,
      similarGroups: nextGroups,
      groupFilter: nextGroupFilter,
      grouping: grouping ?? this.grouping,
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

  /// The visible subset for the current view mode. A group filter wins over
  /// [bestOnly] (every photo in any BestShots folder), which wins over
  /// [filter] (one exact directory); with none, returns [photos] unchanged.
  static List<Photo> _computeVisible(
    List<Photo> photos,
    String? filter,
    bool bestOnly,
    String? groupFilter,
    SimilarGroups groups,
  ) {
    if (groupFilter != null) {
      return List.unmodifiable([
        for (final ph in photos)
          if (groups.groupOf[ph.path] == groupFilter) ph,
      ]);
    }
    if (bestOnly) {
      return List.unmodifiable([
        for (final ph in photos)
          if (isInBestShotsPath(ph.path)) ph,
      ]);
    }
    if (filter == null) return photos;
    return List.unmodifiable([
      for (final ph in photos)
        if (p.dirname(ph.path) == filter) ph,
    ]);
  }

  /// Builds the side-panel tree: every directory that directly contains
  /// photos, plus the intermediate ancestors needed to show each one nested
  /// under its parent (so e.g. `jpg/BestShots` sits below `jpg`). Entries are
  /// in pre-order; [SubfolderEntry.depth] is normalized so the shallowest
  /// shown directory is at indent 0.
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

    // Photo directories + their ancestors strictly inside the root, so every
    // listed child has its parent listed above it.
    final dirs = <String>{...counts.keys};
    if (rootPath != null) {
      for (final d in counts.keys) {
        var parent = p.dirname(d);
        while (p.isWithin(rootPath, parent)) {
          dirs.add(parent);
          parent = p.dirname(parent);
        }
      }
    }

    List<String> segs(String dir) =>
        rootPath == null ? [dir] : p.split(p.relative(dir, from: rootPath));
    int rawDepth(String dir) =>
        rootPath != null && p.equals(dir, rootPath) ? 0 : segs(dir).length;

    final minDepth =
        dirs.map(rawDepth).fold<int>(1 << 30, (a, b) => a < b ? a : b);

    final ordered = dirs.toList()
      ..sort((a, b) {
        // Segment-by-segment compare → tree pre-order (parent before child,
        // each subtree contiguous) regardless of path separator.
        final sa = segs(a), sb = segs(b);
        for (var i = 0; i < sa.length && i < sb.length; i++) {
          final c = sa[i].toLowerCase().compareTo(sb[i].toLowerCase());
          if (c != 0) return c;
        }
        return sa.length - sb.length;
      });

    return List.unmodifiable([
      for (final dir in ordered)
        SubfolderEntry(
          dir: dir,
          label: p.basename(dir),
          depth: rawDepth(dir) - minDepth,
          count: counts[dir] ?? 0,
          isBestShots: p.basename(dir).toLowerCase() == 'a-cut',
        ),
    ]);
  }
}

/// True if [path]'s immediate parent directory is an `A-cut` folder
/// (the curated/best-shots folder; formerly named `BestShots`).
bool isInBestShotsPath(String path) =>
    p.basename(p.dirname(path)).toLowerCase() == 'a-cut';
