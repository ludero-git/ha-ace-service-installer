# syntax=docker/dockerfile:1

ARG BUILD_FROM=debian:13-slim

FROM ${BUILD_FROM} AS novnc-assets

ENV DEBIAN_FRONTEND=noninteractive

RUN /bin/bash <<'EOF'
set -eu

echo "==> Preparing noVNC assets"

apt-get update

apt-get install -y --no-install-recommends \
  novnc

mkdir -p /out
cp -a /usr/share/novnc/. /out/

rm -rf \
  /var/lib/apt/lists/* \
  /var/cache/apt/* \
  /tmp/* \
  /var/tmp/*

echo "==> noVNC assets ready"
EOF

FROM ${BUILD_FROM} AS os-base

ENV DEBIAN_FRONTEND=noninteractive
ARG TARGETARCH

RUN /bin/bash <<'EOF'
set -eu

echo "==> Installing base OS packages"

case "$TARGETARCH" in
  amd64) dpkg --add-architecture i386 ;;
esac

apt-get update

apt-get install -y --no-install-recommends \
  ca-certificates \
  curl \
  fonts-dejavu-core \
  fonts-liberation \
  jq \
  libxcomposite1 \
  libxcursor1 \
  libxi6 \
  libxinerama1 \
  libxrandr2 \
  libxrender1 \
  libxtst6 \
  nginx \
  openbox \
  python3 \
  python3-flask \
  tini \
  tint2 \
  util-linux \
  websockify \
  wmctrl \
  x11-utils \
  x11vnc \
  xvfb

echo "==> Removing unused Mesa/LLVM graphics payload"

strip_package_payload()
{
  package="$1"

  dpkg-query -L "$package" 2>/dev/null |
    while IFS= read -r path; do
      if [ -f "$path" ] || [ -L "$path" ]; then
        rm -f "$path"
      fi
    done
}

dpkg-query -W -f='${binary:Package}\n' 2>/dev/null |
  grep -E '^(mesa-|lib[^ ]*mesa[^ ]*|libgbm1|libllvm[0-9]+|libz3-[0-9]+)(:.*)?$' |
  while IFS= read -r package; do
    echo "    stripping $package"
    strip_package_payload "$package"
  done

ldconfig

rm -rf \
  /var/lib/apt/lists/* \
  /var/cache/apt/* \
  /usr/share/doc/* \
  /usr/share/man/* \
  /usr/share/info/* \
  /tmp/* \
  /var/tmp/*

echo "==> Base OS packages ready"
EOF

FROM os-base AS wine-base

ARG TARGETARCH

RUN /bin/bash <<'EOF'
set -eu

echo "==> Installing Wine runtime for $TARGETARCH"

apt-get update

case "$TARGETARCH" in
  amd64)
    apt-get install -y --no-install-recommends \
      wine \
      wine64 \
      wine32:i386
    ;;

  arm64)
    mkdir -p /tmp/hangover-install
    cd /tmp/hangover-install

    echo "==> Downloading Hangover"

    curl -fL \
      https://github.com/AndreRH/hangover/releases/download/hangover-11.16/hangover_11.16_debian13_trixie_arm64.tar \
      -o hangover.tar

    echo "b5493f5903ab3c05f78bf4c03b06ac0005eb26f732437748c1592fefa45e861a  hangover.tar" \
      | sha256sum -c -

    tar -xf hangover.tar

    apt-get install -y --no-install-recommends ./hangover*.deb

    rm -rf /tmp/hangover-install
    ;;

  *)
    echo "Unsupported architecture: $TARGETARCH" >&2
    exit 1
    ;;
esac

echo "==> Removing any Mesa/LLVM payload introduced by Wine"

strip_package_payload()
{
  package="$1"

  dpkg-query -L "$package" 2>/dev/null |
    while IFS= read -r path; do
      if [ -f "$path" ] || [ -L "$path" ]; then
        rm -f "$path"
      fi
    done
}

dpkg-query -W -f='${binary:Package}\n' 2>/dev/null |
  grep -E '^(mesa-|lib[^ ]*mesa[^ ]*|libgbm1|libllvm[0-9]+|libz3-[0-9]+)(:.*)?$' |
  while IFS= read -r package; do
    echo "    stripping $package"
    strip_package_payload "$package"
  done

ldconfig

rm -rf \
  /var/lib/apt/lists/* \
  /var/cache/apt/* \
  /usr/share/doc/* \
  /usr/share/man/* \
  /usr/share/info/* \
  /tmp/* \
  /var/tmp/*

echo "==> Wine runtime ready"
EOF

FROM wine-base AS runtime-base

RUN <<'EOF'
set -eu

useradd \
  --uid 1000 \
  --home-dir /data/home/ace \
  --shell /bin/bash \
  ace

mkdir -p \
  /opt/ace/web/novnc \
  /run/nginx \
  /tmp/runtime-ace \
  /data/home/ace \
  /data/home/ace/Desktop \
  /data/home/ace/Documents \
  /data/home/ace/Downloads

chown -R \
  ace:ace \
  /opt/ace \
  /tmp/runtime-ace \
  /data/home/ace

chmod 0700 /tmp/runtime-ace
EOF

COPY --from=novnc-assets --chown=ace:ace \
  /out/ \
  /opt/ace/web/novnc/

FROM runtime-base AS winetricks-base

RUN /bin/bash <<'EOF'
set -eu

echo "==> Installing Winetricks dependencies"

sed -i \
  '/^Components:/ s/$/ contrib/' \
  /etc/apt/sources.list.d/debian.sources

apt-get update

apt-get install -y --no-install-recommends \
  cabextract \
  unzip \
  winetricks

rm -rf \
  /var/lib/apt/lists/* \
  /var/cache/apt/* \
  /tmp/* \
  /var/tmp/*

echo "==> Winetricks ready"
EOF

# Install fonts before .NET, otherwise .NET spawned processes hang wineserver -w.
FROM winetricks-base AS fonts-prefix

ENV XDG_RUNTIME_DIR=/tmp/runtime-root \
    DISPLAY=:99 \
    WINEPREFIX=/opt/ace/wineprefix \
    WINEARCH=win64

ARG TARGETARCH
USER ace

RUN /bin/bash <<'EOF'
set -eu

echo "==> Installing Wine fonts"

mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

Xvfb :99 \
  -screen 0 1280x720x24 \
  -nolisten tcp \
  -ac \
  -extension GLX \
  >/tmp/xvfb.log 2>&1 &

for _ in {1..50}; do
  [ -S /tmp/.X11-unix/X99 ] && break
  sleep 0.1
done

[ -S /tmp/.X11-unix/X99 ]

case "$TARGETARCH" in
  amd64)
    winetricks -q --force corefonts fontsmooth=rgb
    ;;

  arm64)
    export HODLL=libwow64fex.dll
    export HODLL64=libarm64ecfex.dll

    WINEDLLOVERRIDES="mscoree,mshtml=" \
      winetricks -q corefonts fontsmooth=rgb
    ;;
esac

echo "==> Wine fonts ready"
EOF

FROM fonts-prefix AS dotnet-prefix

ARG TARGETARCH

RUN /bin/bash <<'EOF'
set -eu

case "$TARGETARCH" in
  arm64)
    export HODLL=libwow64fex.dll
    export HODLL64=libarm64ecfex.dll
    ;;
esac

Xvfb :99 \
  -screen 0 1280x720x24 \
  -nolisten tcp \
  -ac \
  -extension GLX \
  >/tmp/xvfb.log 2>&1 &

for _ in {1..50}; do
  [ -S /tmp/.X11-unix/X99 ] && break
  sleep 0.1
done

[ -S /tmp/.X11-unix/X99 ]

echo "==> Installing .NET Framework 4.0"

WINEDLLOVERRIDES="mscoree,mshtml=" \
  WINEFLAGS="-passive -norestart" \
  winetricks -q dotnet40

echo "==> Installing .NET Framework 4.8"

WINEDLLOVERRIDES="mscoree,mshtml=" \
  WINEFLAGS="-passive -norestart" \
  winetricks -q dotnet48

echo "==> Cleaning Wine prefix"

rm -rf \
  "$WINEPREFIX/drive_c/windows/Microsoft.NET/Framework64/v4.0.30319/SetupCache" \
  "$WINEPREFIX/drive_c/windows/Temp/"* \
  "$WINEPREFIX/drive_c/users/ace/Temp/"* \
  "$WINEPREFIX/drive_c/users/ace/AppData/Local/Temp/"*

echo "==> Wine .NET prefix ready"
EOF

FROM mcr.microsoft.com/dotnet/sdk:8.0 AS service-installer-patcher-build

WORKDIR /src

COPY tools/service-installer-patcher/ServiceInstallerPatcher.csproj ./

RUN echo "==> Restoring service installer patcher" && \
    dotnet restore ServiceInstallerPatcher.csproj

COPY tools/service-installer-patcher/Program.cs ./

RUN <<'EOF'
set -e

echo "==> Building service installer patcher"

dotnet build \
  ServiceInstallerPatcher.csproj \
  --configuration Release \
  --no-restore \
  --output /out \
  -p:DebugSymbols=false \
  -p:DebugType=None

test -f /out/ServiceInstallerPatcher.exe
test -f /out/Mono.Cecil.dll

echo "==> Service installer patcher ready"
EOF

FROM runtime-base AS openbox-config-build

COPY tools/configure-openbox.py /tmp/configure-openbox.py

RUN <<'EOF'
set -eu

mkdir -p /out

SHOW_DESKTOP=false \
ACE_OPENBOX_DEST=/out/application.xml \
python3 /tmp/configure-openbox.py

SHOW_DESKTOP=true \
ACE_OPENBOX_DEST=/out/desktop.xml \
python3 /tmp/configure-openbox.py
EOF

FROM runtime-base AS final

ARG TARGETARCH
ARG BUILD_VERSION="dev"
ARG BUILD_ARCH="local"

ENV DISPLAY=:0 \
    WINEPREFIX=/opt/ace/wineprefix \
    WINEARCH=win64 \
    WINEDEBUG=-all \
    HOME=/data/home/ace \
    XDG_RUNTIME_DIR=/tmp/runtime-ace \
    ACE_LOG=/config/ace-service-installer.log

COPY --from=dotnet-prefix --chown=ace:ace \
  /opt/ace/wineprefix/ \
  /opt/ace/wineprefix/

COPY --from=service-installer-patcher-build --chown=ace:ace \
  /out/ \
  /opt/ace/tools/service-installer-patcher/

COPY --from=openbox-config-build --chown=ace:ace \
  /out/ \
  /opt/ace/openbox/

COPY rootfs/ /

USER root

RUN <<'EOF'
set -eu

chmod 0755 \
  /usr/local/bin/entrypoint.sh \
  /usr/local/bin/ace-control.sh \
  /usr/local/bin/ace-api.py

rm -f /etc/nginx/sites-enabled/default

ln -s \
  /etc/nginx/sites-available/ace \
  /etc/nginx/sites-enabled/ace

rm -rf \
  /var/cache/apt/* \
  /usr/share/doc/* \
  /usr/share/man/* \
  /usr/share/info/* \
  /tmp/* \
  /var/tmp/*
EOF

RUN /bin/bash <<'EOF'
set -euo pipefail

case "$TARGETARCH" in
  amd64) actual_hass_arch="amd64" ;;
  arm64) actual_hass_arch="aarch64" ;;
  *) actual_hass_arch="$TARGETARCH" ;;
esac

metadata_arch="$BUILD_ARCH"

if [ -z "$metadata_arch" ] || [ "$metadata_arch" = "local" ]; then
  metadata_arch="$actual_hass_arch"
fi

source_hash="$(
  find \
    /usr/local/bin \
    /opt/ace/web/app \
    /opt/ace/tools \
    /opt/ace/openbox \
    /etc/nginx/sites-available/ace \
    -type f \
    -print0 |
    sort -z |
    xargs -0 sha256sum |
    sha256sum |
    awk '{print $1}'
)"

printf \
  '{"version":"%s","arch":"%s","source_hash":"%s"}\n' \
  "$BUILD_VERSION" \
  "$metadata_arch" \
  "$source_hash" \
  > /opt/ace/build-info.json
EOF

EXPOSE 8100

USER root

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/usr/local/bin/entrypoint.sh"]