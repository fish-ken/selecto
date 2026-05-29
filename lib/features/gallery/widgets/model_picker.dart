import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ai/model_configs/model_configs.dart';
import '../../../app/providers.dart';
import '../../../l10n/l10n.dart';

/// AppBar control that lists the bundled models (see [kModelConfigs]) by
/// their display [ModelConfig.name] and lets the user switch the active
/// model at runtime. Selection is handled by Riverpod — see
/// [selectedModelProvider] in `lib/app/providers.dart`.
class ModelPicker extends ConsumerWidget {
  const ModelPicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final models = ref.watch(availableModelsProvider);
    final selected = ref.watch(selectedModelProvider);
    final t = ref.watch(stringsProvider);

    if (models.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Tooltip(
          message: t.tr('noModelsConfigured'),
          child: const Icon(Icons.error_outline),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.memory, size: 18),
        const SizedBox(width: 6),
        PopupMenuButton<ModelConfig>(
          tooltip: t.tr('chooseModel'),
          initialValue: selected,
          onSelected: (m) =>
              ref.read(selectedModelProvider.notifier).select(m),
          itemBuilder: (_) => [
            for (final m in models)
              PopupMenuItem<ModelConfig>(
                value: m,
                child: Row(
                  children: [
                    Icon(
                      selected.id == m.id
                          ? Icons.check
                          : Icons.circle_outlined,
                      size: 14,
                    ),
                    const SizedBox(width: 8),
                    Text(m.name),
                  ],
                ),
              ),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 240),
                  child: Text(
                    selected.name,
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
  }
}
