#!/usr/bin/env bash
# (오프라인) 저장된 빌더 이미지를 로드하고 네트워크를 끊은 채 빌드한다.
# offline-bundle/ 디렉토리 안에서 실행하세요.
set -euo pipefail
cd "$(dirname "$0")"

ENGINE="${ENGINE:-}"
if [ -z "$ENGINE" ]; then
    if command -v docker >/dev/null 2>&1; then ENGINE=docker
    elif command -v podman >/dev/null 2>&1; then ENGINE=podman
    else echo "docker 또는 podman 이 필요합니다." >&2; exit 1
    fi
fi
echo "==> 컨테이너 엔진: $ENGINE"

IMG="portable-google-chrome-builder"

echo "==> 이미지 로드 (builder-image.tar.gz)"
gunzip -c builder-image.tar.gz | "$ENGINE" load

mkdir -p dist
echo "==> 네트워크 차단(--network none) 상태로 빌드"
"$ENGINE" run --rm --network none -v "$PWD/dist:/work/dist:Z" "$IMG" /build-in-container.sh

echo "==> 결과물: offline-bundle/dist/Google-Chrome-x86_64.AppImage"
