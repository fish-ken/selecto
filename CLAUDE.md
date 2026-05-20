# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

Shell is PowerShell on Windows; commands work cross-platform unless noted.

| Task                       | Command                                                                 |
| -------------------------- | ----------------------------------------------------------------------- |
| Install deps               | `flutter pub get`                                                       |
| Codegen (Riverpod/Drift/Freezed) | `dart run build_runner build --delete-conflicting-outputs`        |
| Watch codegen              | `dart run build_runner watch --delete-conflicting-outputs`              |
| Run app                    | `flutter run -d windows` (or `macos` / `linux`)                         |
| All tests                  | `flutter test`                                                          |
| Single test file           | `flutter test test/domain/select_best_shots_test.dart`                  |
| Single test by name        | `flutter test --plain-name "drops blinks and low-sharpness"`            |
| Lint                       | `flutter analyze`                                                       |
| Riverpod lint              | `dart run custom_lint`                                                  |

Codegen output (`*.g.dart`, `*.freezed.dart`) is gitignored and **must be regenerated** after pulling or changing any `@riverpod` / `@freezed` / Drift table. The app will not compile until `build_runner` has run at least once.

Platform folders (`windows/`, `macos/`, `linux/`) are not checked in. First-time setup on a fresh clone: `flutter create --platforms=windows,macos,linux --org=com.selecto .`

## Architecture

Clean Architecture with one hard rule: **UI never crosses into FFI**. The call chain is always

```
Widget → Riverpod controller → use case → repository interface
                                              ↓ (impl)
                                          AiService facade → isolate worker → OrtSession
```

`lib/domain/` is pure Dart (no Flutter, no `dart:io`, no FFI). Adding a Flutter or platform import there is a layer violation. `lib/ai/` and `lib/data/` depend on `domain/`; nothing depends back the other way.

### Cache identity

`Photo.cacheKey = "<path>::<mtime_ms>::<bytes>"` is the identity used everywhere — Drift's primary key (`CachedAnalyses.cacheKey`), the `AnalysisResult.photoCacheKey` field, and the per-photo dedup in `AiAnalysisRepositoryImpl`. If you change the formula in `lib/domain/entities/photo.dart`, the entire on-disk cache is invalidated; preserve it unless you also bump `AppDatabase.schemaVersion` and write a migration.

### AI isolate pool — critical invariants

`OnnxAiService` (`lib/ai/onnx_ai_service.dart`) maintains a bounded pool of worker isolates and dispatches round-robin. Two invariants must hold:

1. **One `OrtSession` per isolate, for the isolate's whole life.** `OrtSession` is not thread-safe. Never share a session between isolates, never construct one outside `aiWorkerEntry` (`lib/ai/isolate_worker.dart`).
2. **Concurrency is bounded by `workerCount`.** `analyzeAll` dispatches at most `workerCount` requests at a time so memory stays flat regardless of input size. Don't replace it with `Future.wait(photos.map(analyze))` — that breaks back-pressure.

The pool reuses a single `ReceivePort` for all workers; messages are tagged with a request `id` and looked up in `_pending`. Adding new message types means extending the sealed `WorkerMessage` in `lib/ai/isolate_messages.dart` and handling the case in `_onWorkerMessage`.

### Model wiring

`lib/ai/isolate_worker.dart` is the only file that knows the model's input/output shape. The defaults assume:

- Input name `'input'`, shape `[1, 3, 224, 224]`, ImageNet-normalized NCHW Float32.
- Output decoded as `[quality, sharpness, face_count, blink_prob]` from the first output tensor.

When a real model is dropped into `assets/models/quality.onnx`, adjust the input name in `session.run(...)` and `_decodeOutputs` to match its head — everything else (preprocessing constants, isolate count, repository caching) stays unchanged.

### State management conventions

Providers go in `lib/app/providers.dart` (cross-cutting) or alongside the feature controller (`lib/features/<feature>/<name>_controller.dart`). All providers use the `@riverpod` codegen annotation — no manual `StateNotifierProvider`. Long-lived dependencies (DB, AI service, repositories) are `@Riverpod(keepAlive: true)`; feature controllers are not, so they reset when their screen unmounts.

`GalleryController.openDirectory` batches scanned photos in groups of 32 before publishing state — directly emitting on every file causes O(n²) rebuilds for large directories. Preserve the batching if you touch the scan loop.

### Grid performance

The grid relies on three things for 5,000+ photos to stay smooth:

- `Image.file` with `cacheWidth`/`cacheHeight` set from `MediaQuery.devicePixelRatioOf` × tile extent. Without this, Flutter decodes the full 24MP buffer per tile.
- `addAutomaticKeepAlives: false` on `GridView.builder` so off-screen tiles release their image memory.
- `Shortcuts`/`Actions` over `RawKeyboardListener` so focus traversal still works.

Keep all three when refactoring `gallery_screen.dart` / `photo_tile.dart`.
