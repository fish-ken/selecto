import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
        final stack = next.errorStack;
        messenger?.showSnackBar(
          SnackBar(
            backgroundColor: Theme.of(context).colorScheme.errorContainer,
            duration: const Duration(seconds: 8),
            // `SnackBarAction.label` is a plain String — no way to add
            // underline through its API. Embed the dismiss button into
            // `content` so we control colour + decoration directly.
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
            tooltip: 'Select best shots (top 20%)',
            onPressed: state.results.isEmpty
                ? null
                : ctrl.selectBest,
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
