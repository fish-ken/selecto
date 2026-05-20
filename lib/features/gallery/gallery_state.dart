import '../../domain/entities/analysis_result.dart';
import '../../domain/entities/photo.dart';

/// Immutable snapshot of the gallery for one render.
class GalleryState {
  const GalleryState({
    this.rootPath,
    this.photos = const [],
    this.selectedIndex = 0,
    this.picked = const {},
    this.results = const {},
    this.scanning = false,
    this.analyzing = false,
    this.error,
  });

  final String? rootPath;
  final List<Photo> photos;

  /// Index of the photo with the keyboard cursor.
  final int selectedIndex;

  /// Paths of photos the user has explicitly picked (Space).
  final Set<String> picked;

  /// Analysis indexed by [Photo.cacheKey].
  final Map<String, AnalysisResult> results;

  final bool scanning;
  final bool analyzing;
  final Object? error;

  Photo? get currentPhoto =>
      photos.isEmpty ? null : photos[selectedIndex.clamp(0, photos.length - 1)];

  GalleryState copyWith({
    String? rootPath,
    List<Photo>? photos,
    int? selectedIndex,
    Set<String>? picked,
    Map<String, AnalysisResult>? results,
    bool? scanning,
    bool? analyzing,
    Object? error,
    bool clearError = false,
  }) {
    return GalleryState(
      rootPath: rootPath ?? this.rootPath,
      photos: photos ?? this.photos,
      selectedIndex: selectedIndex ?? this.selectedIndex,
      picked: picked ?? this.picked,
      results: results ?? this.results,
      scanning: scanning ?? this.scanning,
      analyzing: analyzing ?? this.analyzing,
      error: clearError ? null : (error ?? this.error),
    );
  }
}
