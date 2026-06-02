# 릴리스 빌드 (Build)

Windows · macOS · Linux 용 **릴리스 산출물**을 만드는 방법입니다. 개발 중 실행/핫리로드는 [README.md](README.md) 의 *Running* 을 참고하세요.

> 빌드 산출물은 **서명되지 않은 상태**입니다. 코드 사이닝, 공증, 인스톨러 패키징은 아직 자동화되지 않았습니다 — 맨 아래 [Distribution TODO](#distribution-todo) 참고.

## 사전 준비

1. **툴체인** — 타겟 OS 의 네이티브 빌드 도구가 설치돼 있어야 합니다 (Windows: Visual Studio + "Desktop development with C++", macOS: Xcode, Linux: `clang`/`cmake`/`ninja-build`/`pkg-config`/`libgtk-3-dev`). 자세한 항목은 [README.md → Prerequisites](README.md#prerequisites) 참고. `flutter doctor` 가 타겟 플랫폼에 대해 모두 ✓ 여야 합니다.

2. **최초 1회 설정** — fresh clone 이라면 네이티브 폴더 생성과 코드 생성을 먼저 끝내야 빌드가 됩니다 (자세한 내용은 [README.md → First-time setup](README.md#first-time-setup)):

   ```pwsh
   flutter create --platforms=windows,macos,linux --org=com.fish-ken .
   flutter pub get
   dart run build_runner build --delete-conflicting-outputs
   ```

   `build_runner` 단계는 **필수**입니다 — `*.g.dart` (Riverpod/Drift/Freezed) 가 없으면 컴파일 자체가 실패합니다. main pull 이후나 `@riverpod`/`@freezed`/Drift 테이블 변경 후에도 다시 돌려야 합니다.

3. **AI 모델** — `assets/models/` 에 `.onnx` 모델 파일이 있어야 분석 기능이 동작합니다 (모델은 Git LFS 로 관리됩니다 — `.gitattributes` 참고). 모델 없이도 빌드/그리드 UI 는 동작합니다.

## 플랫폼별 릴리스 빌드

### Windows

```pwsh
flutter build windows --release
```

출력: `build\windows\x64\runner\Release\selecto.exe` + 필수 DLL 들 (`flutter_windows.dll`, `onnxruntime.dll`, `sqlite3.dll`, 플러그인 라이브러리들, 그리고 번들 에셋이 담긴 `data\` 폴더).

**`Release\` 폴더 전체를 함께 배포해야 합니다** — `.exe` 단독으로는 실행되지 않습니다.

배포용 zip 생성:

```pwsh
Compress-Archive -Path build\windows\x64\runner\Release\* -DestinationPath selecto-windows-x64.zip
```

### macOS

```pwsh
flutter build macos --release
```

출력: `build/macos/Build/Products/Release/selecto.app` — 자체 완결된 번들. App Store 외부에서 배포하려면 Developer ID Application 인증서로 서명 후 공증해야 합니다:

```pwsh
codesign --deep --force --options runtime --sign "Developer ID Application: <이름>" selecto.app
xcrun notarytool submit selecto.app.zip --apple-id <id> --team-id <team> --password <앱-전용-암호> --wait
xcrun stapler staple selecto.app
```

### Linux

```pwsh
flutter build linux --release
```

출력: `build/linux/x64/release/bundle/` — 디렉터리 전체를 배포합니다. 배포 대상에 따라 tarball, AppImage, Flatpak, Snap 중 선택하여 패키징합니다.

## 빌드 크기 sanity check

ONNX 모델을 빼고 깨끗하게 빌드한 Windows release 는 **40–60 MB** 정도가 정상입니다. 큰 부분은 `flutter_windows.dll`(~20 MB), `onnxruntime.dll`(~10 MB), `sqlite3.dll`(~1.5 MB) 입니다. 100 MB 를 넘어가면 `assets/models/` 안에 `.onnx` 모델이 함께 패키징됐는지 확인하세요 (LFS 로 추적되므로 의도치 않게 포함될 수 있음).

## CI (GitHub Actions)

`.github/workflows/` 에 릴리스 빌드 워크플로가 있습니다.

| 파일 | 역할 |
| --- | --- |
| `build-windows.yml` | Windows x64 릴리스 빌드 → `selecto-windows-x64` 아티팩트 |
| `build-macos.yml` | macOS 릴리스 빌드(.app zip) → `selecto-macos` 아티팩트 |
| `build-linux.yml` | Linux x64 릴리스 빌드 → `selecto-linux-x64` 아티팩트 |
| `build-all.yml` | 위 세 워크플로를 **한 번에 병렬 호출**하는 배치 진입점 |

- 각 OS 워크플로는 Actions 탭에서 **개별로 "Run workflow"** 할 수 있고(`workflow_dispatch`), `build-all.yml` 이 `workflow_call` 로 호출합니다.
- `build-all.yml` 은 수동 실행 또는 **`v*` 태그 푸시**(예: `v0.1.0`) 시 3-OS 빌드를 동시에 돌립니다.
- 각 워크플로는 fresh clone 과 동일하게 `flutter create` → `pub get` → `build_runner` → `flutter build <platform> --release` 순서로 실행하며, 모델은 LFS(`lfs: true`) 로 함께 체크아웃합니다. Flutter 는 `stable` 채널을 쓰며, 재현성이 필요하면 워크플로의 `FLUTTER_CHANNEL` 자리를 특정 버전으로 고정하세요.

## Distribution TODO

아직 미구현 — 기여 환영합니다:

- [ ] Windows 코드 사이닝 + MSIX 패키징
- [ ] macOS 공증(notarization) 자동화
- [ ] Linux AppImage / Flatpak manifest
- [ ] GitHub Actions CI 매트릭스 (3-OS 빌드 + 테스트)
- [ ] 자동 업데이트 채널
