# LNL3D Print Quoting

A local web app for quoting 3D print jobs. Drop a model file, configure printer/material settings, and get an instant quote with cost breakdown.

## Features

- Slice STL/OBJ/3MF/AMF/STEP files via PrusaSlicer CLI
- Auto-orient models via OrcaSlicer
- Auto-split oversized models to fit build volume
- Multi-part quoting with quantity discounts
- PDF quote export (customer-facing)
- Preset management for repeat configurations
- Full quote form with customer database

## Requirements

- macOS (primary platform)
- [PrusaSlicer](https://github.com/prusa3d/PrusaSlicer/releases) installed
- [OrcaSlicer](https://github.com/SoftFever/OrcaSlicer/releases) installed (optional, for auto-orient)
- Python 3.10+

## Quick Start

```bash
pip install flask trimesh networkx rtree numpy scipy
python3 app.py
```

Opens automatically at [http://localhost:5111](http://localhost:5111).

## Environment Variables

| Variable | Default | Description |
|---|---|---|
| `PRUSASLICER_PATH` | `/Applications/PrusaSlicer.app/Contents/MacOS/PrusaSlicer` | Path to PrusaSlicer binary |
| `ORCASLICER_PATH` | `/Applications/OrcaSlicer.app/Contents/MacOS/OrcaSlicer` | Path to OrcaSlicer binary |
| `PRUSA_VENDOR_DIR` | `/Applications/PrusaSlicer.app/Contents/Resources/profiles` | Bundled printer profiles |
| `PRUSA_USER_DIR` | `~/Library/Application Support/PrusaSlicer` | User printer/filament profiles |
| `PORT` | `5111` | Server port |

## Docker (Raspberry Pi)

See the [`rpi-docker`](../../tree/rpi-docker) branch for Docker-based deployment on Raspberry Pi 5 (ARM64).
