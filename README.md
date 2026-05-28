# Selecto

Windows · macOS · Linux 데스크톱용 **AI 기반 사진 컬링/선별 앱**.
Flutter · Riverpod · ONNX Runtime(`dart:ffi`)으로 구성되어 있습니다.

## Quickstart

가장 빠르게 실행하는 두 가지 경로입니다. 두 방법 모두 사전에 [Prerequisites](#prerequisites)의 설치는 마쳐 있어야 합니다.

### A. VS Code에서 F5 한 번으로 끝내기 (권장)

이 저장소에는 `.vscode/launch.json` 과 `.vscode/tasks.json` 이 들어 있어 클릭 한 번으로 초기화 → 실행이 가능합니다.

1. VS Code로 프로젝트 폴더 (`F:\F-Workspace\selecto`) 를 엽니다.
2. 좌측 사이드바의 **Run and Debug** 패널을 엽니다 (`Ctrl+Shift+D`).
3. 상단 드롭다운에서 원하는 구성을 선택하고 **F5** 또는 ▶ 클릭.

| 구성 이름 | 동작 |
| --- | --- |
| **Init** | `flutter create` → `flutter pub get` → `build_runner build` 를 순차 실행. 앱은 실행하지 않음 — **fresh clone 직후 1회만** 사용 |
| **Dev Run** | `build_runner build` 후 디버그 모드로 앱 실행 (hot reload 가능) |
| **Profile Run** | `build_runner build` 후 프로파일 모드 실행 — 프레임 타이밍 측정용 |
| **Release Run** | `build_runner build` 후 릴리스 모드 실행 — 실배포 동작 확인용 |
| **Dev Run (custom model)** | `--dart-define=MODEL_PATH=...` 로 ONNX 모델 경로 오버라이드 (예시 설정) |
| **Dev Run (no codegen)** | codegen 단계 생략 — 별도 터미널에 `build_runner: watch` 를 띄워둔 경우 사용 |

**처음 클론한 직후의 권장 순서**

1. **Init** 선택 후 F5 → 초기화 완료 후 자동 종료
2. **Dev Run** 선택 후 F5 → 앱 실행

### B. CLI로 직접 실행

VS Code를 쓰지 않거나 CI 등에서 수동 실행하려는 경우.

```pwsh
flutter create --platforms=windows,macos,linux --org=com.fish-ken .
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run -d windows
```

자세한 단계 설명은 아래 [First-time setup](#first-time-setup) 참고.

## Architecture

엄격한 레이어 경계를 가진 Clean Architecture 입니다. **UI는 절대 FFI를 직접 호출하지 않습니다.**

```
lib/
├── app/            앱 셸, 테마, 라우터
├── core/           공통 유틸 (logging, Result 타입, Failure 계층)
├── domain/         Pure Dart — 엔티티, 리포지토리 인터페이스, 유스케이스
├── data/           리포지토리 구현, Drift DB, 로컬 파일 스캐너
├── ai/             ONNX 서비스 facade, Isolate 워커 풀, 이미지 전처리
└── features/
    └── gallery/    가상화된 사진 그리드 + 키보드 단축키
```

의존성 방향: `features → domain ← data / ai`. `domain`은 어떤 외부 패키지에도 의존하지 않습니다.

## Prerequisites

- **Flutter SDK 3.22+** — https://docs.flutter.dev/get-started/install
- **Windows**: Visual Studio + "Desktop development with C++" 워크로드
- **macOS**: Xcode 14+ 및 command-line tools
- **Linux**: `clang`, `cmake`, `ninja-build`, `pkg-config`, `libgtk-3-dev`
- **exiftool** *(선택 — 카메라 RAW 파일 지원용)*: `.NEF` / `.CR2` / `.ARW` / `.RAF` 등 RAW 파일을 다루려면 PATH 에 `exiftool` 이 있어야 합니다. 없으면 RAW 파일은 스캔 시 그냥 건너뜁니다 (JPEG/PNG 등은 영향 없음).
  ```pwsh
  winget install -e --id OliverBetz.ExifTool        # Windows
  brew install exiftool                              # macOS
  sudo apt install libimage-exiftool-perl            # Debian/Ubuntu
  ```

설치 확인:

```pwsh
flutter doctor
exiftool -ver       # RAW 지원 쓸 거면 함께 확인
```

타겟 플랫폼에 대한 모든 항목이 ✓ 여야 합니다.

## First-time setup

신규 클론 시 **반드시 아래 순서대로** 실행합니다.

```pwsh
# 1) 플랫폼별 네이티브 폴더(windows/, macos/, linux/) 생성
flutter create --platforms=windows,macos,linux --org=com.fish-ken .

# 2) Dart/Flutter 의존성 해결
flutter pub get

# 3) 코드 생성 산출물 출력 (Riverpod, Drift, Freezed, JSON)
dart run build_runner build --delete-conflicting-outputs
```

3단계는 **필수입니다**. `providers.dart`, `gallery_controller.dart`, `app_database.dart` 가 `*.g.dart` 파일을 import 하기 때문에, `build_runner` 를 돌리지 않으면 컴파일 자체가 실패합니다.

이후 ONNX 모델을 `assets/models/quality.onnx` 위치에 넣습니다. 모델이 없어도 그리드 UI 자체는 동작하지만, "Analyze" 버튼은 모델이 있어야 정상 작동합니다.

> VS Code 사용 시 위 3단계는 **Init** 런치 구성을 F5로 실행하면 한 번에 처리됩니다.

## Running

### Debug (기본 — hot reload, 느림)

```pwsh
flutter run -d windows      # 또는 macos, linux
```

`r` = hot reload, `R` = hot restart, `q` = 종료. 디바이스가 여러 개라면 `--device-id`로 지정:

```pwsh
flutter devices
flutter run -d "Windows (desktop)"
```

### Profile 모드 (릴리스에 가까운 성능, DevTools 부착됨)

프레임 타이밍이나 AI 처리량을 측정할 때 사용합니다. Debug 모드는 JIT 체크가 매 줄마다 끼어들어서 실제 성능과 차이가 큽니다.

```pwsh
flutter run -d windows --profile
```

### Release 모드 (AOT 컴파일, DevTools 없음)

```pwsh
flutter run -d windows --release
```

### Codegen watcher (개발 중 별도 터미널에서 띄워두기)

`@riverpod` / `@freezed` / Drift 테이블을 수정할 때마다 `*.g.dart` 가 자동 재생성됩니다.

```pwsh
dart run build_runner watch --delete-conflicting-outputs
```

VS Code에서는 `Ctrl+Shift+P → Tasks: Run Task → build_runner: watch` 로도 띄울 수 있습니다.

## Testing

```pwsh
# 전체 테스트
flutter test

# 단일 파일
flutter test test/domain/select_best_shots_test.dart

# 이름으로 단일 테스트 (test('...') 의 문자열과 매치)
flutter test --plain-name "drops blinks and low-sharpness"

# 커버리지 포함 (출력: coverage/lcov.info)
flutter test --coverage
```

### 정적 분석

```pwsh
flutter analyze            # analysis_options.yaml 기반 Dart analyzer + lint
dart run custom_lint       # Riverpod 전용 lint (provider 오용, 스코프 누수 등)
```

## Release builds

빌드 산출물은 **서명되지 않은 상태**입니다. 코드 사이닝, 공증, 인스톨러 패키징은 아직 자동화되지 않았습니다 — 아래 "Distribution TODO" 참고.

### Windows

```pwsh
flutter build windows --release
```

출력: `build\windows\x64\runner\Release\selecto.exe` + 필수 DLL들 (`flutter_windows.dll`, `onnxruntime.dll`, `sqlite3.dll`, 플러그인 라이브러리들, 그리고 번들 에셋이 담긴 `data\` 폴더).

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

### 빌드 크기 sanity check

ONNX 모델을 빼고 깨끗하게 빌드한 Windows release는 **40–60 MB** 정도가 정상입니다. 큰 부분은 `flutter_windows.dll`(~20 MB), `onnxruntime.dll`(~10 MB), `sqlite3.dll`(~1.5 MB) 입니다. 100 MB 를 넘어가면 `assets/models/` 안에 `.onnx` 모델이 함께 패키징됐는지 확인하세요 (`.gitignore` 대상이라 깜빡 잊기 쉬움).

## Common dev workflows

| 목적 | 명령 |
| --- | --- |
| main pull 후 의존성/codegen 동기화 | `flutter pub get && dart run build_runner build --delete-conflicting-outputs` |
| codegen 출력이 이상해진 경우 초기화 | `dart run build_runner clean && dart run build_runner build --delete-conflicting-outputs` |
| 새 Riverpod provider 추가 | `@riverpod` 어노테이션 + 저장 → `build_runner watch` 가 자동 재생성 |
| 새 Drift 테이블 추가 | `lib/data/local/app_database.dart` 수정 → `schemaVersion` 증가 → 재생성 |
| 로컬 dev DB 초기화 | `%APPDATA%\com.fish-ken\selecto\selecto.sqlite` (Windows) / `~/Library/Application Support/com.fish-ken/selecto/selecto.sqlite` (macOS) 삭제 |
| 상태가 꼬였을 때 전체 리셋 | `flutter clean && flutter pub get && dart run build_runner build --delete-conflicting-outputs` |

## Performance notes

- **Grid**: `GridView.builder` + `cacheWidth`/`cacheHeight` 썸네일. 전체 24 MP 버퍼가 아닌 썸네일 해상도로만 디코드합니다.
- **AI inference**: bounded isolate 워커 풀. **Isolate 1개 = `OrtSession` 1개**가 불변식 — 세션은 스레드 안전하지 않으므로 절대 공유하지 마세요.
- **DB**: Drift + `sqlite3` FFI. 분석 결과는 `(path, mtime, size)` 키로 캐시되어, 변경되지 않은 파일은 다음 실행 때 재추론을 건너뜁니다.

## Keyboard shortcuts (Gallery)

| 키 | 동작 |
| --- | --- |
| ← / → | 선택 커서 좌우 이동 |
| ↑ / ↓ | 한 줄 위/아래 이동 |
| Space | 현재 사진 픽 토글 |
| Ctrl/Cmd + A | 전체 픽 |
| Ctrl/Cmd + D | 전체 해제 |
| Enter | 전체 화면 뷰어 열기 |

## Troubleshooting

| 증상 | 해결책 |
| --- | --- |
| `Target of URI hasn't been generated: 'package:selecto/...g.dart'` | `dart run build_runner build --delete-conflicting-outputs` 실행 |
| `Undefined class 'AppDatabaseRef' / 'CachedAnalysesCompanion'` | 위와 동일 — codegen이 안 돌아간 상태 |
| `flutter doctor` 에서 `Visual Studio not installed` | Visual Studio Installer → "Desktop development with C++" 워크로드 추가 |
| `Unable to load asset: assets/models/quality.onnx` | `assets/models/quality.onnx` 위치에 ONNX 파일 배치 |
| 패키지 업그레이드 후 빌드 캐시 꼬임 | `flutter clean && flutter pub get && dart run build_runner build --delete-conflicting-outputs` |
| 브랜치 전환 후 stale `*.g.dart` | `dart run build_runner clean` 후 재빌드 |
| F5 했는데 코드 생성이 매번 너무 느림 | 별도 터미널에 `build_runner: watch` 띄우고 launch 구성은 **Dev Run (no codegen)** 사용 |

## Distribution TODO

아직 미구현 — 기여 환영합니다:

- [ ] Windows 코드 사이닝 + MSIX 패키징
- [ ] macOS 공증(notarization) 자동화
- [ ] Linux AppImage / Flatpak manifest
- [ ] GitHub Actions CI 매트릭스 (3-OS 빌드 + 테스트)
- [ ] 자동 업데이트 채널
