import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    // Surface errors raised by the gallery controller (scan failure,
    // inference crash, missing model, etc.). Without this they'd only
    // hit the log file and the user would see nothing change.
    ref.listen<GalleryState>(galleryControllerProvider, (prev, next) {
      final err = next.error;
      if (err != null && err != prev?.error) {
        final messenger = ScaffoldMessenger.maybeOf(context);
        messenger?.showSnackBar(
          SnackBar(
            content: Text('Error: $err'),
            backgroundColor: Theme.of(context).colorScheme.errorContainer,
            duration: const Duration(seconds: 8),
            action: SnackBarAction(
              label: 'Dismiss',
              onPressed: messenger.hideCurrentSnackBar,
            ),
          ),
        );
      }
    });

    final state = ref.watch(galleryControllerProvider);
    final ctrl = ref.read(galleryControllerProvider.notifier);

    // Choose grid breakpoints based on window width. 200px target tile.
    final width = MediaQuery.sizeOf(context).width - 32;
    final crossAxisCount = (width / 200).floor().clamp(2, 12).toInt();
    final tileExtent = width / crossAxisCount;

    final hasModel = ref.watch(selectedModelProvider) != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(state.rootPath ?? 'Selecto'),
        actions: [
          const ModelPicker(),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Open folder',
            onPressed: _pickDirectory,
            icon: const Icon(Icons.folder_open),
          ),
          IconButton(
            tooltip: hasModel ? 'Analyze' : 'No model selected',
            onPressed: state.photos.isEmpty || state.analyzing || !hasModel
                ? null
                : ctrl.analyzeAll,
            icon: state.analyzing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome),
          ),
          IconButton(
            tooltip: 'Select best shots',
            onPressed: state.results.isEmpty
                ? null
                : () => ctrl.selectBest(topK: 25),
            icon: const Icon(Icons.star),
          ),
        ],
      ),
      body: state.photos.isEmpty
          ? _EmptyState(scanning: state.scanning, onPick: _pickDirectory)
          : GalleryShortcuts(
              crossAxisCount: crossAxisCount,
              onMove: ctrl.moveCursor,
              onTogglePick: ctrl.togglePickCurrent,
              onPickAll: ctrl.pickAll,
              onUnpickAll: ctrl.unpickAll,
              onOpenViewer: () {
                // TODO: push full-screen viewer route
              },
              child: GridView.builder(
                controller: _scrollCtrl,
                padding: const EdgeInsets.all(8),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  childAspectRatio: 1,
                ),
                itemCount: state.photos.length,
                // addAutomaticKeepAlives:false → don't keep off-screen tiles alive.
                addAutomaticKeepAlives: false,
                addRepaintBoundaries: true,
                itemBuilder: (context, i) {
                  final photo = state.photos[i];
                  return PhotoTile(
                    photo: photo,
                    thumbExtent: tileExtent,
                    isCursor: i == state.selectedIndex,
                    isPicked: state.picked.contains(photo.path),
                    analysis: state.results[photo.cacheKey],
                    onTap: () => ctrl.setCursor(i),
                  );
                },
              ),
            ),
      bottomNavigationBar: _StatusBar(
        scanning: state.scanning,
        analyzing: state.analyzing,
        total: state.photos.length,
        picked: state.picked.length,
        analyzed: state.results.length,
      ),
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

class _StatusBar extends StatelessWidget {
  const _StatusBar({
    required this.scanning,
    required this.analyzing,
    required this.total,
    required this.picked,
    required this.analyzed,
  });
  final bool scanning;
  final bool analyzing;
  final int total;
  final int picked;
  final int analyzed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          if (scanning) const Text('Scanning… ') else Text('$total photos  '),
          Text('· $picked picked  '),
          if (analyzed > 0) Text('· $analyzed analyzed  '),
          if (analyzing) const Text('· inferring…'),
        ],
      ),
    );
  }
}
