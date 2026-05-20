# native/

Native artifacts bundled per-platform.

- `onnxruntime/<platform>/` — prebuilt ONNX Runtime shared libs (downloaded by
  the `onnxruntime` Dart package on first build; this directory is gitignored).

If you need a custom build (GPU EP, CoreML EP, etc.), drop the libraries here
and wire them up via the platform-specific build hooks
(`windows/CMakeLists.txt`, `macos/Podfile`, `linux/CMakeLists.txt`).
