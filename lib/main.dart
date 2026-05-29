import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'app/app.dart';
import 'core/logging.dart';
import 'l10n/app_strings.dart';
import 'l10n/l10n.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  initLogging();

  // Default ImageCache caps at 100 entries / 100 MB, which thrashes hard
  // on multi-thousand-photo libraries: scrolling back and forth keeps
  // re-decoding the same thumbnails. Bump it aggressively for desktop
  // (plenty of RAM, single user).
  PaintingBinding.instance.imageCache
    ..maximumSize = 2000
    ..maximumSizeBytes = 512 * 1024 * 1024; // 512 MB

  await windowManager.ensureInitialized();
  await windowManager.setMinimumSize(const Size(960, 640));
  await windowManager.setTitle('Selecto');

  Future<AppStrings> load(String code) async {
    final raw = await rootBundle.loadString('assets/i18n/$code.json');
    return AppStrings(Map<String, String>.from(jsonDecode(raw) as Map));
  }

  final bundle = <AppLocale, AppStrings>{
    AppLocale.en: await load('en'),
    AppLocale.ko: await load('ko'),
  };

  runApp(
    ProviderScope(
      overrides: [stringsBundleProvider.overrideWithValue(bundle)],
      child: const SelectoApp(),
    ),
  );
}
