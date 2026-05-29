import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/l10n.dart';
import '../gallery/gallery_controller.dart';
import '../gallery/modifier_keys.dart';
import 'widgets/filmstrip.dart';
import 'widgets/viewer_shortcuts.dart';

/// Lightroom-style detail / loupe view.
///
///   ┌─────────────────────────────────────────────┐
///   │                                             │
///   │             [ large photo ]                 │  ← BoxFit.contain
///   │                                             │     preserves AR
///   │                                             │
///   ├─────────────────────────────────────────────┤
///   │ [thumb] [thumb] [▣ thumb ▣] [thumb] [thumb] │  ← Filmstrip
///   └─────────────────────────────────────────────┘
///
/// Reads selection state from [galleryControllerProvider] so navigation
/// (←/→, filmstrip tap) stays in sync with the gallery underneath.
class ViewerScreen extends ConsumerWidget {
  const ViewerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(galleryControllerProvider);
    final ctrl = ref.read(galleryControllerProvider.notifier);
    final t = ref.watch(stringsProvider);

    void close() {
      // Use pop when possible (preserves underlying gallery state).
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/');
      }
    }

    final photo = state.currentPhoto;
    if (photo == null) {
      // No photos loaded — there's nothing to show; bounce back.
      WidgetsBinding.instance.addPostFrameCallback((_) => close());
      return const Scaffold(
        backgroundColor: Colors.black,
        body: SizedBox.shrink(),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: ViewerShortcuts(
        onMove: ctrl.moveCursor,
        onTogglePick: ctrl.togglePickCurrent,
        onClose: close,
        child: Column(
          children: [
            _TopBar(
              isPicked: state.picked.contains(photo.path),
              fileName: photo.path.split(RegExp(r'[\\/]')).last,
              onClose: close,
              closeTooltip: t.tr('viewerClose'),
              selectedLabel: t.tr('selected'),
              positionLabel: t.tr('viewerPosition', {
                'index': (state.selectedIndex + 1).toString(),
                'total': state.photos.length.toString(),
              }),
            ),
            Expanded(
              child: _ZoomableImage(
                // Key by path so the zoom resets when navigating photos.
                key: ValueKey(photo.decodablePath),
                imagePath: photo.decodablePath,
                // Right-click on the main image toggles pick on the
                // currently displayed photo (no need to leave the viewer).
                onSecondaryTap: () => ctrl.togglePickByPath(photo.path),
              ),
            ),
            SizedBox(
              height: 110,
              child: Filmstrip(
                photos: state.photos,
                selectedIndex: state.selectedIndex,
                picked: state.picked,
                resultsByCacheKey: state.results,
                onTap: (i) {
                  final mods = ref.read(modifierKeysProvider);
                  if (mods.shift) {
                    ctrl.selectRangeTo(i);
                  } else if (mods.toggleSelect) {
                    ctrl.toggleSelectAt(i);
                  } else {
                    ctrl.selectSingle(i);
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pan/zoom surface for the loupe image.
///
/// - **Double-click** toggles between fit-to-window (1×) and 200%, centered
///   on the cursor. A second double-click anywhere returns to 1×.
/// - **Ctrl + mouse wheel** zooms in/out around the pointer.
/// - When zoomed, drag to pan (handled by [InteractiveViewer]).
///
/// Closing the viewer stays on Esc/Enter (see [ViewerShortcuts]) — the
/// old double-click-to-close gesture is now the zoom toggle.
class _ZoomableImage extends StatefulWidget {
  const _ZoomableImage({
    super.key,
    required this.imagePath,
    required this.onSecondaryTap,
  });

  final String imagePath;
  final VoidCallback onSecondaryTap;

  @override
  State<_ZoomableImage> createState() => _ZoomableImageState();
}

class _ZoomableImageState extends State<_ZoomableImage>
    with SingleTickerProviderStateMixin {
  final _controller = TransformationController();
  // Drives the eased transitions for both double-tap and Ctrl+wheel zoom
  // so scale changes glide instead of snapping. Created in initState (not a
  // `late final` initializer): the lazy initializer would otherwise run on
  // first access, which — if the user never zoomed this photo — happens
  // inside dispose(). Building an AnimationController there calls
  // createTicker → TickerMode.of(context), an ancestor lookup that throws
  // once the element is deactivated.
  late final AnimationController _animController;
  Animation<Matrix4>? _animation;
  Offset? _lastTapPosition;

  static const double _minScale = 1.0;
  static const double _maxScale = 8.0;
  static const double _doubleTapScale = 2.0;
  static const _doubleTapDuration = Duration(milliseconds: 220);
  static const _wheelDuration = Duration(milliseconds: 120);

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: _doubleTapDuration,
    )..addListener(() {
        final anim = _animation;
        if (anim != null) _controller.value = anim.value;
      });
  }

  @override
  void dispose() {
    _animController.dispose();
    _controller.dispose();
    super.dispose();
  }

  double get _scale => _controller.value.getMaxScaleOnAxis();

  /// Eased tween from the current transform to [target]. Restarting mid-flight
  /// is fine — `begin` is read from wherever the matrix currently sits, so
  /// rapid wheel notches chase smoothly instead of jumping.
  void _animateTo(Matrix4 target, Duration duration) {
    _animation = Matrix4Tween(begin: _controller.value, end: target).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );
    _animController
      ..duration = duration
      ..reset()
      ..forward();
  }

  void _handleDoubleTap() {
    final Matrix4 target;
    if (_scale > _minScale + 0.01) {
      // Already zoomed — glide back to fit.
      target = Matrix4.identity();
    } else {
      // Zoom in to 200%, centered on the point the user clicked.
      final focal = _lastTapPosition;
      const z = _doubleTapScale;
      target = focal == null
          ? Matrix4.diagonal3Values(z, z, 1)
          // T(-focal·(z-1)) · S(z): scale up, then shift so the tapped
          // point stays put under the cursor.
          : (Matrix4.translationValues(
              -focal.dx * (z - 1), -focal.dy * (z - 1), 0)
            ..multiply(Matrix4.diagonal3Values(z, z, 1)));
    }
    _animateTo(target, _doubleTapDuration);
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    // Only zoom when Ctrl is held; otherwise let the scroll fall through.
    if (!HardwareKeyboard.instance.isControlPressed) return;

    final factor = event.scrollDelta.dy > 0 ? 0.85 : 1.15;
    final target = (_scale * factor).clamp(_minScale, _maxScale);
    final applied = target / _scale;
    if ((applied - 1.0).abs() < 1e-6) return;

    final focal = event.localPosition;
    // Scale around the pointer: T(focal) · S(applied) · T(-focal) · current.
    final zoom = Matrix4.translationValues(focal.dx, focal.dy, 0)
      ..multiply(Matrix4.diagonal3Values(applied, applied, 1))
      ..multiply(Matrix4.translationValues(-focal.dx, -focal.dy, 0));
    _animateTo(zoom * _controller.value, _wheelDuration);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: _handlePointerSignal,
      child: GestureDetector(
        onDoubleTapDown: (d) => _lastTapPosition = d.localPosition,
        onDoubleTap: _handleDoubleTap,
        onSecondaryTapDown: (_) => widget.onSecondaryTap(),
        child: InteractiveViewer(
          transformationController: _controller,
          minScale: _minScale,
          maxScale: _maxScale,
          // Keep the image edges within the viewport while panning.
          boundaryMargin: EdgeInsets.zero,
          // Scale is driven manually (double-tap + Ctrl+wheel) so the
          // built-in plain-scroll zoom doesn't fire on a bare mouse wheel.
          // Panning (drag when zoomed) stays enabled.
          scaleEnabled: false,
          // The child fills the whole pane so pointer coordinates map
          // 1:1 onto the transform space used by double-tap / Ctrl+wheel.
          child: SizedBox.expand(
            child: Image.file(
              File(widget.imagePath),
              // Preserve original aspect ratio; let Flutter scale
              // to fit the available pane.
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => const Center(
                child: Icon(
                  Icons.broken_image,
                  size: 64,
                  color: Colors.white54,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.isPicked,
    required this.fileName,
    required this.onClose,
    required this.closeTooltip,
    required this.selectedLabel,
    required this.positionLabel,
  });

  final bool isPicked;
  final String fileName;
  final VoidCallback onClose;
  final String closeTooltip;
  final String selectedLabel;
  final String positionLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          IconButton(
            tooltip: closeTooltip,
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: onClose,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              fileName,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70),
            ),
          ),
          if (isPicked) ...[
            const Icon(Icons.check_circle, color: Colors.tealAccent, size: 18),
            const SizedBox(width: 6),
            Text(selectedLabel,
                style: const TextStyle(color: Colors.tealAccent, fontSize: 12)),
            const SizedBox(width: 16),
          ],
          Text(
            positionLabel,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
