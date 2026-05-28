import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Intents + shortcuts for the loupe/detail viewer. Mirrors the gallery
/// shortcut set but adds Esc-to-close (and Enter as a synonym for close,
/// matching the open/close symmetry users expect from Lightroom).

class MoveViewerIntent extends Intent {
  const MoveViewerIntent(this.delta);
  final int delta;
}

class TogglePickIntent extends Intent {
  const TogglePickIntent();
}

class CloseViewerIntent extends Intent {
  const CloseViewerIntent();
}

class ViewerShortcuts extends StatelessWidget {
  const ViewerShortcuts({
    super.key,
    required this.onMove,
    required this.onTogglePick,
    required this.onClose,
    required this.child,
  });

  final void Function(int delta) onMove;
  final VoidCallback onTogglePick;
  final VoidCallback onClose;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.arrowLeft): MoveViewerIntent(-1),
        SingleActivator(LogicalKeyboardKey.arrowRight): MoveViewerIntent(1),
        SingleActivator(LogicalKeyboardKey.space): TogglePickIntent(),
        SingleActivator(LogicalKeyboardKey.escape): CloseViewerIntent(),
        SingleActivator(LogicalKeyboardKey.enter): CloseViewerIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          MoveViewerIntent: CallbackAction<MoveViewerIntent>(
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
          CloseViewerIntent: CallbackAction<CloseViewerIntent>(
            onInvoke: (_) {
              onClose();
              return null;
            },
          ),
        },
        child: Focus(autofocus: true, child: child),
      ),
    );
  }
}
