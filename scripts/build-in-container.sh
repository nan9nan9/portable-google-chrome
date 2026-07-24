#!/usr/bin/env bash
# 컨테이너 내부에서 실행됩니다.
# 설치된 google-chrome-stable 과 그 의존 라이브러리를 하나의 AppDir 로 모아
# AppImage 로 패키징합니다.
set -euo pipefail

# ── 경로 정의 ────────────────────────────────────────────────────────────
APPDIR=/work/AppDir
OUTDIR=/work/dist
OUTNAME="Google-Chrome-x86_64.AppImage"
CHROME_SRC=/opt/google/chrome          # apt 가 설치하는 Chrome 실제 경로
TOOLS=/opt/tools
LIBARCH=/usr/lib/x86_64-linux-gnu

echo "==> AppDir 초기화"
rm -rf "$APPDIR"
mkdir -p "$APPDIR/opt/google/chrome" "$APPDIR/usr/lib" \
         "$APPDIR/usr/lib/gdk-pixbuf-2.0" "$APPDIR/usr/share/glib-2.0/schemas"
mkdir -p "$OUTDIR"

# ── 1) Chrome 본체 복사 (리소스 상대경로 유지가 핵심) ─────────────────────
echo "==> Chrome 본체 복사"
cp -a "$CHROME_SRC/." "$APPDIR/opt/google/chrome/"

CHROME_BIN="$APPDIR/opt/google/chrome/chrome"
CHROME_VER="$("$CHROME_SRC/chrome" --version 2>/dev/null | awk '{print $NF}' || echo unknown)"
echo "    Chrome 버전: $CHROME_VER"

# ── 2) 의존 라이브러리 수집 ───────────────────────────────────────────────
# 원칙: glibc / GL / EGL / DRM / gbm / vulkan / wayland 등 호스트 하드웨어·드라이버·
# 디스플레이 서버와 직접 통신하는 저수준 라이브러리는 번들에서 제외하고 호스트 것을 사용.
# (Chrome 디렉토리에 이미 들어있는 자체 libEGL/libGLESv2(ANGLE) 등은 그대로 유지)
# 종결자를 [-._] 로 둬야 libwayland-client / libdrm_amdgpu / libGLX_mesa 같은
# 접미사 변형까지 제외된다. (\. 로 끝내면 정확히 그 이름+"." 만 매칭해 변형을 놓침)
EXCLUDE_RE='^(ld-linux-x86-64|libc|libm|libdl|libpthread|librt|libresolv|libutil|libnsl|libanl|libBrokenLocale|libGL|libGLX|libGLdispatch|libOpenGL|libEGL|libGLESv2|libglapi|libgbm|libdrm|libvulkan|libwayland)[-._]'

echo "==> 의존성 목록 산출 (ldd 전이 폐쇄)"
# ldd 는 전이 의존성을 평탄화해 모두 보여주므로 시드별 1회 호출로 충분하다.
# GTK(파일 대화상자 등)는 Chrome 이 dlopen 하므로 ldd 로는 안 잡힌다 → 시드에 명시 추가.
SEEDS=("$CHROME_BIN")
while IFS= read -r so; do SEEDS+=("$so"); done < <(find "$APPDIR/opt/google/chrome" -name '*.so' -o -name '*.so.*')
for gtk in "$LIBARCH/libgtk-3.so.0" "$LIBARCH/libgtk-4.so.1"; do
    [ -e "$gtk" ] && SEEDS+=("$gtk")
done

# Chrome 자체 SONAME 이 해석되도록 chrome 디렉토리를 검색경로에 포함
export LD_LIBRARY_PATH="$APPDIR/opt/google/chrome:${LD_LIBRARY_PATH:-}"

: > /tmp/alllibs
for s in "${SEEDS[@]}"; do
    ldd "$s" 2>/dev/null || true
done | awk '/=> \// {print $3}' | sort -u > /tmp/alllibs

echo "==> 라이브러리 복사 (제외 규칙 적용)"
copied=0; skipped=0
while IFS= read -r lib; do
    [ -e "$lib" ] || continue
    base="$(basename "$lib")"
    # 저수준/하드웨어 라이브러리는 호스트 것 사용
    if echo "$base" | grep -Eq "$EXCLUDE_RE"; then skipped=$((skipped+1)); continue; fi
    # 이미 Chrome 디렉토리에 존재하는 것은 건너뜀 (자체 번들 우선)
    case "$lib" in "$APPDIR/opt/google/chrome/"*) continue;; esac
    # -L: 심볼릭 링크의 실제 내용을 복사하되 이름은 SONAME(링크명) 유지
    cp -Lf "$lib" "$APPDIR/usr/lib/$base" 2>/dev/null && copied=$((copied+1)) || true
done < /tmp/alllibs
echo "    복사 $copied 개 / 제외 $skipped 개"

# ── 2.5) NSS 런타임 모듈 (libnss3 이 dlopen 하므로 ldd 로는 안 잡힘) ────────
# 누락 시 "libsoftokn3.so: cannot open" → NSS 초기화 FATAL 로 Chrome 이 죽는다.
echo "==> NSS 런타임 모듈 번들"
for pat in libsoftokn3 libfreebl3 libfreeblpriv3 libnssckbi libnssdbm3 libnsssysinit libplds4 libplc4; do
    while IFS= read -r m; do
        [ -e "$m" ] || continue
        cp -Lf "$m" "$APPDIR/usr/lib/$(basename "$m")" 2>/dev/null || true
        # 모듈 자신의 의존성도 수집
        ldd "$m" 2>/dev/null | awk '/=> \// {print $3}' | while IFS= read -r d; do
            b="$(basename "$d")"
            echo "$b" | grep -Eq "$EXCLUDE_RE" && continue
            [ -e "$d" ] && cp -Lf "$d" "$APPDIR/usr/lib/$b" 2>/dev/null || true
        done
    done < <(find "$LIBARCH" /usr/lib -maxdepth 3 -name "${pat}.so" 2>/dev/null)
done

# ── 2.6) certutil 번들 (사내/사설 CA 를 프로필 NSS DB 에 등록하는 데 사용) ──
# 사내 MITM 프록시의 사설 루트 CA 를 신뢰시키려면 NSS DB 에 등록해야 하는데,
# air-gap 환경엔 certutil 이 없을 수 있으므로 함께 번들한다. (의존 라이브러리는 이미 수집됨)
echo "==> certutil 번들"
mkdir -p "$APPDIR/usr/bin"
CERTUTIL_SRC="$(command -v certutil || true)"
if [ -n "$CERTUTIL_SRC" ]; then
    cp -Lf "$CERTUTIL_SRC" "$APPDIR/usr/bin/certutil"
    # certutil 의존성 중 미수집분 보강
    ldd "$CERTUTIL_SRC" 2>/dev/null | awk '/=> \// {print $3}' | while IFS= read -r d; do
        b="$(basename "$d")"
        echo "$b" | grep -Eq "$EXCLUDE_RE" && continue
        [ -e "$d" ] && cp -Lf "$d" "$APPDIR/usr/lib/$b" 2>/dev/null || true
    done
    echo "    certutil 포함"
else
    echo "    (certutil 미발견 — CHROME_EXTRA_CA 기능 비활성)"
fi

# ── 3) gdk-pixbuf 로더 (GTK 파일 대화상자의 아이콘/이미지 렌더링) ──────────
# 로더 모듈을 복사하고 캐시를 @@APPDIR@@ 토큰으로 생성 → 실행 시 실제 경로로 치환.
echo "==> gdk-pixbuf 로더 번들"
PIXBUF_SRC="$(find "$LIBARCH" -maxdepth 1 -type d -name 'gdk-pixbuf-2.0' | head -1)"
QUERY_LOADERS="$(find "$LIBARCH/gdk-pixbuf-2.0" -name 'gdk-pixbuf-query-loaders' 2>/dev/null | head -1 || true)"
if [ -n "$PIXBUF_SRC" ] && [ -n "$QUERY_LOADERS" ]; then
    LOADERS_SUBDIR="$(find "$PIXBUF_SRC" -type d -name 'loaders' | head -1)"
    DEST_VER_DIR="$APPDIR/usr/lib/gdk-pixbuf-2.0/$(basename "$(dirname "$LOADERS_SUBDIR")")"
    mkdir -p "$DEST_VER_DIR/loaders"
    cp -a "$LOADERS_SUBDIR/." "$DEST_VER_DIR/loaders/"
    # 로더가 의존하는 라이브러리도 usr/lib 로 수집
    while IFS= read -r lib; do
        [ -e "$lib" ] || continue
        base="$(basename "$lib")"
        echo "$base" | grep -Eq "$EXCLUDE_RE" && continue
        cp -Lf "$lib" "$APPDIR/usr/lib/$base" 2>/dev/null || true
    done < <(find "$DEST_VER_DIR/loaders" -name '*.so' -exec ldd {} \; 2>/dev/null | awk '/=> \// {print $3}' | sort -u)
    # 캐시 생성 후 절대경로를 토큰으로 치환
    GDK_PIXBUF_MODULEDIR="$DEST_VER_DIR/loaders" "$QUERY_LOADERS" 2>/dev/null \
        | sed "s|$APPDIR|@@APPDIR@@|g" > "$APPDIR/usr/lib/gdk-pixbuf-2.0/loaders.cache" || true
    echo "    로더 캐시 생성 완료"
else
    echo "    (gdk-pixbuf 로더 미발견 — 건너뜀)"
fi

# ── 4) GSettings 스키마 (GTK 대화상자 경고 방지) ──────────────────────────
echo "==> GSettings 스키마 컴파일"
if [ -d /usr/share/glib-2.0/schemas ]; then
    cp -a /usr/share/glib-2.0/schemas/*.xml "$APPDIR/usr/share/glib-2.0/schemas/" 2>/dev/null || true
    cp -a /usr/share/glib-2.0/schemas/*.gschema.override "$APPDIR/usr/share/glib-2.0/schemas/" 2>/dev/null || true
    glib-compile-schemas "$APPDIR/usr/share/glib-2.0/schemas" 2>/dev/null || true
fi

# ── 5) 아이콘 / desktop 파일 ──────────────────────────────────────────────
echo "==> desktop / 아이콘 구성"
ICON_SRC="$(ls "$CHROME_SRC"/product_logo_256.png "$CHROME_SRC"/product_logo_*.png 2>/dev/null | head -1 || true)"
if [ -n "$ICON_SRC" ]; then
    cp "$ICON_SRC" "$APPDIR/google-chrome.png"
else
    # 최소한의 빈 아이콘 fallback (appimagetool 은 아이콘을 요구)
    touch "$APPDIR/google-chrome.png"
fi

cat > "$APPDIR/google-chrome.desktop" <<'EOF'
[Desktop Entry]
Version=1.0
Name=Google Chrome (Portable)
GenericName=Web Browser
Comment=포터블 형태로 패키징된 Google Chrome
Exec=AppRun %U
Terminal=false
Icon=google-chrome
Type=Application
Categories=Network;WebBrowser;
MimeType=text/html;text/xml;application/xhtml+xml;x-scheme-handler/http;x-scheme-handler/https;
StartupNotify=true
EOF

# ── 5.5) initial_preferences: 새 프로필 생성 시 기본값 시드 ────────────────
# Chrome 은 바이너리 옆의 initial_preferences 를 새 프로필 초기값으로 읽는다.
# 기본 브라우저 설정 안 함 / 기본 브라우저 확인 안 함 / 사용 통계 보고 비활성.
echo "==> initial_preferences 작성"
cat > "$APPDIR/opt/google/chrome/initial_preferences" <<'PREF'
{
  "distribution": {
    "make_chrome_default": false,
    "make_chrome_default_for_user": false,
    "suppress_first_run_default_browser_prompt": true,
    "do_not_create_desktop_shortcut": true,
    "do_not_create_quick_launch_shortcut": true,
    "do_not_register_for_update_launch": true
  },
  "browser": {
    "check_default_browser": false
  },
  "metrics_reporting_enabled": false
}
PREF

# ── 6) AppRun 작성 ────────────────────────────────────────────────────────
echo "==> AppRun 작성"
cat > "$APPDIR/AppRun" <<'APPRUN'
#!/bin/bash
# Portable Google Chrome — AppRun
# 번들 라이브러리 경로 설정 + 포터블 프로필 + 샌드박스 자동 선택 후 chrome 실행.
set -e
HERE="$(dirname "$(readlink -f "$0")")"
CHROME="$HERE/opt/google/chrome/chrome"

# 번들 라이브러리 우선 (호스트 저수준 라이브러리는 뒤쪽 기본 경로에서 해석)
export LD_LIBRARY_PATH="$HERE/usr/lib:$HERE/opt/google/chrome${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export GSETTINGS_SCHEMA_DIR="$HERE/usr/share/glib-2.0/schemas${GSETTINGS_SCHEMA_DIR:+:$GSETTINGS_SCHEMA_DIR}"

# gdk-pixbuf 캐시: 빌드 시 심은 @@APPDIR@@ 토큰을 실제 경로로 치환한 사본을 사용
PIXBUF_CACHE="$HERE/usr/lib/gdk-pixbuf-2.0/loaders.cache"
if [ -f "$PIXBUF_CACHE" ]; then
    RT="${TMPDIR:-/tmp}/portable-chrome-$$"
    mkdir -p "$RT"
    sed "s|@@APPDIR@@|$HERE|g" "$PIXBUF_CACHE" > "$RT/loaders.cache"
    export GDK_PIXBUF_MODULE_FILE="$RT/loaders.cache"
    trap 'rm -rf "$RT"' EXIT
fi

# ── 포터블 프로필: AppImage 파일과 같은 폴더에 데이터를 두어 함께 이동 ──────
if [ -n "${APPIMAGE:-}" ]; then
    BASE_DIR="$(dirname "$APPIMAGE")"
else
    BASE_DIR="$HERE"          # 추출(extract) 실행 시엔 AppDir 기준
fi
DATA_DIR="${CHROME_USER_DATA_DIR:-$BASE_DIR/chrome-portable-data}"

# ── 사내/사설 루트 CA 신뢰 (선택) ─────────────────────────────────────────
# 회사·학교 네트워크가 HTTPS 를 사설 CA 로 재서명(MITM)하면 Chrome 이 그 CA 를 몰라
# net_error -202(ERR_CERT_AUTHORITY_INVALID)가 난다. (Firefox 는 자체 저장소라 통과)
# CHROME_EXTRA_CA 에 사설 루트 CA 파일(PEM) 또는 그런 파일들이 든 디렉토리를 지정하면,
# 번들된 certutil 로 "포터블 프로필 내부" NSS DB 에 등록해 Chrome 이 신뢰하게 한다.
# 등록 정보가 프로필과 함께 이동하도록, 이 경우 HOME 을 프로필로 돌려 $HOME/.pki/nssdb 사용.
if [ -n "${CHROME_EXTRA_CA:-}" ] || [ -d "$DATA_DIR/.pki/nssdb" ]; then
    export HOME="$DATA_DIR"
    NSSDB="$HOME/.pki/nssdb"
    CU="$HERE/usr/bin/certutil"
    mkdir -p "$NSSDB"
    if [ ! -f "$NSSDB/cert9.db" ] && [ -x "$CU" ]; then
        "$CU" -d "sql:$NSSDB" -N --empty-password >/dev/null 2>&1 || true
    fi
    if [ -n "${CHROME_EXTRA_CA:-}" ] && [ -x "$CU" ]; then
        _import_ca() {
            local f="$1" nick
            nick="portable-ca-$(basename "$f")"
            "$CU" -d "sql:$NSSDB" -D -n "$nick" >/dev/null 2>&1 || true
            if "$CU" -d "sql:$NSSDB" -A -t "C,," -n "$nick" -i "$f" >/dev/null 2>&1; then
                echo "portable-chrome: 사설 CA 등록됨 → $f" >&2
            else
                echo "portable-chrome: 사설 CA 등록 실패(PEM 형식 확인) → $f" >&2
            fi
        }
        if [ -d "$CHROME_EXTRA_CA" ]; then
            for f in "$CHROME_EXTRA_CA"/*.pem "$CHROME_EXTRA_CA"/*.crt "$CHROME_EXTRA_CA"/*.cer; do
                [ -e "$f" ] && _import_ca "$f"
            done
        elif [ -f "$CHROME_EXTRA_CA" ]; then
            _import_ca "$CHROME_EXTRA_CA"
        else
            echo "portable-chrome: CHROME_EXTRA_CA 경로를 찾을 수 없음 → $CHROME_EXTRA_CA" >&2
        fi
    fi
fi

# 사용자가 이미 준 플래그는 중복 주입하지 않는다
has_flag() { local pfx="$1"; shift; for a in "$@"; do case "$a" in "$pfx"|"$pfx"=*) return 0;; esac; done; return 1; }

EXTRA=()
# 포터블 프로필 (사용자가 직접 지정하지 않은 경우)
has_flag --user-data-dir "$@" || EXTRA+=("--user-data-dir=$DATA_DIR")

# 시스템 키링(GNOME Keyring/KWallet) 잠금해제 팝업 방지:
#   비밀번호/쿠키 암호화를 OS 키링 대신 프로필 내부 basic 저장소로 처리한다.
#   (CHROME_USE_KEYRING=1 이면 시스템 키링을 그대로 사용)
if ! has_flag --password-store "$@" && [ "${CHROME_USE_KEYRING:-0}" != "1" ]; then
    EXTRA+=("--password-store=basic")
fi

# 첫 실행 안내 / 기본 브라우저 설정 배너 억제
# (CHROME_SHOW_PROMPTS=1 이면 억제하지 않음)
if [ "${CHROME_SHOW_PROMPTS:-0}" != "1" ]; then
    has_flag --no-first-run "$@"             || EXTRA+=("--no-first-run")
    has_flag --no-default-browser-check "$@" || EXTRA+=("--no-default-browser-check")
fi

# ── GPU / GL 처리 ─────────────────────────────────────────────────────────
# 포터블 실행 환경(헤드리스·VM·원격·일부 WSL 등)에는 동작하는 GL 드라이버가 없어
# 호스트 libGL/ANGLE 초기화가 실패하고 다음과 같은 에러를 쏟아낸다:
#   "libGL error: ... failed to open swrast", "ANGLE ... Could not create a backing
#    OpenGL context", "eglInitialize ... failed".
# 기본값으로 Chrome 에 번들된 SwiftShader(소프트웨어 GL)를 사용해 호스트 드라이버에
# 의존하지 않고 조용히 렌더링한다. (WebGL 도 동작)
#   CHROME_ENABLE_GPU=1  : 호스트 하드웨어 GPU 사용 (드라이버 정상인 데스크톱용)
#   CHROME_DISABLE_GPU=1 : GPU 완전 비활성(--disable-gpu, 가장 가벼움 / WebGL 꺼짐)
if [ "${CHROME_ENABLE_GPU:-0}" = "1" ]; then
    :   # 호스트 GPU 사용: 아무 것도 주입하지 않음
elif [ "${CHROME_DISABLE_GPU:-0}" = "1" ]; then
    has_flag --disable-gpu "$@" || EXTRA+=("--disable-gpu")
elif ! has_flag --use-angle "$@" && ! has_flag --use-gl "$@" && ! has_flag --disable-gpu "$@"; then
    # SwiftShader 소프트웨어 GL 로 라우팅해 호스트 GL 부재 에러를 없앤다.
    # (--enable-unsafe-swiftshader 는 WebGL 소프트웨어 폴백을 켜지만 Chrome 이 "unsafe"
    #  경고 인포바를 띄우므로 넣지 않는다. WebGL 이 필요하면 CHROME_ENABLE_GPU=1)
    EXTRA+=("--use-angle=swiftshader")
fi

# ── AI Mode 비활성 (기본) ─────────────────────────────────────────────────
# 주소창/새 탭의 "AI Mode" 진입점(버튼·제안·스타터팩·사인인 프로모)을 끈다.
# feature 이름은 이 Chrome 바이너리에서 실제 추출한 것. 알 수 없는 이름은 무시되므로 안전.
#   CHROME_ENABLE_AI=1 : AI Mode 를 끄지 않음(그대로 노출)
# 사용자가 직접 --disable-features/--enable-features 를 주면 덮어쓰지 않도록 관여하지 않는다.
if [ "${CHROME_ENABLE_AI:-0}" != "1" ] && ! has_flag --disable-features "$@" && ! has_flag --enable-features "$@"; then
    EXTRA+=("--disable-features=AiModeOmniboxEntryPoint,WebUIOmniboxDynamicAiModeButton,AllowAiModeMatches,AiModeEntryPointAlwaysNavigates,AiModeStartPack,EnableSearchAIModeSigninPromo")
fi

# ── 샌드박스 선택 ─────────────────────────────────────────────────────────
# 읽기전용 AppImage 에선 chrome-sandbox 를 SUID root 로 만들 수 없다. 그러나 최신
# Chrome 은 "사용자 네임스페이스"가 있으면 별도 플래그 없이도 네임스페이스 샌드박스를
# 자동 사용한다. → 이 경우 샌드박스 플래그를 아무것도 넣지 않는다.
#   (예전엔 --disable-setuid-sandbox 를 넣었으나 Chrome 이 화면 상단에 "unsupported
#    command-line flag: --disable-setuid-sandbox" 경고 인포바를 띄우므로 제거함)
# 네임스페이스가 비활성인 커널에서만 부득이 --no-sandbox 로 폴백한다. 이때 뜨는 경고
# 인포바는 --test-type 으로 억제한다. (샌드박스가 꺼지므로 보안은 저하)
SANDBOX_ARGS=()
userns_ok=1
if [ -r /proc/sys/kernel/unprivileged_userns_clone ]; then
    [ "$(cat /proc/sys/kernel/unprivileged_userns_clone)" = "0" ] && userns_ok=0
fi
if [ -r /proc/sys/user/max_user_namespaces ]; then
    [ "$(cat /proc/sys/user/max_user_namespaces)" = "0" ] && userns_ok=0
fi
# 사용자가 이미 샌드박스 관련 플래그를 직접 주면 우리는 관여하지 않는다.
_user_sb=0
for a in "$@"; do
    case "$a" in --no-sandbox|--disable-setuid-sandbox|--sandbox|--test-type) _user_sb=1;; esac
done
if [ "$_user_sb" -eq 0 ] && { [ "${CHROME_NO_SANDBOX:-0}" = "1" ] || [ "$userns_ok" -eq 0 ]; }; then
    [ "$userns_ok" -eq 0 ] && echo "portable-chrome: 사용자 네임스페이스 비활성 → --no-sandbox 실행(보안 저하)" >&2
    # --no-sandbox 경고 인포바는 --test-type 으로 억제
    SANDBOX_ARGS=(--no-sandbox --test-type)
fi

# ── 무해한 시작 잡음 로그 필터 ────────────────────────────────────────────
# 기능과 무관하지만 일부 환경에서 나오는 로그(딱 끄는 Chrome 플래그가 없음)를
# stderr 에서 해당 라인만 정확히 걸러낸다. 나머지 로그는 그대로 출력된다.
#   - UPower dbus: 전원/배터리 서비스(UPower) 미존재 시 1회성 dbus 에러
#   - GCM: 푸시 메시징 등록의 DEPRECATED_ENDPOINT 응답 에러
#   - NTP: 새 탭 열 때마다 반복되는 "chrome://newtab for incorrect profile type" 로그 스팸
#   - mojo: 렌더러 종료/전환 시 나오는 "Message N rejected by interface blink.mojom.*" 잡음
# (CHROME_QUIET=0 이면 필터하지 않고 원본 로그를 그대로 출력)
QUIET_RE='org\.freedesktop\.UPower|gcm/engine/registration_request|Registration response error message: DEPRECATED_ENDPOINT|Requested load of chrome://newtab/ for incorrect profile type|rejected by interface blink\.mojom'

if [ "${CHROME_QUIET:-1}" = "1" ] && echo x | grep --line-buffered -q x 2>/dev/null; then
    # process substitution 으로 stderr 만 필터(원본 stderr 로 재출력). stdout 은 무변경.
    exec "$CHROME" "${SANDBOX_ARGS[@]}" "${EXTRA[@]}" "$@" \
        2> >(grep --line-buffered -vE "$QUIET_RE" >&2)
else
    exec "$CHROME" "${SANDBOX_ARGS[@]}" "${EXTRA[@]}" "$@"
fi
APPRUN
chmod +x "$APPDIR/AppRun"

# ── 7) AppImage 패키징 ────────────────────────────────────────────────────
echo "==> AppImage 패키징"
RUNTIME_ARG=()
[ -f "$TOOLS/runtime-x86_64" ] && RUNTIME_ARG=(--runtime-file "$TOOLS/runtime-x86_64")

ARCH=x86_64 "$TOOLS/appimagetool" --appimage-extract-and-run \
    "${RUNTIME_ARG[@]}" \
    "$APPDIR" "$OUTDIR/$OUTNAME"

chmod +x "$OUTDIR/$OUTNAME" || true
echo "==> 완료: $OUTDIR/$OUTNAME (Chrome $CHROME_VER)"
