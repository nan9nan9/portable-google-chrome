# Portable Google Chrome (AppImage)

[![Release](https://img.shields.io/github/v/release/nan9nan9/portable-google-chrome?sort=semver)](https://github.com/nan9nan9/portable-google-chrome/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/nan9nan9/portable-google-chrome/total)](https://github.com/nan9nan9/portable-google-chrome/releases)
[![Platform](https://img.shields.io/badge/platform-linux--x86__64-blue)](#동작-원리)
[![glibc](https://img.shields.io/badge/glibc-%E2%89%A5%202.28%20(RHEL8%2FCentOS8%2FDebian10)-green)](#동작-원리)

설치 없이 실행 가능한 `google-chrome-stable` 포터블 빌드입니다.
파일 하나(AppImage)만 복사하면 대부분의 최신 x86_64 리눅스에서 바로 실행됩니다.
프로필(설정·확장·로그인)은 기본적으로 **사용자 홈 `~/.config/portable-chrome`** 에 저장되어
계정별로 독립적입니다. (AppImage 파일 옆에 두어 함께 이동시키려면 `CHROME_DATA_IN_HOME=0`)

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

- **Chrome 은 사전 빌드된 독점 바이너리**입니다. Chrome 자체의 glibc 요구는 바이너리가
  결정하며, 실측 결과 **Chrome 150 바이너리는 최대 GLIBC_2.25 만 요구**합니다. 반면
  **함께 번들하는 의존 라이브러리는 빌드 베이스의 glibc 에 링크**되므로, 베이스가 너무
  최신이면 번들 라이브러리가 호스트에 더 높은 glibc 를 요구해 오래된 호스트에서 실행이
  실패합니다. 그래서 하한선을 낮추려면 **베이스 자체를 낮춰야** 합니다. 이 프로젝트는
  **Debian 10(buster, glibc 2.28)** 을 베이스로 써서 번들 라이브러리 요구를 **≤ 2.28** 로
  맞춥니다. (검증: 번들 전체 최대 GLIBC 심볼 2.28, buster 에서 Chrome 150 렌더링 정상.
  하한선 glibc 2.28 → RHEL 8 / CentOS 8 / Debian 10 / Ubuntu 20.04+ 등 커버)
  buster 는 EOL 이라 `Dockerfile` 에서 apt 소스를 `archive.debian.org` 로 교체합니다.
  `apt` 로 `google-chrome-stable` 을 설치하면 Chrome 본체와 모든 런타임 의존 라이브러리가
  함께 들어오므로 `ldd` 로 전부 수집할 수 있습니다.
- Chrome 바이너리와 의존 라이브러리(GTK3, NSS/NSPR, glib, pango, cairo, harfbuzz 등),
  gdk-pixbuf 로더, GSettings 스키마를 하나의 AppDir 로 모아 AppImage 로 패키징합니다.
- **glibc / GL / EGL / DRM / gbm / vulkan / wayland** 등 호스트 하드웨어·드라이버·
  디스플레이 서버와 직접 통신하는 저수준 라이브러리는 **번들에서 제외**하고 호스트 것을
  사용합니다. (Chrome 디렉토리에 자체 포함된 ANGLE `libEGL`/`libGLESv2` 등은 그대로 유지)
- Chrome 은 리소스(`*.pak`, `locales/`, `icudtl.dat` 등)를 **바이너리 기준 상대경로**로
  찾으므로, 디렉토리 구조(`opt/google/chrome/`)만 유지하면 됩니다. mate-terminal 처럼
  경로를 강제로 리다이렉트하는 LD_PRELOAD 후킹이 **필요 없습니다**.
- **샌드박스**: 읽기전용 AppImage 안에서는 `chrome-sandbox` 를 SUID root 로 만들 수
  없습니다. 다행히 최신 Chrome 은 **사용자 네임스페이스**가 있으면 별도 플래그 없이도
  네임스페이스 샌드박스를 자동 사용합니다. 그래서 **샌드박스 관련 플래그를 아무것도 넣지
  않아** 보안(샌드박스 ON)을 유지하면서 화면 상단의 `"unsupported command-line flag:
  --disable-setuid-sandbox"` 경고 인포바도 뜨지 않습니다. 커널에서 네임스페이스가 비활성인
  경우에만 부득이 `--no-sandbox` 로 폴백하며, 이때 뜨는 경고 인포바는 `--test-type` 으로
  억제합니다(샌드박스가 꺼지므로 보안 저하, 경고 메시지도 stderr 로 출력).
- **프로필 위치**: 기본은 **사용자 홈 `~/.config/portable-chrome`**(계정별 독립). 공유
  드라이브에 AppImage 하나만 두고 여러 명이 써도 프로필이 충돌하지 않습니다. AppImage 파일과
  함께 이동하는 포터블 방식을 원하면 `CHROME_DATA_IN_HOME=0`(→ AppImage 옆 `chrome-portable-data/`),
  경로를 직접 지정하려면 `CHROME_USER_DATA_DIR=<경로>`.
- **방해 요소 제거(기본값)**: 포터블 환경에 맞게 아래를 기본으로 끕니다.
  - **시스템 키링 잠금해제 팝업** — 비밀번호/쿠키 암호화를 OS 키링(GNOME Keyring/KWallet)
    대신 프로필 내부 `basic` 저장소로 처리(`--password-store=basic`). "Unlock Login Keyring"
    창이 뜨지 않고, 데이터가 프로필과 함께 이동합니다. (보안 트레이드오프: OS 키링보다
    약한 난독화 저장. 시스템 키링을 쓰려면 `CHROME_USE_KEYRING=1`)
  - **첫 실행 안내 / 기본 브라우저 설정 배너 / 사용 통계 프롬프트** — `--no-first-run`,
    `--no-default-browser-check` 및 바이너리 옆 `initial_preferences`(기본 브라우저 설정 안 함,
    사용 통계 보고 비활성)로 억제. (원래 프롬프트를 보려면 `CHROME_SHOW_PROMPTS=1`)
  - **GPU/GL 초기화 에러** — 포터블 실행 환경(헤드리스·VM·원격·일부 WSL 등)에는 동작하는
    GL 드라이버가 없어 `libGL error: ... swrast`, `ANGLE ... Could not create a backing OpenGL
    context`, `eglInitialize ... failed` 같은 에러가 쏟아집니다. Chrome 에 **번들된
    SwiftShader(소프트웨어 GL)**를 기본 사용(`--use-angle=swiftshader`)해 호스트 드라이버에
    의존하지 않고 조용히 렌더링합니다. (WebGL 소프트웨어 폴백은 Chrome 이 "unsafe" 경고
    인포바를 띄우는 `--enable-unsafe-swiftshader` 가 필요해 기본에서 제외 — WebGL/하드웨어
    가속이 필요하면 `CHROME_ENABLE_GPU=1`) GPU 를 완전히 끄려면 `CHROME_DISABLE_GPU=1`.
  - **AI Mode** — 주소창/새 탭의 "AI Mode" 진입점(버튼·제안·스타터팩·사인인 프로모)을
    `--disable-features`(AiModeOmniboxEntryPoint 등, 이 Chrome 바이너리에서 실제 추출한
    feature 이름)로 끕니다. AI Mode 를 쓰려면 `CHROME_ENABLE_AI=1`.
  - **무해한 잡음 로그** — 기능과 무관하지만 일부 환경에서 나오는 로그(UPower dbus 에러,
    GCM `DEPRECATED_ENDPOINT`, 새 탭 `incorrect profile type`, mojo `rejected by interface
    blink.mojom.*`)를 끄는 Chrome 플래그가 없어, AppRun 이 stderr 에서 해당 라인만 정확히
    필터링합니다. 다른 로그는 그대로 보입니다. (원본을 보려면 `CHROME_QUIET=0`)

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
| `CHROME_USER_DATA_DIR=<경로>` | 프로필 위치 직접 지정 (최우선) |
| `CHROME_DATA_IN_HOME=0` | 프로필을 홈 대신 **AppImage 옆 `chrome-portable-data/`** 에 저장(파일과 함께 이동). 기본값은 홈(`~/.config/portable-chrome`) |
| `CHROME_CA_DIR=<디렉토리>` | CA 자동 등록 폴더 지정 (기본: AppImage 옆 `ca-certs/`) |
| `CHROME_USE_KEYRING=1` | 프로필 내부 저장소 대신 시스템 키링(GNOME Keyring/KWallet) 사용 |
| `CHROME_SHOW_PROMPTS=1` | 첫 실행 안내·기본 브라우저 설정 프롬프트 억제 해제 |
| `CHROME_ENABLE_GPU=1` | 소프트웨어 GL(SwiftShader) 대신 호스트 하드웨어 GPU 사용 |
| `CHROME_DISABLE_GPU=1` | GPU 완전 비활성(`--disable-gpu`, 가장 가벼움 / WebGL 꺼짐) |
| `CHROME_IMPORT_FIREFOX_CA=auto` | Firefox 신뢰 저장소(cert9.db)의 CA 를 자동으로 가져와 신뢰 (아래 참고) |
| `CHROME_EXTRA_CA=<파일\|디렉토리>` | 사내/사설 루트 CA(PEM)를 포터블 프로필에 등록해 신뢰 (아래 참고) |
| `CHROME_ENABLE_AI=1` | 기본으로 끄는 "AI Mode"(주소창/새 탭 진입점)를 끄지 않고 노출 |
| `CHROME_QUIET=0` | 무해한 잡음 로그(UPower/GCM/NTP/mojo) 필터를 끄고 원본 로그 그대로 출력 |
| `CHROME_NO_SANDBOX=1` | 강제로 `--no-sandbox` 실행 (보안 저하, 문제 진단용) |
| `--user-data-dir=<경로>` | 직접 지정하면 포터블 프로필 주입을 생략 (일반 Chrome 처럼 동작) |

> 위 방해 요소 억제 플래그(`--password-store`, `--no-first-run`, `--no-default-browser-check`)는
> 사용자가 같은 플래그를 직접 넘기면 중복 주입하지 않고 사용자 값을 존중합니다.

일반 Chrome 플래그(`--incognito`, `--proxy-server=...` 등)는 그대로 전달됩니다.

### 사내/사설 CA 로 인한 인증서 오류(`net_error -202`) 해결

회사·학교 네트워크가 보안 프록시로 HTTPS 를 가로채 **사내 사설 CA 로 재서명**하는 경우,
Chrome 은 그 CA 를 신뢰하지 않아 모든/일부 HTTPS 에서
`ERR_CERT_AUTHORITY_INVALID`(`handshake failed ... net_error -202`)가 납니다.
Firefox 는 자체 CA 저장소를 써서 통과하지만, Chrome 은 시스템/사용자 신뢰 저장소를 봅니다.

번들된 `certutil` 이 사내 CA 를 **포터블 프로필 내부 NSS DB** 에 등록해 Chrome 이 신뢰하게
합니다. (등록 정보가 프로필과 함께 이동) 두 가지 방법이 있습니다.

**방법 A — Firefox 설정을 그대로 참고 (가장 간단, Firefox 는 되는데 Chrome 만 안 될 때):**
Firefox 의 신뢰 저장소(`cert9.db`)에서 CA 를 자동으로 가져옵니다. 별도 파일 준비가 필요 없습니다.

```bash
CHROME_IMPORT_FIREFOX_CA=auto ./Google-Chrome-x86_64.AppImage
# 프로필 위치를 직접 지정할 수도 있음:
CHROME_IMPORT_FIREFOX_CA="$HOME/.mozilla/firefox/xxxx.default-release" ./Google-Chrome-x86_64.AppImage
```

`auto` 는 `~/.mozilla/firefox`, snap/flatpak Firefox 경로를 뒤져 SSL 로 신뢰된 CA 를 모두
가져옵니다. 실행 시 `portable-chrome: Firefox CA 등록 → <이름>` 로그가 뜨면 성공입니다.
(참고: Firefox 가 사내 CA 를 OS "엔터프라이즈 루트"에서만 읽고 자체 저장소에 없으면 이 방법으로는
안 잡힙니다 — 이때는 방법 B 를 쓰세요.)

**방법 B — CA 파일(PEM)을 직접 지정:**

```bash
# 파일 하나 지정 (PEM)
CHROME_EXTRA_CA=/path/to/corp-root-ca.pem ./Google-Chrome-x86_64.AppImage
# 여러 개면 디렉토리 지정 (*.pem / *.crt / *.cer 자동 등록)
CHROME_EXTRA_CA=/path/to/ca-dir ./Google-Chrome-x86_64.AppImage
```

**CA 파일 구하는 법** — IT 부서에서 받거나, Firefox 에서 내보내기:
Firefox → 설정 → 개인정보 및 보안 → 인증서 → **인증서 보기** → **인증기관(Authorities)** 탭 →
사내 CA 선택 → **내보내기** → `.pem`(또는 `.crt`) 저장.

두 방법 모두 한 번 등록되면 프로필(`chrome-portable-data/`)에 남아, 다음부터는 환경변수 없이
실행해도 계속 신뢰됩니다.

**방법 C — CA 폴더 자동 등록 (env 불필요, 다인원 배포에 적합):**
AppImage 옆에 **`ca-certs/`** 폴더를 만들고 사내 CA 파일을 넣어두면, 실행할 때마다 자동으로
등록됩니다. 환경변수가 필요 없습니다.

```
Google-Chrome-x86_64.AppImage
ca-certs/            ← 이 폴더에 사내 CA 를 넣어두면 자동 등록
  ├─ corp-root.crt
  └─ corp-inter.crt
```
(경로를 바꾸려면 `CHROME_CA_DIR=<폴더>`)

**지원 형식:** PEM, **DER(바이너리 `.crt`/`.cer`/`.der`)**, 여러 인증서가 든 **번들 PEM**(자동 분할),
`-----BEGIN` 앞에 잡텍스트(`Bag Attributes` 등)가 있는 PEM 모두 자동 처리합니다. 실행 시 stderr 에
`portable-chrome: CA 등록 → <이름>` 과 `... CA 등록 누계 = N` 이 찍히니 N 이 1 이상인지 확인하세요.
등록 실패 시 `CA 등록 실패 → ... : <원인>` 으로 certutil 오류를 그대로 보여줍니다.

### 사내 다인원 배포 (CA 공유 + 프로필은 사용자별)

**기본값이 이 구성입니다** — CA 는 공유 경로에서 자동으로, 프로필은 각 사용자 홈에 독립 저장:
1. `ca-certs/` 에 사내 CA 를 넣어 AppImage 와 함께 (공유 드라이브 등에) 배포
2. 사용자는 그냥 실행 → 프로필이 각자 `~/.config/portable-chrome` 에 생성되고,
   `ca-certs/` 의 CA 는 각자 프로필에 자동 등록됨 (환경변수 불필요)

```bash
./Google-Chrome-x86_64.AppImage      # 프로필: ~/.config/portable-chrome (계정별 독립)
```

- 공유 드라이브에 AppImage 하나만 둬도 사용자별 프로필이라 **충돌·프라이버시 문제가 없습니다.**
- 반대로 AppImage 파일과 프로필을 **함께 이동**시키는 포터블 방식이 필요하면
  `CHROME_DATA_IN_HOME=0` (→ AppImage 옆 `chrome-portable-data/`).
- 간단히는, CA 까지 등록해둔 `chrome-portable-data/` 를 AppImage 와 함께 **각 사용자 폴더로 복사**해도
  됩니다(각자 독립 프로필 + CA 포함).

> 예전 버전에서 CA 등록이 실패했었다면 프로필의 `chrome-portable-data/.pki` 를 한 번 지우고
> 다시 시도하세요(손상된 항목 제거).

> 참고: 특정 사이트에서만 -202 가 나고 발급 기관이 Entrust 등 정상 CA 라면, Chrome 이
> 해당 CA 를 정책적으로 불신하는 경우로 정품 Chrome 도 동일하게 거부합니다(사내 CA 문제 아님).

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
| `Dockerfile` | Debian 10(buster, glibc 2.28) 기반 빌드 환경 (Chrome + 의존성 + appimagetool 포함) |
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
