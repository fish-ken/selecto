# Selecto

AI-powered photo culling/selection desktop app for Windows, macOS, and Linux.
Built with Flutter, Riverpod, and ONNX Runtime (via `dart:ffi`).

## Architecture

Clean Architecture with strict layer boundaries. The UI never touches FFI directly.

```
lib/
├── app/            App shell, theming, router
├── core/           Cross-cutting utilities (logging, result types, errors)
├── domain/         Pure Dart: entities, repository interfaces, use cases
├── data/           Repository impls, Drift DB, local file scanner
├── ai/             ONNX service facade, isolate worker pool, preprocessing
└── features/
    └── gallery/    Virtualized photo grid + keyboard shortcuts
```

Dependency direction: `features` → `domain` ← `data` / `ai`.
`domain` depends on nothing.

## Prerequisites

- **Flutter SDK 3.22+** — https://docs.flutter.dev/get-started/install
- **Windows**: Visual Studio with the "Desktop development with C++" workload
- **macOS**: Xcode 14+ with command-line tools
- **Linux**: `clang`, `cmake`, `ninja-build`, `pkg-config`, `libgtk-3-dev`

Verify with:

```pwsh
flutter doctor
```

All checks for your target platform must be green.

## First-time setup

Run **in this order** on a fresh clone:

```pwsh
# 1) Create the per-platform native folders (windows/, macos/, linux/)
flutter create --platforms=windows,macos,linux --org=com.fish-ken .

# 2) Resolve Dart/Flutter dependencies
flutter pub get

# 3) Generate codegen output (Riverpod, Drift, Freezed, JSON)
dart run build_runner build --delete-conflicting-outputs
```

Step 3 is **mandatory** — without it the project won't compile because
`providers.dart`, `gallery_controller.dart`, and `app_database.dart` all import
`*.g.dart` files that only exist after `build_runner` runs.

Then drop your ONNX model into `assets/models/quality.onnx`. The grid UI works
without it, but the "Analyze" button will fail until the file is present.

## Running

### Debug (default — hot reload, slow)

```pwsh
flutter run -d windows      # or: macos, linux
```

Press `r` for hot-reload, `R` for hot-restart, `q` to quit. Use `--device-id`
to pick a specific device if you have several:

```pwsh
flutter devices
flutter run -d "Windows (desktop)"
```

### Profile mode (release-ish perf, devtools attached)

Use this when measuring frame times or AI throughput — debug mode is
artificially slow because every line is JIT-checked.

```pwsh
flutter run -d windows --profile
```

### Release mode (compiled AOT, no devtools)

```pwsh
flutter run -d windows --release
```

### Codegen watcher (run in a second terminal during dev)

Keep this open while editing `@riverpod` / `@freezed` / Drift files so
`*.g.dart` regenerates on every save:

```pwsh
dart run build_runner watch --delete-conflicting-outputs
```

## Testing

```pwsh
# All tests
flutter test

# Single file
flutter test test/domain/select_best_shots_test.dart

# Single test by name (matches the string in `test('...', ...)`)
flutter test --plain-name "drops blinks and low-sharpness"

# With coverage (output: coverage/lcov.info)
flutter test --coverage
```

### Static analysis

```pwsh
flutter analyze            # Dart analyzer + lint rules from analysis_options.yaml
dart run custom_lint       # Riverpod-specific lints (provider misuse, scope leaks)
```

## Release builds

The build outputs are unsigned. Code signing / notarization / installer
packaging is **not** wired up yet — see "Distribution TODO" below.

### Windows

```pwsh
flutter build windows --release
```

Output: `build\windows\x64\runner\Release\selecto.exe` plus the required DLLs
(`flutter_windows.dll`, `onnxruntime.dll`, `sqlite3.dll`, plugin libs, and a
`data\` folder with bundled assets). Ship **the whole `Release\` folder** —
the `.exe` alone won't run.

To zip:

```pwsh
Compress-Archive -Path build\windows\x64\runner\Release\* -DestinationPath selecto-windows-x64.zip
```

### macOS

```pwsh
flutter build macos --release
```

Output: `build/macos/Build/Products/Release/selecto.app` — a self-contained
bundle. For distribution outside the App Store you'll need to sign with a
Developer ID Application cert and notarize:

```pwsh
codesign --deep --force --options runtime --sign "Developer ID Application: <name>" selecto.app
xcrun notarytool submit selecto.app.zip --apple-id <id> --team-id <team> --password <app-specific-pw> --wait
xcrun stapler staple selecto.app
```

### Linux

```pwsh
flutter build linux --release
```

Output: `build/linux/x64/release/bundle/` — ship the whole directory. Pack as
tarball, AppImage, Flatpak, or Snap depending on distribution target.

### Build size sanity check

A clean Windows release of this project should sit around **40–60 MB** before
ONNX models are added. The largest pieces are `flutter_windows.dll` (~20 MB),
`onnxruntime.dll` (~10 MB), and `sqlite3.dll` (~1.5 MB). If your build balloons
past 100 MB, check `assets/models/` — `.onnx` weights are gitignored and easy
to forget about during packaging.

## Common dev workflows

| Goal                                  | Command                                                                    |
| ------------------------------------- | -------------------------------------------------------------------------- |
| Pull main and bring deps up to date   | `flutter pub get && dart run build_runner build --delete-conflicting-outputs` |
| Reset codegen if outputs go weird     | `dart run build_runner clean && dart run build_runner build --delete-conflicting-outputs` |
| Add a new Riverpod provider           | Annotate with `@riverpod`, save, let `build_runner watch` regenerate       |
| Add a new Drift table                 | Edit `lib/data/local/app_database.dart`, bump `schemaVersion`, regenerate  |
| Wipe local dev DB                     | Delete `%APPDATA%\com.selecto\selecto\selecto.sqlite` (Win) / `~/Library/Application Support/com.selecto/selecto/selecto.sqlite` (macOS) |
| Fresh start after weird state         | `flutter clean && flutter pub get && dart run build_runner build --delete-conflicting-outputs` |

## Performance notes

- **Grid:** `GridView.builder` with `cacheWidth`/`cacheHeight` thumbnails so
  Flutter decodes the image at thumbnail resolution, not the full 24 MP buffer.
- **AI inference:** bounded isolate worker pool. One `OrtSession` per isolate;
  sessions are NOT thread-safe so do not share.
- **DB:** Drift on `sqlite3` FFI. Cached analysis results keyed by
  `(path, mtime, size)` so unchanged files skip re-inference across launches.

## Keyboard shortcuts (gallery)

| Key            | Action                          |
| -------------- | ------------------------------- |
| ← / →          | Move selection cursor           |
| ↑ / ↓          | Move cursor by one row          |
| Space          | Toggle pick on current photo    |
| Ctrl/Cmd + A   | Pick all visible                |
| Ctrl/Cmd + D   | Unpick all                      |
| Enter          | Open full-screen viewer         |

## Troubleshooting

| Symptom                                                                  | Fix                                                                                   |
| ------------------------------------------------------------------------ | ------------------------------------------------------------------------------------- |
| `Target of URI hasn't been generated: 'package:selecto/...g.dart'`       | Run `dart run build_runner build --delete-conflicting-outputs`                        |
| `Undefined class 'AppDatabaseRef' / 'CachedAnalysesCompanion'`           | Same — codegen hasn't run                                                             |
| `Visual Studio not installed` on `flutter doctor`                        | VS Installer → add "Desktop development with C++" workload                            |
| `Unable to load asset: assets/models/quality.onnx`                       | Drop an `.onnx` file at `assets/models/quality.onnx`                                  |
| Build cache acts up after package upgrade                                | `flutter clean && flutter pub get && dart run build_runner build --delete-conflicting-outputs` |
| Stale `*.g.dart` files after switching branches                          | `dart run build_runner clean` then rebuild                                            |

## Distribution TODO

Not done yet — open if you want to contribute:

- [ ] Windows code signing + MSIX packaging
- [ ] macOS notarization automation
- [ ] Linux AppImage / Flatpak manifest
- [ ] GitHub Actions CI matrix (build + test on all three OSes)
- [ ] Auto-update channel
