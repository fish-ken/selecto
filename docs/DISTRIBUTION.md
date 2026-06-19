# 배포 (Distribution)

Selecto를 Windows / macOS / Linux용 설치본으로 패키징하는 방법입니다.
오케스트레이션은 [`flutter_distributor`](https://distributor.leanflutter.dev)로 하고,
플랫폼별 설정은 아래 파일들에 들어 있습니다.

| 플랫폼  | 산출물        | 설정 파일                                   |
| ------- | ------------- | ------------------------------------------- |
| Windows | `.msix`       | `pubspec.yaml` 의 `msix_config`             |
| macOS   | `.dmg`        | `macos/packaging/dmg/make_config.yaml`      |
| Linux   | `.deb`        | `linux/packaging/deb/make_config.yaml`      |
| Linux   | `.AppImage`   | `linux/packaging/appimage/make_config.yaml` |

> 크로스 컴파일은 안 됩니다 — 각 산출물은 **해당 OS에서** 빌드해야 합니다
> (Windows는 Windows에서, dmg는 macOS에서, deb/AppImage는 Linux에서).

도구 설치(머신당 1회):

```pwsh
dart pub global activate flutter_distributor
flutter pub get   # msix 패키지 가져오기
```

---

## Windows — MSIX (주 배포 방식)

설정은 `pubspec.yaml` 의 `msix_config` 에 있습니다.

```pwsh
# 사이드로드용 .msix (테스트 서명)
dart run msix:create

# 또는 flutter_distributor 경유 (dist\ 에 출력)
flutter_distributor package --platform windows --targets msix

# Microsoft Store 제출용 패키지
dart run msix:create --store
```

### 서명 (중요)

서명하지 않으면 Windows SmartScreen이 "알 수 없는 게시자" 경고를 띄웁니다.

- **테스트/내부용**: 인자 없이 `dart run msix:create` 하면 자체 서명(test) 인증서로
  서명됩니다. 받는 사람이 그 인증서를 "신뢰할 수 있는 사람"에 설치하면 설치됩니다.
- **정식 배포**: 코드 서명 인증서(OV/EV `.pfx`)를 발급받아 `msix_config` 의
  `certificate_path` / `certificate_password` / `publisher` 를 채웁니다.
  `publisher` 는 인증서 주체(subject)와 정확히 일치해야 합니다.
- **Microsoft Store**: 스토어가 서명하므로 인증서 불필요. 단, `broadFileSystemAccess`
  권한은 제출 시 사유 설명이 필요합니다.

### 폴더째 배포 (설치 없이)

설치본이 아니라 포터블로 줄 수도 있습니다:

```pwsh
flutter build windows --release
# build\windows\x64\runner\Release\ 폴더를 통째로 zip
```

단 (1) exe만이 아니라 `Release\` 폴더 전체를 줘야 하고, (2) 대상 PC에 Visual C++
재배포 패키지가 없으면 실행이 안 될 수 있습니다. 그래서 MSIX를 권장합니다.

---

## macOS — DMG

```bash
npm install -g appdmg        # dmg 메이커 의존성
flutter_distributor package --platform macos --targets dmg
```

레이아웃/아이콘/배경은 `macos/packaging/dmg/make_config.yaml` 에서 조정합니다
(그 안의 `.app` 경로/이름이 macOS Runner 의 Product Name 과 맞는지 확인).

### 서명 + 노터라이즈 (Gatekeeper)

서명/노터라이즈하지 않으면 macOS가 "확인되지 않은 개발자" 라며 실행을 막습니다.
Apple Developer 계정으로 `codesign` → `notarytool submit` → `stapler staple` 을
거쳐야 합니다.

---

## Linux — .deb / AppImage

```bash
# .deb (dpkg-deb 필요, 데비안/우분투 기본 포함)
flutter_distributor package --platform linux --targets deb

# AppImage (appimagetool 을 PATH 에 설치)
flutter_distributor package --platform linux --targets appimage
```

- `.deb`: `linux/packaging/deb/make_config.yaml` 의 의존성/메타데이터 확인.
- `AppImage`: `appimagetool` 이 아이콘을 요구합니다 — PNG 아이콘을 추가하고
  `linux/packaging/appimage/make_config.yaml` 의 `icon` 을 활성화하세요.

---

## 아이콘

소스 이미지 한 장(`assets/icon/app_icon.png`)으로 모든 플랫폼 아이콘을 만듭니다.
현재는 **플레이스홀더**(인디고 라운드 사각형 + 흰 별)가 들어 있습니다.

**실제 아이콘으로 교체하기**

1. 정사각 PNG(1024×1024 권장)를 `assets/icon/app_icon.png` 에 덮어쓰기.
   (임시 아이콘을 다시 만들려면: `dart run tool/generate_app_icon.dart`)
2. 런처 아이콘 재생성:
   ```pwsh
   dart run flutter_launcher_icons   # → windows/.../app_icon.ico, macOS iconset
   ```

같은 소스 PNG가 이미 아래에 모두 연결돼 있습니다:

| 쓰임                       | 설정 위치                                       |
| -------------------------- | ----------------------------------------------- |
| Windows exe/작업표시줄(.ico) | `flutter_launcher_icons` (pubspec)              |
| macOS 앱 아이콘            | `flutter_launcher_icons` (pubspec)              |
| Windows MSIX 타일          | `pubspec.yaml` → `msix_config.logo_path`        |
| Linux AppImage             | `linux/packaging/appimage/make_config.yaml` `icon` |

> `flutter_launcher_icons` 가 만든 산출물(`windows/runner/resources/app_icon.ico`,
> `macos/.../AppIcon.appiconset`)은 커밋해 두면 CI 에서 별도 생성 없이 쓰입니다.

---

## CI (GitHub Actions)

`.github/workflows/` 에 OS별 워크플로가 연결돼 있습니다.

| 워크플로            | 러너            | 산출물                         |
| ------------------- | --------------- | ------------------------------ |
| `build-windows.yml` | windows-latest  | `.msix` (`dart run msix:create`) |
| `build-macos.yml`   | macos-latest    | `.dmg` (flutter_distributor)   |
| `build-linux.yml`   | ubuntu-latest   | `.deb` + `.AppImage` (flutter_distributor) |
| `build-all.yml`     | (호출/오케스트레이션) | 위 3개 + GitHub Release 첨부 |

각 워크플로는 LFS 체크아웃 → `flutter pub get` → codegen(`build_runner`) →
패키징 순으로 동작합니다. (플랫폼 폴더가 저장소에 커밋돼 있어 `flutter create`
단계는 제거했습니다.)

**실행 방법**

- **수동**: Actions 탭에서 원하는 워크플로 "Run workflow" → 아티팩트로 다운로드.
- **릴리스**: `v*` 태그를 푸시하면(`git tag v0.1.0 && git push origin v0.1.0`)
  `build-all` 이 3개 OS 설치본을 만들어 **GitHub Release 에 자동 첨부**합니다.

**아직 남은 것 (TODO)**

- **서명**: 현재 CI 산출물은 미서명/테스트 서명이라 SmartScreen·Gatekeeper
  경고가 뜹니다. 정식 배포하려면 인증서를 GitHub Secrets 로 넣고 워크플로에
  서명 단계를 추가하세요(Windows `.pfx`, macOS notarytool 자격증명).
- **Linux AppImage**: CI 에서 빌드합니다. `appimagetool` 이 FUSE 를 요구해
  러너에 `libfuse2` 를 설치해 둠 — 첫 실행에서 동작을 확인하세요.
- **macOS .dmg**: `dmg` 레이아웃의 `.app` 파일명/경로는 macOS 에서 첫 실행 시
  검증이 필요할 수 있습니다(`macos/packaging/dmg/make_config.yaml`).

인앱 자동 업데이트가 필요하면 [`auto_updater`](https://pub.dev/packages/auto_updater).
