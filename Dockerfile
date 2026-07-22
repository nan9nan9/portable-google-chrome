# Portable Google Chrome 빌더 이미지
#
# Chrome 은 사전 빌드된 독점 바이너리라 glibc 하한을 우리가 낮출 수 없다.
# (하한은 Chrome 바이너리 자신이 결정) → 그러나 "번들 라이브러리"는 빌드 베이스의
# glibc 에 링크되므로, 베이스가 새로우면 번들 라이브러리가 호스트에 더 높은 glibc 를
# 요구하게 된다. 따라서 "현재 Chrome stable 이 여전히 실행되는 가장 낮은 배포판"을
# 골라 하한선을 최소화한다. 검증 결과 Debian 11(glibc 2.31)에서 Chrome 150 정상 실행.
# → 하한선 glibc 2.31 (Debian11 / Ubuntu20.04 / RHEL9(2.34) 등 폭넓게 커버).
# apt 로 google-chrome-stable 을 설치하면 Chrome 본체 + 모든 런타임 의존
# 라이브러리가 이미지에 함께 들어오므로 ldd 로 전부 수집할 수 있다.
FROM debian:11-slim

ENV DEBIAN_FRONTEND=noninteractive

# 빌드/패키징에 필요한 도구
#  - file, binutils         : ELF 검사
#  - squashfs-tools         : appimagetool 이 squashfs 생성에 사용
#  - libglib2.0-bin         : glib-compile-schemas
#  - fuse3/libfuse2         : appimagetool 실행 편의 (실제로는 extract-and-run 사용)
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl gnupg file binutils xz-utils \
        squashfs-tools libglib2.0-bin \
    && rm -rf /var/lib/apt/lists/*

# Google 공식 저장소 추가 후 Chrome 설치 (의존 라이브러리까지 함께 설치됨)
RUN curl -fsSL https://dl.google.com/linux/linux_signing_key.pub \
        | gpg --dearmor -o /usr/share/keyrings/google-chrome.gpg \
    && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome.gpg] http://dl.google.com/linux/chrome/deb/ stable main" \
        > /etc/apt/sources.list.d/google-chrome.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends google-chrome-stable \
    && rm -rf /var/lib/apt/lists/*

# appimagetool + AppImage 런타임 (오프라인 빌드 대비 이미지에 구워둔다)
RUN mkdir -p /opt/tools \
    && curl -fsSL -o /opt/tools/appimagetool \
        https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage \
    && curl -fsSL -o /opt/tools/runtime-x86_64 \
        https://github.com/AppImage/type2-runtime/releases/download/continuous/runtime-x86_64 \
    && chmod +x /opt/tools/appimagetool /opt/tools/runtime-x86_64

COPY scripts/build-in-container.sh /build-in-container.sh
RUN chmod +x /build-in-container.sh

WORKDIR /work
CMD ["/build-in-container.sh"]
