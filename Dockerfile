# ── ARG for target architecture (set by BuildKit) ────────────────────────────
ARG TARGETARCH

# ══════════════════════════════════════════════════════════════════════════════
# Stage 1a: extract AppImages (amd64 only)
# ══════════════════════════════════════════════════════════════════════════════
FROM ubuntu:22.04 AS slicer-extract-amd64

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y wget squashfs-tools python3 \
  && rm -rf /var/lib/apt/lists/*

COPY find_squashfs_offset.py /tmp/find_squashfs_offset.py

# PrusaSlicer 2.8.1 (last release with Linux AppImage)
RUN wget -q \
    "https://github.com/prusa3d/PrusaSlicer/releases/download/version_2.8.1/PrusaSlicer-2.8.1%2Blinux-x64-newer-distros-GTK3-202409181416.AppImage" \
    -O /tmp/prusaslicer.AppImage \
  && OFFSET=$(python3 /tmp/find_squashfs_offset.py /tmp/prusaslicer.AppImage) \
  && echo "PrusaSlicer squashfs offset: $OFFSET" \
  && unsquashfs -dest /opt/prusaslicer -offset $OFFSET /tmp/prusaslicer.AppImage \
  && rm /tmp/prusaslicer.AppImage

# OrcaSlicer 2.3.1
RUN wget -q \
    "https://github.com/OrcaSlicer/OrcaSlicer/releases/download/v2.3.1/OrcaSlicer_Linux_AppImage_Ubuntu2404_V2.3.1.AppImage" \
    -O /tmp/orcaslicer.AppImage \
  && OFFSET=$(python3 /tmp/find_squashfs_offset.py /tmp/orcaslicer.AppImage) \
  && echo "OrcaSlicer squashfs offset: $OFFSET" \
  && unsquashfs -dest /opt/orcaslicer -offset $OFFSET /tmp/orcaslicer.AppImage \
  && rm /tmp/orcaslicer.AppImage


# ══════════════════════════════════════════════════════════════════════════════
# Stage 1b: build PrusaSlicer from source (arm64)
#
# Builds CLI-only (no GUI) — avoids wxWidgets/GTK/OpenGL deps entirely.
# Uses PrusaSlicer's bundled deps system so we don't need system Boost/TBB/etc.
# First build takes ~30-60 min on a Pi 5; Docker layer cache makes rebuilds fast.
# ══════════════════════════════════════════════════════════════════════════════
FROM ubuntu:22.04 AS slicer-extract-arm64

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y \
    git build-essential autoconf cmake pkg-config curl wget ca-certificates \
    libssl-dev libcurl4-openssl-dev libtool m4 zlib1g-dev \
    libgmp-dev libmpfr-dev \
  && rm -rf /var/lib/apt/lists/*

# Clone PrusaSlicer 2.8.1 (shallow)
RUN git clone --depth 1 --branch version_2.8.1 \
    https://github.com/prusa3d/PrusaSlicer.git /src/PrusaSlicer

# Build bundled dependencies (Boost, TBB, CGAL, OpenCASCADE, etc.)
# This is the longest step — cached after first build.
RUN mkdir -p /src/PrusaSlicer/deps/build && cd /src/PrusaSlicer/deps/build \
  && cmake .. \
  && make -j$(nproc)

# Build PrusaSlicer CLI only
RUN mkdir -p /src/PrusaSlicer/build && cd /src/PrusaSlicer/build \
  && cmake .. \
    -DCMAKE_BUILD_TYPE=Release \
    -DSLIC3R_STATIC=1 \
    -DSLIC3R_GUI=0 \
    -DSLIC3R_PCH=OFF \
    -DSLIC3R_BUILD_TESTS=OFF \
    -DSLIC3R_ENABLE_FORMAT_STEP=ON \
    -DCMAKE_PREFIX_PATH=/src/PrusaSlicer/deps/build/destdir/usr/local \
  && make -j$(nproc)

# Assemble output in /opt/prusaslicer matching the layout the runtime stage expects:
#   /opt/prusaslicer/bin/prusa-slicer   — the binary
#   /opt/prusaslicer/profiles/          — bundled printer/filament profiles
RUN mkdir -p /opt/prusaslicer/bin /opt/prusaslicer/profiles \
  && cp /src/PrusaSlicer/build/src/prusa-slicer /opt/prusaslicer/bin/ \
  && cp -r /src/PrusaSlicer/resources/profiles/* /opt/prusaslicer/profiles/

# Create empty orcaslicer dir so COPY --from in runtime stage always succeeds
RUN mkdir -p /opt/orcaslicer


# ══════════════════════════════════════════════════════════════════════════════
# Stage 2: pick the right slicer stage based on architecture
# BuildKit only builds the stage that matches TARGETARCH; the other is skipped.
# ══════════════════════════════════════════════════════════════════════════════
FROM slicer-extract-${TARGETARCH} AS slicer-stage


# ══════════════════════════════════════════════════════════════════════════════
# Stage 3: runtime
# ══════════════════════════════════════════════════════════════════════════════
FROM ubuntu:24.04

ARG TARGETARCH
ARG DEBIAN_FRONTEND=noninteractive

# Runtime deps — amd64 needs GUI libs for AppImage binaries; arm64 is minimal (CLI-only)
RUN if [ "$TARGETARCH" = "amd64" ]; then \
      apt-get update && apt-get install -y \
        python3 python3-pip \
        libgtk-3-0 libglib2.0-0 libdbus-1-3 \
        libgl1 libglu1-mesa \
        libxrender1 libxrandr2 libxss1 libxcursor1 libxcomposite1 \
        libxi6 libxtst6 libfontconfig1 libfreetype6 \
        libatk1.0-0 libcairo2 libpango-1.0-0 libpangocairo-1.0-0 \
        libwebkit2gtk-4.1-0 \
        ca-certificates \
      && rm -rf /var/lib/apt/lists/*; \
    else \
      apt-get update && apt-get install -y \
        python3 python3-pip git ca-certificates \
      && rm -rf /var/lib/apt/lists/*; \
    fi

COPY requirements.txt /tmp/requirements.txt
RUN pip3 install --no-cache-dir --break-system-packages -r /tmp/requirements.txt

# ── Copy slicers from the build stage ─────────────────────────────────────────
# Both arches put PrusaSlicer in /opt/prusaslicer (different internal layouts)
COPY --from=slicer-stage /opt/prusaslicer /opt/prusaslicer
# OrcaSlicer: present on amd64, empty dir on arm64 (so COPY always succeeds)
COPY --from=slicer-stage /opt/orcaslicer /opt/orcaslicer

# ── Wrapper scripts ───────────────────────────────────────────────────────────
# amd64: AppImage layout — binary at /opt/prusaslicer/usr/bin/prusa-slicer
# arm64: source build layout — binary at /opt/prusaslicer/bin/prusa-slicer
RUN if [ "$TARGETARCH" = "amd64" ]; then \
      printf '#!/bin/sh\nexec /opt/prusaslicer/usr/bin/prusa-slicer "$@"\n' \
        > /usr/local/bin/prusa-slicer && chmod +x /usr/local/bin/prusa-slicer; \
    else \
      printf '#!/bin/sh\nexec /opt/prusaslicer/bin/prusa-slicer "$@"\n' \
        > /usr/local/bin/prusa-slicer && chmod +x /usr/local/bin/prusa-slicer; \
    fi

# OrcaSlicer wrapper (amd64 only — not available on arm64)
RUN if [ "$TARGETARCH" = "amd64" ]; then \
      printf '#!/bin/sh\nexport LC_ALL=C\nexport LD_LIBRARY_PATH="/opt/orcaslicer/bin${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"\nexec /opt/orcaslicer/bin/orca-slicer "$@"\n' \
        > /usr/local/bin/orca-slicer && chmod +x /usr/local/bin/orca-slicer; \
    fi

WORKDIR /app
COPY app.py quote.py ./

RUN mkdir -p /data/prusaslicer_config /data/exports

# ── Environment ───────────────────────────────────────────────────────────────
ENV PRUSASLICER_PATH=/usr/local/bin/prusa-slicer
ENV PRUSA_USER_DIR=/root/.config/PrusaSlicer
ENV PRESETS_FILE=/data/presets.json
ENV PORT=5111
ENV HOME=/root
ENV DOCKER=1

# PRUSA_VENDOR_DIR and ORCASLICER_PATH are set by the entrypoint based on arch.
# Defaults here are for amd64; arm64 entrypoint overrides them.
ENV PRUSA_VENDOR_DIR=/opt/prusaslicer/usr/bin/resources/profiles
ENV ORCASLICER_PATH=/usr/local/bin/orca-slicer

# ── Entrypoint: set arch-specific env at runtime ──────────────────────────────
RUN printf '#!/bin/sh\n\
ARCH=$(uname -m)\n\
if [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then\n\
  export PRUSA_VENDOR_DIR=/opt/prusaslicer/profiles\n\
  unset ORCASLICER_PATH\n\
fi\n\
exec "$@"\n' > /usr/local/bin/entrypoint.sh && chmod +x /usr/local/bin/entrypoint.sh

VOLUME ["/data"]
EXPOSE 5111

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["python3", "app.py"]
