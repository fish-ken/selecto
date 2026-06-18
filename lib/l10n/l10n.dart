import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_strings.dart';

/// Supported UI languages.
enum AppLocale {
  en('English', Locale('en')),
  ko('한국어', Locale('ko')),
  zh('简体中文', Locale('zh')),
  ja('日本語', Locale('ja'));

  const AppLocale(this.label, this.locale);
  final String label;
  final Locale locale;

  /// The [AppLocale] for an OS language code, or [en] when unsupported.
  static AppLocale forLanguageCode(String code) {
    for (final l in values) {
      if (l.locale.languageCode == code) return l;
    }
    return en;
  }
}

/// Loaded string bundles, seeded in `main()` via override.
final stringsBundleProvider = Provider<Map<AppLocale, AppStrings>>(
  (ref) => throw UnimplementedError('override stringsBundleProvider in main()'),
);

/// The active language. Defaults to the OS language when supported.
class LocaleController extends Notifier<AppLocale> {
  @override
  AppLocale build() {
    final code = PlatformDispatcher.instance.locale.languageCode;
    return AppLocale.forLanguageCode(code);
  }

  void set(AppLocale locale) => state = locale;
}

final localeControllerProvider =
    NotifierProvider<LocaleController, AppLocale>(LocaleController.new);

/// The string table for the active language. Watch this in widgets:
/// `final t = ref.watch(stringsProvider); ... t.tr('analyze')`.
final stringsProvider = Provider<AppStrings>((ref) {
  final bundle = ref.watch(stringsBundleProvider);
  final locale = ref.watch(localeControllerProvider);
  return bundle[locale]!;
});
