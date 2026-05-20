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

## Setup

1. Install the Flutter SDK (3.22+): https://docs.flutter.dev/get-started/install
2. Generate platform folders:
   ```pwsh
   flutter create --platforms=windows,macos,linux --org=com.selecto .
   ```
3. Install dependencies:
   ```pwsh
   flutter pub get
   ```
4. Run codegen (Riverpod, Freezed, Drift, JSON):
   ```pwsh
   dart run build_runner build --delete-conflicting-outputs
   ```
5. Drop your `.onnx` model into `assets/models/` (e.g. `quality.onnx`).
6. Launch:
   ```pwsh
   flutter run -d windows
   ```

## Performance notes

- **Grid:** `GridView.builder` with `cacheWidth`/`cacheHeight` thumbnails. Image
  decode happens off-thread (Flutter's image cache + `image` pkg in an isolate).
- **AI inference:** bounded isolate worker pool. One `OrtSession` per isolate;
  sessions are NOT thread-safe so do not share.
- **DB:** Drift on `sqlite3` FFI. Cached analysis results keyed by `(path, mtime, size)`.

## Keyboard shortcuts (gallery)

| Key            | Action                          |
| -------------- | ------------------------------- |
| ← / →          | Move selection cursor           |
| Space          | Toggle pick on current photo    |
| Ctrl/Cmd + A   | Pick all visible                |
| Ctrl/Cmd + D   | Unpick all                      |
| Enter          | Open full-screen viewer         |
