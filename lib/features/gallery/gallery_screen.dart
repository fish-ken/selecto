import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import 'gallery_controller.dart';
import 'gallery_state.dart';
import 'widgets/gallery_shortcuts.dart';
import 'widgets/model_picker.dart';
import 'widgets/photo_tile.dart';

class GalleryScreen extends ConsumerStatefulWidget {
  const GalleryScreen({super.key});

  @override
  ConsumerState<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends ConsumerState<GalleryScreen> {
  final _scrollCtrl = ScrollController();

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDirectory() async {
    final path = await FilePicker.platform.getDirectoryPath();
    if (path == null) return;
    await ref.read(galleryControllerProvider.notifier).openDirectory(path);
  }

  @override
  Widget build(BuildContext context) {
    // Surface errors raised by the gallery controller. Uses `ref.listen`,
    // not `ref.watch` — runs callback on change, doesn't rebuild.
    ref.listen<GalleryState>(galleryControllerProvider, (prev, next) {
      final err = next.error;
      if (err != null && err != prev?.error) {
        final messenger = ScaffoldMessenger.maybeOf(context);
        final stack = next.errorStack;
        messenger?.showSnackBar(
          SnackBar(
            backgroundColor: Theme.of(context).colorScheme.errorContainer,
            duration: const Duration(seconds: 8),
            content: Row(
              children: [
                Expanded(
                  child: Text(
                    'Error: $err',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                _SnackTextButton(
                  label: 'Copy Log',
                  onPressed: () => _copyErrorLog(
                    context: context,
                    messenger: messenger,
                    error: err,
                    stack: stack,
                  ),
                ),
                _SnackTextButton(
                  label: 'Dismiss',
                  onPressed: messenger.hideCurrentSnackBar,
                ),
              ],
            ),
          ),
        );
      }
    });

    return Scaffold(
      appBar: const _GalleryAppBar(),
      body: _GalleryBody(scrollCtrl: _scrollCtrl, onPickDirectory: _pickDirectory),
      bottomNavigationBar: const _StatusBar(),
    );
  }
}

/// AppBar isolated as its own ConsumerWidget so it only rebuilds when
/// the specific fields it shows actually change.
class _GalleryAppBar extends ConsumerWidget implements PreferredSizeWidget {
  const _GalleryAppBar();

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Narrow the watch to a record of just the fields we render.
    final s = ref.watch(galleryControllerProvider.select((s) => (
          rootPath: s.rootPath,
          hasPhotos: s.photos.isNotEmpty,
          analyzing: s.analyzing,
          hasResults: s.results.isNotEmpty,
        )));
    final hasModel = ref.watch(selectedModelProvider) != null;
    final ctrl = ref.read(galleryControllerProvider.notifier);

    return AppBar(
      title: Text(s.rootPath ?? 'Selecto'),
      actions: [
        const ModelPicker(),
        const SizedBox(width: 8),
        Builder(
          builder: (context) => IconButton(
            tooltip: 'Open folder',
            onPressed: () async {
              final path = await FilePicker.platform.getDirectoryPath();
              if (path == null) return;
              await ref
                  .read(galleryControllerProvider.notifier)
                  .openDirectory(path);
            },
            icon: const Icon(Icons.folder_open),
          ),
        ),
        IconButton(
          tooltip: hasModel ? 'Analyze' : 'No model selected',
          onPressed: !s.hasPhotos || s.analyzing || !hasModel
              ? null
              : ctrl.analyzeAll,
          icon: s.analyzing
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.auto_awesome),
        ),
        IconButton(
          tooltip: 'Select best shots (top 20%)',
          onPressed: !s.hasResults ? null : ctrl.selectBest,
          icon: const Icon(Icons.star),
        ),
      ],
    );
  }
}

/// Body — empty state vs. grid. Watches only what the body decision needs.
class _GalleryBody extends ConsumerWidget {
  const _GalleryBody({required this.scrollCtrl, required this.onPickDirectory});

  final ScrollController scrollCtrl;
  final VoidCallback onPickDirectory;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasPhotos = ref.watch(
      galleryControllerProvider.select((s) => s.photos.isNotEmpty),
    );

    if (!hasPhotos) {
      final scanning = ref.watch(
        galleryControllerProvider.select((s) => s.scanning),
      );
      return _EmptyState(scanning: scanning, onPick: onPickDirectory);
    }

    return _PhotoGrid(scrollCtrl: scrollCtrl);
  }
}

/// The actual grid. Watches `photos.length` for itemCount and ignores
/// everything else — per-tile data flows through fine-grained selectors
/// in the tile's own Consumer.
class _PhotoGrid extends ConsumerWidget {
  const _PhotoGrid({required this.scrollCtrl});

  final ScrollController scrollCtrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photosLength = ref.watch(
      galleryControllerProvider.select((s) => s.photos.length),
    );
    final ctrl = ref.read(galleryControllerProvider.notifier);

    final width = MediaQuery.sizeOf(context).width - 32;
    final crossAxisCount = (width / 200).floor().clamp(2, 12).toInt();
    final tileExtent = width / crossAxisCount;

    return GalleryShortcuts(
      crossAxisCount: crossAxisCount,
      onMove: ctrl.moveCursor,
      onTogglePick: ctrl.togglePickCurrent,
      onPickAll: ctrl.pickAll,
      onUnpickAll: ctrl.unpickAll,
      onOpenViewer: () => context.push('/viewer'),
      child: GridView.builder(
        controller: scrollCtrl,
        padding: const EdgeInsets.all(8),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          childAspectRatio: 1,
        ),
        itemCount: photosLength,
        addAutomaticKeepAlives: false,
        addRepaintBoundaries: true,
        itemBuilder: (context, i) {
          // Tile is its own Consumer — it watches only its own slice of
          // state (this photo's cursor/picked/analysis bits). State
          // changes that don't affect this index produce no rebuild.
          return _PhotoTileConnected(index: i, thumbExtent: tileExtent);
        },
      ),
    );
  }
}

/// Per-tile connector — subscribes only to the slices that actually
/// affect this single tile's visuals. The big win during analysis:
/// when `state.results` gets one new entry, only the tile whose
/// `photo.cacheKey` matches rebuilds. The other 49 visible tiles see
/// their selectors return identical values → no rebuild.
class _PhotoTileConnected extends ConsumerWidget {
  const _PhotoTileConnected({
    required this.index,
    required this.thumbExtent,
  });

  final int index;
  final double thumbExtent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photo = ref.watch(
      galleryControllerProvider.select(
        (s) => index < s.photos.length ? s.photos[index] : null,
      ),
    );
    if (photo == null) return const SizedBox.shrink();

    final isCursor = ref.watch(
      galleryControllerProvider.select((s) => s.selectedIndex == index),
    );
    final isPicked = ref.watch(
      galleryControllerProvider.select((s) => s.picked.contains(photo.path)),
    );
    final analysis = ref.watch(
      galleryControllerProvider.select((s) => s.results[photo.cacheKey]),
    );
    final ctrl = ref.read(galleryControllerProvider.notifier);

    return PhotoTile(
      photo: photo,
      thumbExtent: thumbExtent,
      isCursor: isCursor,
      isPicked: isPicked,
      analysis: analysis,
      onTap: () => ctrl.setCursor(index),
      onDoubleTap: () {
        ctrl.setCursor(index);
        context.push('/viewer');
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.scanning, required this.onPick});
  final bool scanning;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    if (scanning) {
      return const Center(child: CircularProgressIndicator());
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.photo_library_outlined, size: 64),
          const SizedBox(height: 16),
          const Text('No folder open'),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onPick,
            icon: const Icon(Icons.folder_open),
            label: const Text('Choose folder'),
          ),
        ],
      ),
    );
  }
}

/// Status bar isolated as its own ConsumerWidget. Counts update frequently
/// during analysis, but the bar is small and self-contained, so its
/// rebuild cost is negligible compared to the grid.
class _StatusBar extends ConsumerWidget {
  const _StatusBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(galleryControllerProvider.select((s) => (
          scanning: s.scanning,
          analyzing: s.analyzing,
          total: s.photos.length,
          picked: s.picked.length,
          analyzed: s.results.length,
        )));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          if (s.scanning) const Text('Scanning… ') else Text('${s.total} photos  '),
          Text('· ${s.picked} picked  '),
          if (s.analyzed > 0) Text('· ${s.analyzed} analyzed  '),
          if (s.analyzing) const Text('· inferring…'),
        ],
      ),
    );
  }
}

/// White, underlined text button used inside the error SnackBar's content
/// row. SnackBarAction can't carry styled labels, so we render TextButtons
/// inline and share their styling through this small helper.
class _SnackTextButton extends StatelessWidget {
  const _SnackTextButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          decoration: TextDecoration.underline,
          decorationColor: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Builds a paste-able log report and writes it to the system clipboard,
/// then shows a brief confirmation SnackBar so the user knows it worked.
Future<void> _copyErrorLog({
  required BuildContext context,
  required ScaffoldMessengerState? messenger,
  required Object error,
  required StackTrace? stack,
}) async {
  final buffer = StringBuffer()
    ..writeln('# Selecto — Error log')
    ..writeln('Timestamp: ${DateTime.now().toIso8601String()}')
    ..writeln()
    ..writeln('## Error')
    ..writeln(error.toString());
  if (stack != null) {
    buffer
      ..writeln()
      ..writeln('## Stack')
      ..writeln(stack.toString());
  }

  await Clipboard.setData(ClipboardData(text: buffer.toString()));

  messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: const Text('Error log copied to clipboard'),
        duration: const Duration(seconds: 2),
        backgroundColor: Theme.of(context).colorScheme.inverseSurface,
      ),
    );
}
