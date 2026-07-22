#!/usr/bin/env bash
# (온라인) 빌더 이미지를 만들어 tar.gz 로 저장한다.
# 저장된 이미지에는 Chrome + 의존 라이브러리 + appimagetool 이 모두 구워져 있어
# 이후 오프라인 머신에서 네트워크 없이 빌드할 수 있다.
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

echo "==> 빌더 이미지 빌드"
"$ENGINE" build -t "$IMG" .

mkdir -p offline-bundle
echo "==> 이미지 저장 (offline-bundle/builder-image.tar.gz)"
"$ENGINE" save "$IMG" | gzip > offline-bundle/builder-image.tar.gz

# 오프라인 실행 스크립트와 도우미 파일을 번들에 함께 넣는다.
cp build-offline-run.sh offline-bundle/
chmod +x offline-bundle/build-offline-run.sh

echo "==> 완료. 'offline-bundle/' 전체를 오프라인 머신으로 복사하세요."
echo "    (크기: $(du -h offline-bundle/builder-image.tar.gz | cut -f1))"
