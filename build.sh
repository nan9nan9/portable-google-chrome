#!/usr/bin/env bash
# (온라인) 빌더 이미지 빌드 + 컨테이너 실행 → dist/Google-Chrome-x86_64.AppImage
set -euo pipefail
cd "$(dirname "$0")"

# 컨테이너 엔진 자동 선택 (docker 우선, 없으면 podman). ENGINE 로 강제 가능.
ENGINE="${ENGINE:-}"
if [ -z "$ENGINE" ]; then
    if command -v docker >/dev/null 2>&1; then ENGINE=docker
    elif command -v podman >/dev/null 2>&1; then ENGINE=podman
    else echo "docker 또는 podman 이 필요합니다." >&2; exit 1
    fi
fi
echo "==> 컨테이너 엔진: $ENGINE"

IMG="portable-google-chrome-builder"
mkdir -p dist

echo "==> 빌더 이미지 빌드"
"$ENGINE" build -t "$IMG" .

echo "==> 컨테이너 실행 (AppImage 생성)"
# dist 를 마운트해 결과물을 호스트로 받는다. :Z 는 SELinux 환경용(무해).
"$ENGINE" run --rm -v "$PWD/dist:/work/dist:Z" "$IMG" /build-in-container.sh

echo "==> 결과물: dist/Google-Chrome-x86_64.AppImage"
