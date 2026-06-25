# Selecto
<img width="1266" height="812" alt="image" src="https://github.com/user-attachments/assets/65e7611f-7405-4a09-a551-99bbbaa35f7e" />
<img width="1266" height="812" alt="image" src="https://github.com/user-attachments/assets/a1e7f3ee-3bbf-4b69-924e-a7f3fdd06f6b" />


AI 기반 사진 컬링(culling) + RAW 뷰어 — Windows · macOS · Linux 데스크톱 앱.

**설치본 다운로드:** https://github.com/fish-ken/selecto/releases
(Windows MSIX 설치 방법은 [INSTALL.md](INSTALL.md) 참고 — 자체 서명 인증서라 첫 설치 시 인증서 등록이 필요합니다.)

> 아래는 **소스에서 빌드/개발**하려는 사람을 위한 문서입니다. 그냥 쓰기만 할 거라면 위 릴리스에서 설치본을 받으세요.

## 주요 기능

- **AI 품질 점수** — ONNX 모델 3종(MANIQA 기술 품질 + NIMA 미적/기술)으로 사진을 점수화하고 베스트 샷을 자동 추천 (`docs/ai-scoring-pipeline.html` 참고).
- **RAW 지원** — `.NEF` / `.CR2` / `.ARW` / `.RAF` 등 카메라 RAW를 **별도 설치 없이** 표시 (내장 Dart 추출기가 RAW 안의 임베드 JPEG 프리뷰를 사용).
- **유사 사진 그룹핑** — dHash 클러스터링으로 연사/유사 컷을 묶어 좌측 패널에서 그룹별로 필터.
- **전체 화면 뷰어** — EXIF 메타데이터 + 히스토그램 정보 패널('i' 토글), 줌/패닝, 점진적 프리뷰 로딩.
- **다국어 UI** — 한국어 · English · 日本語 · 中文 (`assets/i18n/`).
- **대용량 그리드** — 5,000+ 장도 부드럽게 스크롤되는 가상화 썸네일 그리드.

## Quickstart

가장 빠르게 실행하는 두 경로입니다. 두 방법 모두 [Prerequisites](#prerequisites) 설치가 끝나 있어야 합니다.

### A. VS Code에서 F5 (권장)

이 저장소에는 `.vscode/launch.json` 과 `.vscode/tasks.json` 이 들어 있어 클릭 한 번으로 실행됩니다.

1. VS Code로 프로젝트 폴더를 엽니다.
2. **Run and Debug** 패널을 엽니다 (`Ctrl+Shift+D`).
3. 상단 드롭다운에서 구성을 선택하고 **F5** 또는 ▶ 클릭.

| 구성 이름 | 동작 |
| --- | --- |
| **Dev Run** | `build_runner build` 후 디버그 모드로 앱 실행 (hot reload 가능) |
| **Profile Run** | `build_runner build` 후 프로파일 모드 실행 — 프레임 타이밍 측정용 |
| **Release Run** | `build_runner build` 후 릴리스 모드 실행 — 실배포 동작 확인용 |
| **Dev Run (no codegen)** | codegen 단계 생략 — 별도 터미널에 `build_runner: watch` 를 띄워둔 경우 사용 |
| **Init** | `flutter pub get` → `build_runner build` 등 초기화를 한 번에 실행 (fresh clone 후 1회) |

**처음 클론한 직후의 권장 순서**

1. `git lfs pull` 로 AI 모델을 받습니다 (LFS — 아래 [Prerequisites](#prerequisites) 참고).
2. **Init** 선택 후 F5 → 의존성 + codegen 완료.
3. **Dev Run** 선택 후 F5 → 앱 실행.

### B. CLI로 직접 실행

```pwsh
git lfs pull                                              # AI 모델(LFS) 내려받기
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run -d windows                                    # 또는 macos, linux
```

자세한 단계 설명은 아래 [First-time setup](#first-time-setup) 참고.

## Architecture

엄격한 레이어 경계를 가진 Clean Architecture 입니다. **UI는 절대 FFI를 직접 호출하지 않습니다.**

```
lib/
├── app/            앱 셸, 테마, 라우터, 교차 관심사 provider
├── core/           공통 유틸 (logging, Result 타입, Failure 계층)
├── domain/         Pure Dart — 엔티티, 리포지토리 인터페이스, 유스케이스
├── data/           리포지토리 구현, Drift DB, 로컬 파일 스캐너
├── ai/             ONNX 서비스 facade, Isolate 워커 풀, 전처리, model_configs/
├── l10n/           로컬라이제이션 로더
└── features/
    ├── gallery/    가상화된 사진 그리드 + 키보드 단축키 + 좌측 폴더/그룹 패널
    ├── viewer/     전체 화면 뷰어 (EXIF·히스토그램 패널)
    ├── settings/   설정 다이얼로그
    └── shared/     기능 간 공용 위젯
```

의존성 방향: `features → domain ← data / ai`. `domain`은 어떤 외부 패키지에도 의존하지 않습니다.

## Prerequisites

- **Flutter SDK 3.22+** — https://docs.flutter.dev/get-started/install
- **Git LFS** — AI 모델(`assets/models/*.onnx`)이 Git LFS로 관리됩니다. `git lfs install` 후 클론하거나, 이미 클론했다면 `git lfs pull` 을 실행하세요. LFS가 없으면 모델 자리에 수십 바이트짜리 포인터 파일만 받아져 분석이 실패합니다.
- **Windows**: Visual Studio + "Desktop development with C++" 워크로드
- **macOS**: Xcode 14+ 및 command-line tools
- **Linux**: `clang`, `cmake`, `ninja-build`, `pkg-config`, `libgtk-3-dev`

설치 확인:

```pwsh
flutter doctor      # 타겟 플랫폼 항목이 모두 ✓ 여야 합니다
```

> 플랫폼별 네이티브 폴더(`windows/`, `macos/`, `linux/`)는 **저장소에 커밋돼 있습니다.** 예전처럼 `flutter create` 를 따로 실행할 필요가 없습니다 — `flutter pub get` 이 누락된 생성 파일을 채웁니다.

## First-time setup

신규 클론 시 아래 순서대로 실행합니다.

```pwsh
# 1) AI 모델(LFS) 내려받기 — git lfs install 이 돼 있으면 클론 때 자동
git lfs pull

# 2) Dart/Flutter 의존성 해결
flutter pub get

# 3) 코드 생성 산출물 출력 (Riverpod, Drift, Freezed, JSON)
dart run build_runner build --delete-conflicting-outputs
```

3단계는 **필수입니다**. `providers.dart`, `gallery_controller.dart`, `app_database.dart` 등이 `*.g.dart` / `*.freezed.dart` 를 import 하므로, `build_runner` 를 돌리지 않으면 컴파일 자체가 실패합니다 (이 산출물들은 gitignore 됩니다).

> VS Code 사용 시 2~3단계는 **Init** 런치 구성을 F5로 실행하면 한 번에 처리됩니다.

## AI 모델

분석에 쓰이는 ONNX 모델은 **저장소에 함께 들어 있습니다** (Git LFS 추적):

| 파일 | 역할 |
| --- | --- |
| `assets/models/maniqa_kadid10k.onnx` | MANIQA — 기술 품질(노이즈/블러/노출 등) 평가 |
| `assets/models/nima_mobilenet_aesthetic.onnx` | NIMA — 미적(aesthetic) 점수 |
| `assets/models/nima_mobilenet_technical.onnx` | NIMA — 기술(technical) 점수 |

각 모델의 입력 shape·전처리·출력 해석은 `lib/ai/model_configs/` 의 설정 클래스에 정의돼 있습니다. 새 모델을 추가하려면 `.onnx` 를 `assets/models/` 에 넣고 `ModelConfig` 구현을 하나 만들어 `model_configs.dart` 에서 export 하면 됩니다. 점수 합산 파이프라인은 `docs/ai-scoring-pipeline.html` 에 시각화돼 있습니다.

## Running

### Debug (기본 — hot reload)

```pwsh
flutter run -d windows      # 또는 macos, linux
```

`r` = hot reload, `R` = hot restart, `q` = 종료. 디바이스가 여러 개라면:

```pwsh
flutter devices
flutter run -d "Windows (desktop)"
```

### Profile 모드 (릴리스에 가까운 성능, DevTools 부착)

프레임 타이밍이나 AI 처리량을 측정할 때 사용합니다. Debug 모드는 JIT 체크가 매 줄마다 끼어들어 실제 성능과 차이가 큽니다.

```pwsh
flutter run -d windows --profile
```

### Release 모드 (AOT 컴파일, DevTools 없음)

```pwsh
flutter run -d windows --release
```

### Codegen watcher (개발 중 별도 터미널에서)

`@riverpod` / `@freezed` / Drift 테이블을 수정할 때마다 `*.g.dart` 가 자동 재생성됩니다.

```pwsh
dart run build_runner watch --delete-conflicting-outputs
```

VS Code에서는 `Ctrl+Shift+P → Tasks: Run Task → build_runner: watch` 로도 띄울 수 있습니다.

## Testing

```pwsh
flutter test                                                      # 전체
flutter test test/domain/select_best_shots_test.dart              # 단일 파일
flutter test --plain-name "drops blinks and low-sharpness"        # 이름으로 단일 테스트
flutter test --coverage                                           # 커버리지 (coverage/lcov.info)
```

### 정적 분석

```pwsh
flutter analyze            # analysis_options.yaml 기반 Dart analyzer + lint
dart run custom_lint       # Riverpod 전용 lint (provider 오용, 스코프 누수 등)
```

## Release builds

Windows · macOS · Linux 릴리스 산출물 생성과 빌드 크기 점검은 **[BUILD.md](BUILD.md)**,
설치본 패키징(MSIX / DMG / deb / AppImage) · 코드 서명 · CI는 **[docs/DISTRIBUTION.md](docs/DISTRIBUTION.md)** 를 참고하세요.

## Common dev workflows

| 목적 | 명령 |
| --- | --- |
| main pull 후 동기화 | `git lfs pull && flutter pub get && dart run build_runner build --delete-conflicting-outputs` |
| codegen 출력이 꼬인 경우 초기화 | `dart run build_runner clean && dart run build_runner build --delete-conflicting-outputs` |
| 새 Riverpod provider 추가 | `@riverpod` 어노테이션 + 저장 → `build_runner watch` 가 자동 재생성 |
| 새 Drift 테이블 추가 | `lib/data/local/app_database.dart` 수정 → `schemaVersion` 증가 → 재생성 |
| 로컬 dev DB 초기화 | `%APPDATA%\com.fish-ken\selecto\selecto.sqlite` (Windows) / `~/Library/Application Support/com.fish-ken/selecto/selecto.sqlite` (macOS) 삭제 |
| 상태가 꼬였을 때 전체 리셋 | `flutter clean && flutter pub get && dart run build_runner build --delete-conflicting-outputs` |

## Performance notes

- **Grid**: `GridView.builder` + `cacheWidth`/`cacheHeight` 썸네일. 전체 24 MP 버퍼가 아닌 썸네일 해상도로만 디코드합니다.
- **AI inference**: bounded isolate 워커 풀. **Isolate 1개 = `OrtSession` 1개**가 불변식 — 세션은 스레드 안전하지 않으므로 절대 공유하지 마세요.
- **DB**: Drift + `sqlite3` FFI. 분석 결과는 `(path, mtime, size)` 키로 캐시되어, 변경되지 않은 파일은 다음 실행 때 재추론을 건너뜁니다.

## Keyboard shortcuts (Gallery / Viewer)

| 키 | 동작 |
| --- | --- |
| ← / → | 선택을 좌우로 이동 (단일 선택, 이전 항목 해제) |
| ↑ / ↓ | 선택을 한 줄 위/아래로 이동 (갤러리) |
| Shift + 방향키 | 앵커 기준 연속 범위로 다중 선택 확장 |
| Ctrl/Cmd + 방향키 | 커서 이동 + 도착 사진을 선택에 추가 (기존 선택 유지) |
| Space | 현재 사진 픽 토글 |
| Ctrl/Cmd + A | 전체 선택 |
| Ctrl/Cmd + D | 전체 해제 |
| Enter | 전체 화면 뷰어 열기 (뷰어에서는 닫기) |
| i | (뷰어) EXIF·히스토그램 정보 패널 토글 |

마우스: 클릭 = 단일 선택, **Ctrl/Cmd + 클릭** = 토글, **Shift + 클릭** = 범위 선택, 우클릭 = 컨텍스트 메뉴(BestShots 이동/제거), 더블클릭 = 뷰어 열기.

## Troubleshooting

| 증상 | 해결책 |
| --- | --- |
| `Target of URI hasn't been generated: 'package:selecto/...g.dart'` | `dart run build_runner build --delete-conflicting-outputs` 실행 |
| `Undefined class 'AppDatabaseRef' / 'CachedAnalysesCompanion'` | 위와 동일 — codegen이 안 돌아간 상태 |
| 분석을 눌러도 동작하지 않음 / 모델 로드 실패 | `assets/models/*.onnx` 가 수 KB 미만이면 LFS 포인터만 받아진 상태 — `git lfs pull` 실행 |
| `flutter doctor` 에서 `Visual Studio not installed` | Visual Studio Installer → "Desktop development with C++" 워크로드 추가 |
| 패키지 업그레이드 후 빌드 캐시 꼬임 | `flutter clean && flutter pub get && dart run build_runner build --delete-conflicting-outputs` |
| 브랜치 전환 후 stale `*.g.dart` | `dart run build_runner clean` 후 재빌드 |
| F5 때 코드 생성이 매번 너무 느림 | 별도 터미널에 `build_runner: watch` 띄우고 launch 구성은 **Dev Run (no codegen)** 사용 |
