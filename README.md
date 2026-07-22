# Portable Google Chrome (AppImage)

[![Release](https://img.shields.io/github/v/release/nan9nan9/portable-google-chrome?sort=semver)](https://github.com/nan9nan9/portable-google-chrome/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/nan9nan9/portable-google-chrome/total)](https://github.com/nan9nan9/portable-google-chrome/releases)
[![Platform](https://img.shields.io/badge/platform-linux--x86__64-blue)](#동작-원리)
[![glibc](https://img.shields.io/badge/glibc-%E2%89%A5%202.31%20(Debian11%2FUbuntu20.04%2FRHEL9)-green)](#동작-원리)

설치 없이 실행 가능한 `google-chrome-stable` 포터블 빌드입니다.
파일 하나(AppImage)만 복사하면 대부분의 최신 x86_64 리눅스에서 바로 실행되고,
프로필(설정·확장·로그인)은 AppImage 파일 옆 폴더에 저장되어 **함께 이동**합니다.

> [`MATE_TERMINAL_README.md`](./MATE_TERMINAL_README.md) 의 AppImage 패키징 방식을
> Chrome 특성에 맞게 재설계한 프로젝트입니다.

## 다운로드

빌드 없이 바로 쓰려면 최신 릴리스에서 AppImage를 내려받으세요:

**➡️ [최신 릴리스 다운로드](https://github.com/nan9nan9/portable-google-chrome/releases/latest)** — [`Google-Chrome-x86_64.AppImage`](https://github.com/nan9nan9/portable-google-chrome/releases/latest/download/Google-Chrome-x86_64.AppImage)

```bash
# 터미널에서 바로 받아 실행
curl -LO https://github.com/nan9nan9/portable-google-chrome/releases/latest/download/Google-Chrome-x86_64.AppImage
chmod +x Google-Chrome-x86_64.AppImage
./Google-Chrome-x86_64.AppImage
```

소스에서 직접 빌드하려면 아래 [빌드 방법](#빌드-방법)을 참고하세요.

> 📊 상단의 **Downloads** 배지는 모든 릴리스에 올라간 `Google-Chrome-x86_64.AppImage`
> 에셋의 **누적 다운로드 수**입니다. (GitHub 자동 생성 소스 zip/tar.gz 다운로드는 집계에
> 포함되지 않습니다.) `v1.0.0` 릴리스부터 집계가 시작됩니다.

## 동작 원리

- **Chrome 은 사전 빌드된 독점 바이너리**입니다. 소스 컴파일이 없으므로 Chrome 자체의
  glibc 하한은 바이너리가 결정합니다. 다만 **함께 번들하는 의존 라이브러리는 빌드
  베이스의 glibc 에 링크**되므로, 베이스가 너무 최신이면 번들 라이브러리가 호스트에 더
  높은 glibc 를 요구해 오래된 호스트에서 실행이 실패합니다. 그래서 "현재 Chrome stable 이
  여전히 실행되는 가장 낮은 배포판"인 **Debian 11(glibc 2.31)** 을 베이스로 씁니다.
  (검증: Debian 11 에서 Chrome 150 정상 실행. 하한선 glibc 2.31 → Debian 11 / Ubuntu 20.04 /
  RHEL 9(2.34) 등 폭넓게 커버) `apt` 로 `google-chrome-stable` 을 설치하면 Chrome 본체와
  모든 런타임 의존 라이브러리가 함께 들어오므로 `ldd` 로 전부 수집할 수 있습니다.
- Chrome 바이너리와 의존 라이브러리(GTK3, NSS/NSPR, glib, pango, cairo, harfbuzz 등),
  gdk-pixbuf 로더, GSettings 스키마를 하나의 AppDir 로 모아 AppImage 로 패키징합니다.
- **glibc / GL / EGL / DRM / gbm / vulkan / wayland** 등 호스트 하드웨어·드라이버·
  디스플레이 서버와 직접 통신하는 저수준 라이브러리는 **번들에서 제외**하고 호스트 것을
  사용합니다. (Chrome 디렉토리에 자체 포함된 ANGLE `libEGL`/`libGLESv2` 등은 그대로 유지)
- Chrome 은 리소스(`*.pak`, `locales/`, `icudtl.dat` 등)를 **바이너리 기준 상대경로**로
  찾으므로, 디렉토리 구조(`opt/google/chrome/`)만 유지하면 됩니다. mate-terminal 처럼
  경로를 강제로 리다이렉트하는 LD_PRELOAD 후킹이 **필요 없습니다**.
- **샌드박스**: 읽기전용 AppImage 안에서는 `chrome-sandbox` 를 SUID root 로 만들 수
  없습니다. 그래서 **사용자 네임스페이스 샌드박스**(`--disable-setuid-sandbox`)를 사용해
  보안을 유지합니다. 커널에서 사용자 네임스페이스가 비활성인 경우에만 부득이
  `--no-sandbox` 로 폴백하며, 이때 경고를 출력합니다.
- **포터블 프로필**: 실행 시 AppImage 파일이 있는 폴더에 `chrome-portable-data/` 를
  만들어 `--user-data-dir` 로 사용합니다. USB/공유폴더에 AppImage 를 두면 설정도 함께
  따라다닙니다.

## 빌드 방법

docker 또는 podman 이 설치된 x86_64 리눅스에서:

```bash
./build.sh
```

결과물: `dist/Google-Chrome-x86_64.AppImage`

## 실행 방법

대상 머신으로 파일 하나만 복사하면 됩니다.

```bash
chmod +x Google-Chrome-x86_64.AppImage
./Google-Chrome-x86_64.AppImage
```

FUSE 가 없는 환경(일부 폐쇄망/컨테이너)에서는 추출 후 실행:

```bash
./Google-Chrome-x86_64.AppImage --appimage-extract
./squashfs-root/AppRun
```

### 환경변수 / 옵션

| 항목 | 설명 |
|------|------|
| `CHROME_USER_DATA_DIR=<경로>` | 포터블 프로필 위치 변경 (기본: AppImage 옆 `chrome-portable-data/`) |
| `CHROME_NO_SANDBOX=1` | 강제로 `--no-sandbox` 실행 (보안 저하, 문제 진단용) |
| `--user-data-dir=<경로>` | 직접 지정하면 포터블 프로필 주입을 생략 (일반 Chrome 처럼 동작) |

일반 Chrome 플래그(`--incognito`, `--proxy-server=...` 등)는 그대로 전달됩니다.

## 오프라인(에어갭) 빌드

인터넷이 없는 빌드 머신에서 만들려면 두 단계로 나눕니다. Chrome·의존 라이브러리·
appimagetool 이 빌더 이미지에 구워지므로, 이미지만 옮기면 오프라인에서 빌드됩니다.

**1단계 — 온라인 머신에서 빌더 이미지 저장:**

```bash
./build-offline-save.sh
# → offline-bundle/builder-image.tar.gz 생성
```

**2단계 — `offline-bundle/` 전체를 오프라인 머신으로 복사 후 실행:**

```bash
cd offline-bundle
./build-offline-run.sh          # tar 로드 + '--network none' 으로 빌드
# → dist/Google-Chrome-x86_64.AppImage
```

## 전제 조건

- **온라인 빌드**(`build.sh`): docker 또는 podman, 인터넷 연결(Chrome·appimagetool 다운로드)
- **오프라인 빌드**: 온라인 머신에서 이미지 저장 1회 필요, 이후 빌드 머신은 인터넷 불필요
- **실행 머신**: X11 또는 Wayland(XWayland 포함) 세션. Chrome 이 요구하는 glibc 이상
  (일반적으로 최근 몇 년 내 배포판이면 충족)

## 파일 구성

| 파일 | 설명 |
|------|------|
| `Dockerfile` | Debian 11(glibc 2.31) 기반 빌드 환경 (Chrome + 의존성 + appimagetool 포함) |
| `build.sh` | (온라인) 이미지 빌드 + 컨테이너 실행 오케스트레이터 |
| `build-offline-save.sh` | (온라인) 빌더 이미지를 tar 로 저장 |
| `build-offline-run.sh` | (오프라인) tar 로드 후 네트워크 차단 빌드 |
| `scripts/build-in-container.sh` | 컨테이너 내부에서 AppDir 구성 및 패키징 |

## 알려진 제약 / 참고

- GUI 앱이므로 헤드리스(디스플레이 없는) 서버에서는 X 포워딩 등이 필요합니다.
- Chrome 버전은 빌드 시점의 최신 stable 이 설치됩니다. 특정 버전이 필요하면
  `Dockerfile` 의 `apt-get install google-chrome-stable` 을
  `google-chrome-stable=<버전>` 으로 고정하세요.
- 사용자 네임스페이스가 막힌 커널(일부 강화 배포판)에서는 자동으로 `--no-sandbox`
  폴백이 적용되며 보안이 약해집니다. 가능하면
  `sysctl kernel.unprivileged_userns_clone=1` 로 네임스페이스를 허용하세요.
- 번역/로케일은 Chrome 패키지에 이미 포함되어 있어 별도 처리하지 않습니다.
