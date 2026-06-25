# 릴리스 빌드 (Build)

Windows · macOS · Linux 용 **릴리스 산출물**(실행 가능한 빌드)을 만드는 방법입니다.

- 개발 중 실행/핫리로드 → [README.md](README.md) 의 *Running*
- 설치본 패키징(MSIX / DMG / deb / AppImage) · 코드 서명 · 아이콘 · CI 상세 → **[docs/DISTRIBUTION.md](docs/DISTRIBUTION.md)**

이 문서는 `flutter build` 로 만드는 **원시(raw) 릴리스 빌드**와 빌드 크기 점검에 집중합니다. 인증서로 서명된 설치 패키지는 위 DISTRIBUTION 문서를 따르세요.

## 사전 준비

1. **툴체인** — 타겟 OS 의 네이티브 빌드 도구 (Windows: Visual Studio + "Desktop development with C++", macOS: Xcode, Linux: `clang`/`cmake`/`ninja-build`/`pkg-config`/`libgtk-3-dev`). 자세한 항목은 [README.md → Prerequisites](README.md#prerequisites). `flutter doctor` 가 타겟 플랫폼에 대해 모두 ✓ 여야 합니다.

2. **최초 1회 설정** — 플랫폼 폴더(`windows/`·`macos/`·`linux/`)는 저장소에 커밋돼 있으므로 `flutter create` 는 필요 없습니다. AI 모델(LFS) 내려받기 + 의존성 + 코드 생성만 하면 됩니다:

   ```pwsh
   git lfs pull
   flutter pub get
   dart run build_runner build --delete-conflicting-outputs
   ```

   `build_runner` 단계는 **필수**입니다 — `*.g.dart` / `*.freezed.dart` 가 없으면 컴파일이 실패합니다. main pull 이후나 `@riverpod`/`@freezed`/Drift 테이블 변경 후에도 다시 돌려야 합니다.

3. **AI 모델** — `assets/models/*.onnx` (MANIQA + NIMA 2종)는 Git LFS 로 관리되며 저장소에 포함돼 있습니다. `git lfs pull` 이 안 됐으면 포인터 파일만 빌드에 들어가 분석이 실패합니다.

## 플랫폼별 릴리스 빌드

> 크로스 컴파일은 안 됩니다 — 각 산출물은 **해당 OS에서** 빌드해야 합니다.

### Windows

```pwsh
flutter build windows --release
```

출력: `build\windows\x64\runner\Release\selecto.exe` + 필수 DLL (`flutter_windows.dll`, `onnxruntime.dll`, `sqlite3.dll`, 플러그인 라이브러리), 그리고 번들 에셋이 담긴 `data\` 폴더.

**`Release\` 폴더 전체를 함께 배포해야 합니다** — `.exe` 단독으로는 실행되지 않습니다. 다만 일반 배포는 포터블 zip 보다 **MSIX 설치본**을 권장합니다 ([docs/DISTRIBUTION.md](docs/DISTRIBUTION.md)). 굳이 포터블 zip 이 필요하면:

```pwsh
Compress-Archive -Path build\windows\x64\runner\Release\* -DestinationPath selecto-windows-x64.zip
```

### macOS

```pwsh
flutter build macos --release
```

출력: `build/macos/Build/Products/Release/selecto.app` — 자체 완결된 번들. App Store 외부 배포 시 서명·공증이 필요합니다 (절차는 [docs/DISTRIBUTION.md → macOS](docs/DISTRIBUTION.md)).

### Linux

```pwsh
flutter build linux --release
```

출력: `build/linux/x64/release/bundle/` — 디렉터리 전체를 배포하거나 `.deb` / AppImage 로 패키징합니다 ([docs/DISTRIBUTION.md → Linux](docs/DISTRIBUTION.md)).

## 설치본 패키징 (빠른 참조)

오케스트레이션은 [`flutter_distributor`](https://distributor.leanflutter.dev) (`distribute_options.yaml`) 가 담당합니다. 자세한 서명/설정은 [docs/DISTRIBUTION.md](docs/DISTRIBUTION.md).

```pwsh
dart pub global activate flutter_distributor                        # 머신당 1회

flutter_distributor package --platform windows --targets msix       # Windows .msix
flutter_distributor package --platform macos   --targets dmg        # macOS .dmg
flutter_distributor package --platform linux   --targets deb,appimage  # Linux .deb + AppImage
```

산출물은 `dist/` 에 떨어집니다.

## 빌드 크기 sanity check

이 앱은 **AI 모델을 에셋으로 번들**합니다. 가장 큰 `maniqa_kadid10k.onnx` 가 ~436 MB 라서 모델을 포함한 릴리스 빌드/설치본은 **약 470–500 MB** 가 정상입니다 (NIMA 2종은 각 ~13 MB).

모델을 제외한 순수 런타임은 **40–60 MB** 정도이며, 큰 부분은 `flutter_windows.dll`(~20 MB), `onnxruntime.dll`(~10 MB), `sqlite3.dll`(~1.5 MB) 입니다.

- 빌드가 **40–60 MB** 로 너무 작다면 → `assets/models/` 에 LFS 포인터만 들어간 상태입니다. `git lfs pull` 후 재빌드하세요.
- 설치본 용량을 줄이고 싶다면 → 무거운 MANIQA 모델을 양자화하거나 모델을 첫 실행 시 별도 다운로드하도록 분리하는 방안을 검토하세요(현재는 모두 동봉).

## CI (GitHub Actions)

`.github/workflows/` 에 OS별 릴리스 워크플로가 연결돼 있습니다.

| 워크플로 | 러너 | 산출물 |
| --- | --- | --- |
| `build-windows.yml` | windows-latest | `.msix` (`dart run msix:create`) |
| `build-macos.yml` | macos-latest | `.dmg` (flutter_distributor) |
| `build-linux.yml` | ubuntu-latest | `.deb` + `.AppImage` (flutter_distributor) |
| `build-all.yml` | (오케스트레이션) | 위 3개 호출 + GitHub Release 자동 첨부 |

- 각 워크플로는 **개별로 "Run workflow"** 가능(`workflow_dispatch`)하며, `build-all.yml` 이 `workflow_call` 로 호출합니다.
- `build-all.yml` 은 수동 실행 또는 **`v*` 태그 푸시**(예: `v1.0.3`) 시 3-OS 빌드를 돌리고, 태그일 때는 설치본을 **GitHub Release 에 첨부**합니다 (릴리스 노트는 `.github/release-notes.md` 템플릿 기반).
- 플랫폼 폴더가 커밋돼 있어 `flutter create` 단계는 없습니다 — LFS 체크아웃 → `flutter pub get` → `build_runner` → 패키징 순으로 동작합니다.
- Windows MSIX 는 `WINDOWS_CERT_BASE64` / `WINDOWS_CERT_PASSWORD` 시크릿이 있으면 그 인증서로 서명하고, 없으면 테스트 자체 서명으로 빌드합니다.

서명·공증·아이콘·향후 개선(TODO)은 [docs/DISTRIBUTION.md](docs/DISTRIBUTION.md) 에 정리돼 있습니다.
