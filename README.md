# LNL3D Print Quoting

A local web app for quoting 3D print jobs. Drop a model file, configure printer/material settings, and get an instant quote with cost breakdown.

## Features

- Slice STL/OBJ/3MF/AMF/STEP files via PrusaSlicer CLI
- Auto-orient models (OrcaSlicer on x86, Tweaker on ARM)
- Auto-split oversized models to fit build volume
- Multi-part quoting with quantity discounts
- PDF quote export (customer-facing)
- Preset management for repeat configurations
- Full quote form with customer database

## Raspberry Pi 5 Setup (Docker)

This branch is configured for running on a Raspberry Pi 5 (64-bit ARM) via Docker.

### Prerequisites

- Raspberry Pi 5 (4GB+ RAM recommended)
- 64-bit Raspberry Pi OS or Ubuntu
- Docker and Docker Compose installed

### Quick Start

```bash
git clone -b rpi-docker https://github.com/michaelLNL3D/LNL3D-Print-Quoting.git
cd LNL3D-Print-Quoting/claude_prusaquoting
docker compose up --build
```

Open `http://<pi-ip>:5111` in a browser.

### First Build

The first build compiles PrusaSlicer from source for ARM64. This takes **30-60 minutes** on a Pi 5. Subsequent builds use Docker's layer cache and are fast.

### PrusaSlicer Configuration

Mount your PrusaSlicer config directory to use custom printer profiles:

```bash
PRUSASLICER_CONFIG=~/.config/PrusaSlicer docker compose up
```

### Environment Variables

| Variable | Default | Description |
|---|---|---|
| `PORT` | `5111` | Server port |
| `PRUSASLICER_CONFIG` | `~/Library/Application Support/PrusaSlicer` | Host path to PrusaSlicer config (mounted into container) |

### Differences from macOS

| Feature | macOS (`main` branch) | Pi (this branch) |
|---|---|---|
| PrusaSlicer | Pre-installed app | Built from source in Docker |
| OrcaSlicer | Pre-installed app | Not available |
| Auto-orient | OrcaSlicer CLI | Tweaker-3 (Python) |
| Run method | `python3 app.py` | `docker compose up` |

### Troubleshooting

- **Build fails with out-of-memory:** Reduce parallelism by editing the Dockerfile — change `make -j$(nproc)` to `make -j2` or `make -j1`
- **Site loads but slicer section is empty:** Check container logs with `docker compose logs`. PrusaSlicer binary may have failed to build.
- **Profiles not showing:** Ensure your PrusaSlicer config directory is mounted correctly and contains printer profiles.

## macOS Setup

For running directly on macOS without Docker, see the [`main`](../../tree/main) branch.
