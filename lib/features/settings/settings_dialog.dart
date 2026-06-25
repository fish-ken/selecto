import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/local/preview_cache_manager.dart';
import '../../l10n/l10n.dart';

/// Settings dialog with a language selector, cache management, and credits.
class SettingsDialog extends ConsumerStatefulWidget {
  const SettingsDialog({super.key});

  /// Convenience launcher.
  static Future<void> show(BuildContext context) => showDialog(
        context: context,
        builder: (_) => const SettingsDialog(),
      );

  @override
  ConsumerState<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends ConsumerState<SettingsDialog> {
  bool _clearing = false;

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _clearCache() async {
    setState(() => _clearing = true);
    await PreviewCacheManager().clear();
    ref.invalidate(previewCacheSizeProvider);
    if (mounted) setState(() => _clearing = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(stringsProvider);
    final cacheAsync = ref.watch(previewCacheSizeProvider);

    return AlertDialog(
      title: Text(t.tr('settingsTitle')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Language row
          Row(
            children: [
              Text(t.tr('language')),
              const SizedBox(width: 16),
              DropdownMenu<AppLocale>(
                initialSelection: ref.watch(localeControllerProvider),
                onSelected: (l) {
                  if (l != null) {
                    ref.read(localeControllerProvider.notifier).set(l);
                  }
                },
                dropdownMenuEntries: [
                  for (final l in AppLocale.values)
                    DropdownMenuEntry<AppLocale>(
                      value: l,
                      label: l.label,
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Cache section
          Text(
            t.tr('cacheSection'),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.tr('previewCacheLabel')),
                    const SizedBox(height: 2),
                    cacheAsync.when(
                      data: (bytes) => Text(
                        _formatBytes(bytes),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                      loading: () => Text(
                        t.tr('cacheSizeCalculating'),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                      error: (_, __) => const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
              _clearing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : TextButton(
                      onPressed: cacheAsync.maybeWhen(
                        data: (bytes) => bytes > 0 ? _clearCache : null,
                        orElse: () => null,
                      ),
                      child: Text(t.tr('clearCache')),
                    ),
            ],
          ),
          const SizedBox(height: 24),
          // Credits section
          Text(
            t.tr('credits'),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          SelectableText(t.tr('creditsBody')),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t.tr('close')),
        ),
      ],
    );
  }
}
