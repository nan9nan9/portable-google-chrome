# Portable Google Chrome 빌더 이미지
#
# Chrome 은 사전 빌드된 독점 바이너리라 Chrome 자체의 glibc 요구는 고정이다.
# (실측: Chrome 150 바이너리는 최대 GLIBC_2.25 만 요구)
# 반면 "함께 번들하는 의존 라이브러리"는 빌드 베이스의 glibc 에 링크되므로,
# 베이스가 새로우면 번들 라이브러리가 호스트에 더 높은 glibc 를 요구해 오래된
# 호스트에서 실행이 실패한다. → 하한선을 낮추려면 "베이스 자체를 낮춰야" 한다.
#
# 목표: glibc 2.28 (RHEL8/CentOS8/Debian10 계열)에서 실행.
# 그래서 베이스를 Debian 10(buster, glibc 2.28)로 쓴다.
# (검증: buster 에서 Chrome 150 설치·헤드리스 렌더링 정상. 번들 라이브러리 glibc
#  요구는 ≤2.28 로 떨어지고 Chrome 은 2.25 만 필요 → 하한선 glibc 2.28)
#
# buster 는 EOL 이라 apt 저장소가 archive.debian.org 로 이동했으므로 소스를 교체한다.
FROM debian:10-slim

ENV DEBIAN_FRONTEND=noninteractive

# buster 아카이브 소스로 교체 + 만료된 Release 파일 허용
RUN printf '%s\n' \
        'deb [check-valid-until=no] http://archive.debian.org/debian buster main' \
        'deb [check-valid-until=no] http://archive.debian.org/debian-security buster/updates main' \
        > /etc/apt/sources.list \
    && echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/99no-check-valid

# 빌드/패키징에 필요한 도구
#  - file, binutils         : ELF 검사
#  - squashfs-tools         : appimagetool 이 squashfs 생성에 사용
#  - libglib2.0-bin         : glib-compile-schemas
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
