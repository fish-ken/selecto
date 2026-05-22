import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../data/local/model_catalog.dart';

/// AppBar control that lists `.onnx` files in `assets/models/` and lets
/// the user switch the active model at runtime. Changing the selection
/// is handled by Riverpod — see [selectedModelProvider] in
/// `lib/app/providers.dart`.
class ModelPicker extends ConsumerWidget {
  const ModelPicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncModels = ref.watch(availableModelsProvider);
    final selected = ref.watch(selectedModelProvider);

    return asyncModels.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      error: (e, _) => IconButton(
        tooltip: 'Failed to load models: $e',
        icon: const Icon(Icons.error_outline),
        onPressed: () => ref.invalidate(availableModelsProvider),
      ),
      data: (models) {
        if (models.isEmpty) {
          return Tooltip(
            message: 'No .onnx files found in assets/models/',
            child: IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => ref.invalidate(availableModelsProvider),
            ),
          );
        }
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.memory, size: 18),
            const SizedBox(width: 6),
            PopupMenuButton<ModelEntry>(
              tooltip: 'Choose AI model',
              initialValue: selected,
              onSelected: (m) =>
                  ref.read(selectedModelProvider.notifier).select(m),
              itemBuilder: (_) => [
                for (final m in models)
                  PopupMenuItem<ModelEntry>(
                    value: m,
                    child: Row(
                      children: [
                        Icon(
                          selected?.fileName == m.fileName
                              ? Icons.check
                              : Icons.circle_outlined,
                          size: 14,
                        ),
                        const SizedBox(width: 8),
                        Text(m.fileName),
                      ],
                    ),
                  ),
                const PopupMenuDivider(),
                const PopupMenuItem<ModelEntry>(
                  enabled: false,
                  child: _RescanButton(),
                ),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 240),
                      child: Text(
                        selected?.fileName ?? 'No model',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Icon(Icons.arrow_drop_down),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _RescanButton extends ConsumerWidget {
  const _RescanButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TextButton.icon(
      icon: const Icon(Icons.refresh, size: 16),
      label: const Text('Rescan assets/models/'),
      onPressed: () {
        Navigator.of(context).pop();
        ref.invalidate(availableModelsProvider);
      },
    );
  }
}
