# Portable MATE Terminal (AppImage)

[![Release](https://img.shields.io/github/v/release/nan9nan9/portable-mate-terminal?sort=semver)](https://github.com/nan9nan9/portable-mate-terminal/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/nan9nan9/portable-mate-terminal/total)](https://github.com/nan9nan9/portable-mate-terminal/releases)
[![Platform](https://img.shields.io/badge/platform-linux--x86__64-blue)](#동작-원리)
[![glibc](https://img.shields.io/badge/glibc-%E2%89%A5%202.17%20(RHEL7%2B)-green)](#동작-원리)

RHEL 7/8/9, CentOS, Ubuntu 등 대부분의 x86_64 리눅스에서 설치 없이 실행 가능한
`mate-terminal` 포터블 빌드입니다.

## 다운로드

빌드 없이 바로 쓰려면 최신 릴리스에서 AppImage를 내려받으세요:

**➡️ [최신 릴리스 다운로드](https://github.com/nan9nan9/portable-mate-terminal/releases/latest)** — [`MATE-Terminal-x86_64.AppImage`](https://github.com/nan9nan9/portable-mate-terminal/releases/latest/download/MATE-Terminal-x86_64.AppImage)

```bash
# 터미널에서 바로 받아 실행
curl -LO https://github.com/nan9nan9/portable-mate-terminal/releases/latest/download/MATE-Terminal-x86_64.AppImage
chmod +x MATE-Terminal-x86_64.AppImage
./MATE-Terminal-x86_64.AppImage
```

소스에서 직접 빌드하려면 아래 [빌드 방법](#빌드-방법)을 참고하세요.

## 동작 원리

- **CentOS 7(glibc 2.17)** 컨테이너에서 빌드합니다. glibc는 하위호환이므로
  가장 낮은 환경에서 빌드하면 RHEL 8/9, 최신 우분투(glibc 2.27+)에서도 실행됩니다.
  (번들 전체의 최대 glibc 요구 버전이 **GLIBC_2.17**로, RHEL7 이상이면 동작)
- `mate-terminal` 바이너리와 의존 라이브러리(GTK3, VTE, glib, pango, cairo 등),
  GTK 모듈, gdk-pixbuf 로더, gio 모듈, GSettings 스키마를 하나의 AppDir로 모아 AppImage로 패키징합니다.
- glibc / GL / DRM / X11 등 **호스트 하드웨어·X서버와 직접 통신하는 저수준 라이브러리는
  번들에서 제외**하고 호스트 것을 사용합니다.
- mate-terminal 은 `terminal.xml`(메뉴 UI) 등을 컴파일 타임 경로(`/usr/share/mate-terminal`)에서
  찾으며 환경변수로 못 바꾸므로, **경량 LD_PRELOAD 인터포저(`libpathhook.so`)** 로 해당 경로만
  AppDir 내부로 리다이렉트합니다. (자식 프로세스/사용자 명령에는 영향 없음)
- gdk-pixbuf/GTK 입력기 모듈 캐시는 빌드 시 토큰(`@@APPDIR@@`)으로 생성한 뒤
  실행 시점의 실제 마운트 경로로 치환합니다.
- **자식 프로세스 환경 격리**: 터미널 안에서 실행하는 셸·명령이 번들된 구버전
  라이브러리를 잘못 로드하지 않도록, `libpathhook.so` 가 `exec` 계열을 후킹해
  AppImage 가 주입한 환경변수(`LD_LIBRARY_PATH`, `LD_PRELOAD`, `GTK_PATH`,
  `GIO_MODULE_DIR` 등)를 제거하고 사용자의 원래 값으로 복원합니다.
  (mate-terminal 자신과 새 창은 번들 환경을 유지)

## 검증 상태

- 빌드: CentOS 7 컨테이너(podman/docker)
- 실행 검증: **Ubuntu 22.04(glibc 2.35)에서 GUI 창 + 터미널 내부 명령 실행 정상**,
  UI/pixbuf/desktop/GSettings 경고 없음 확인.
- 자식 환경 격리 검증: 터미널 안 셸이 AppImage 환경변수를 상속하지 않고,
  사용자의 원래 `LD_LIBRARY_PATH` 가 복원됨을 확인.
- 미검증: 실제 RHEL 7/8/9 환경(설계상 glibc 2.17 기준으로 동작하나 실기 확인 권장).

## 빌드 방법

도커가 설치된 x86_64 리눅스에서:

```bash
./build.sh
```

결과물: `dist/MATE-Terminal-x86_64.AppImage`

## 실행 방법

대상 서버로 파일 하나만 복사하면 됩니다.

```bash
chmod +x MATE-Terminal-x86_64.AppImage
./MATE-Terminal-x86_64.AppImage
```

FUSE가 없는 환경(일부 폐쇄망/컨테이너)에서는 추출 후 실행:

```bash
./MATE-Terminal-x86_64.AppImage --appimage-extract
./squashfs-root/AppRun
```

## 오프라인(에어갭) 빌드

인터넷이 없는 빌드 머신에서 만들려면 두 단계로 나눕니다. 모든 패키지와 appimagetool 이
빌더 이미지에 구워지므로, 이미지만 옮기면 오프라인에서 네트워크 없이 빌드됩니다.

**1단계 — 온라인 머신에서 빌더 이미지 저장:**

```bash
./build-offline-save.sh
# → offline-bundle/builder-image.tar.gz (약 190MB) 생성
```

**2단계 — `offline-bundle/` 전체를 오프라인 머신으로 복사 후 실행:**

```bash
cd offline-bundle
./build-offline-run.sh          # tar 로드 + '--network none' 으로 빌드
# → dist/MATE-Terminal-x86_64.AppImage
```

> 검증됨: 로컬 이미지를 삭제한 뒤 tar 에서 로드해 `--network none` 상태로 빌드 성공.
> 온라인/오프라인 머신은 같은 런타임(docker↔docker 또는 podman↔podman) 사용을 권장합니다.

## 전제 조건

- **온라인 빌드**(`build.sh`): docker 또는 podman, 인터넷 연결(EPEL 패키지·appimagetool 다운로드)
- **오프라인 빌드**: 온라인 머신에서 이미지 저장 1회 필요, 이후 빌드 머신은 인터넷 불필요
- **실행 머신**: X11 또는 XWayland 세션(GUI 앱이므로 디스플레이 필요)

## 파일 구성

| 파일 | 설명 |
|------|------|
| `Dockerfile` | CentOS 7 기반 빌드 환경 |
| `build.sh` | (온라인) 이미지 빌드 + 컨테이너 실행 오케스트레이터 |
| `build-offline-save.sh` | (온라인) 빌더 이미지를 tar 로 저장 |
| `build-offline-run.sh` | (오프라인) tar 로드 후 네트워크 차단 빌드 |
| `scripts/build-in-container.sh` | 컨테이너 내부에서 AppDir 구성 및 패키징 |

## 알려진 제약 / 참고

- GUI 앱이므로 헤드리스(디스플레이 없는) 서버에서는 X 포워딩 등이 필요합니다.
- 팩토리(D-Bus) 충돌 방지를 위해 `--disable-factory` 를 지원하면 자동 적용합니다.
- 번역(.mo)은 용량을 위해 기본 제외했습니다. 필요하면
  `build-in-container.sh` 에서 `/usr/share/locale` 복사를 추가하세요.
- 특정 mate-terminal 버전이 필요하면 `Dockerfile` 의 `yum install` 에 버전을 지정하세요.
