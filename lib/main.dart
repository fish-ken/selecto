import 'package:flutter/material.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'app/app.dart';
import 'core/logging.dart';

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

  runApp(const ProviderScope(child: SelectoApp()));
}
