import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Intent + action plumbing for the gallery shortcuts. Using the
/// Shortcuts/Actions/Focus widgets (rather than RawKeyboardListener) so
/// the bindings respect focus traversal and survive platform input quirks.

class MoveCursorIntent extends Intent {
  const MoveCursorIntent(this.delta);
  final int delta;
}

class TogglePickIntent extends Intent {
  const TogglePickIntent();
}

class PickAllIntent extends Intent {
  const PickAllIntent();
}

class UnpickAllIntent extends Intent {
  const UnpickAllIntent();
}

class OpenViewerIntent extends Intent {
  const OpenViewerIntent();
}

class GalleryShortcuts extends StatelessWidget {
  const GalleryShortcuts({
    super.key,
    required this.crossAxisCount,
    required this.onMove,
    required this.onTogglePick,
    required this.onPickAll,
    required this.onUnpickAll,
    required this.onOpenViewer,
    required this.child,
  });

  final int crossAxisCount;
  final void Function(int delta) onMove;
  final VoidCallback onTogglePick;
  final VoidCallback onPickAll;
  final VoidCallback onUnpickAll;
  final VoidCallback onOpenViewer;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        const SingleActivator(LogicalKeyboardKey.arrowLeft):
            const MoveCursorIntent(-1),
        const SingleActivator(LogicalKeyboardKey.arrowRight):
            const MoveCursorIntent(1),
        SingleActivator(LogicalKeyboardKey.arrowUp): MoveCursorIntent(-crossAxisCount),
        SingleActivator(LogicalKeyboardKey.arrowDown): MoveCursorIntent(crossAxisCount),
        const SingleActivator(LogicalKeyboardKey.space): const TogglePickIntent(),
        const SingleActivator(LogicalKeyboardKey.enter): const OpenViewerIntent(),
        const SingleActivator(LogicalKeyboardKey.keyA, control: true): const PickAllIntent(),
        const SingleActivator(LogicalKeyboardKey.keyA, meta: true): const PickAllIntent(),
        const SingleActivator(LogicalKeyboardKey.keyD, control: true): const UnpickAllIntent(),
        const SingleActivator(LogicalKeyboardKey.keyD, meta: true): const UnpickAllIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          MoveCursorIntent: CallbackAction<MoveCursorIntent>(
            onInvoke: (intent) {
              onMove(intent.delta);
              return null;
            },
          ),
          TogglePickIntent: CallbackAction<TogglePickIntent>(
            onInvoke: (_) {
              onTogglePick();
              return null;
            },
          ),
          PickAllIntent: CallbackAction<PickAllIntent>(
            onInvoke: (_) {
              onPickAll();
              return null;
            },
          ),
          UnpickAllIntent: CallbackAction<UnpickAllIntent>(
            onInvoke: (_) {
              onUnpickAll();
              return null;
            },
          ),
          OpenViewerIntent: CallbackAction<OpenViewerIntent>(
            onInvoke: (_) {
              onOpenViewer();
              return null;
            },
          ),
        },
        child: Focus(autofocus: true, child: child),
      ),
    );
  }
}
