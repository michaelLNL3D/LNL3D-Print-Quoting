# Combined Slicer + Quoting Application — Design Spec

## Overview

Merge the PrusaSlicer quoting tool (`claude_prusaquoting`) and the LNL3D quoting/invoice site (`LNL3D_QuotingSite`) into a single Flask application with a two-phase UI: **Slicer → Quick Quote → (optional) Full Quote**.

The core insight: slice once with a stock PLA profile to get accurate weight and print time, then use material multipliers to extrapolate costs for any filament instantly — no re-slicing needed.

---

## Architecture

### Single Flask Server

The Node.js server (~100 lines of JSON file read/write) is eliminated. Flask handles everything:

- **Slicing**: Existing PrusaSlicer/OrcaSlicer CLI integration (unchanged)
- **Data persistence**: JSON file storage for quotes, settings, customers (ported from Node.js)
- **Combined frontend**: Served as a single-page app with phase-based navigation

**Port**: 5111 (existing Flask default)

### File Structure (target)

```
Combined/
├── app.py                    # Combined Flask backend
├── data/
│   ├── settings.json         # Company settings, printers, materials, discount tiers
│   ├── customers.json        # Customer database
│   └── quotes.json           # Quote log
├── requirements.txt          # Python dependencies (Flask, trimesh, etc.)
├── Dockerfile                # Existing Docker support
├── docker-compose.yml
└── docs/
```

### Data Persistence Endpoints (ported from Node.js)

| Method | Endpoint | Purpose |
|--------|----------|---------|
| GET | `/api/quotes` | Fetch all quotes |
| POST | `/api/quotes` | Save entire quotes array |
| GET | `/api/settings` | Fetch settings object |
| POST | `/api/settings` | Save settings object |
| GET | `/api/customers` | Fetch customer list |
| POST | `/api/customers` | Save customer list |

These read/write JSON files in `./data/` with the same format the LNL3D site already uses. No database.

### Existing Slicer Endpoints (unchanged)

| Method | Endpoint | Purpose |
|--------|----------|---------|
| GET | `/api/printers` | List printer names |
| GET | `/api/profiles` | Print & filament profiles for a printer |
| POST | `/api/check_size` | Pre-flight bounding box + mesh health check |
| POST | `/api/quote` | Slice model and generate slicer quote |
| GET | `/api/progress/<pid>` | Live progress polling |
| GET | `/api/export_gcode` | Download GCode |
| POST | `/api/export_3mf` | Export 3MF project |
| GET/POST/DELETE | `/api/presets` | Slicer presets |

---

## User Flow

### Phase 1: Slicer (Landing Page)

The existing slicer UI is the entry point. User uploads 3D files, configures orientation/cutting/slicing options, and clicks "Generate Quote."

**Key change**: Slicing always uses a **stock PLA baseline profile** regardless of what the user ultimately wants to quote. This gives accurate weight and print time that serve as the baseline for all material extrapolations.

The slicer phase retains:
- Drag-and-drop file upload (single + batch)
- Auto-orient toggle (OrcaSlicer)
- Pre-flight size/mesh checks
- Scale-to-fit and auto-split for oversized models
- Live progress polling during slicing
- Queue panel for batch uploads

**What changes**: After slicing completes, instead of showing the current slicer results panel, the UI transitions to Phase 2.

### Phase 2: Quick Quote View

A compact quote screen that appears after slicing. Shows the cost breakdown and allows quick adjustments without re-slicing.

**Visible information:**
- Filename
- Printer (editable dropdown)
- Filament (editable dropdown — applies multipliers)
- Quantity (editable)
- Customer (editable dropdown with autocomplete)
- Cost breakdown panel:
  - Print time (adjusted by material multiplier)
  - Weight (adjusted by material multiplier)
  - Material cost
  - Machine cost
  - Failure adjustment
  - Cost per piece
  - Markup multiplier and amount
- **Quote Price** (prominent)
- Margin % and profit/pc

**Actions:**
- **Log Quote** — Saves directly to the quote log with a generated quote ID
- **Full Details →** — Opens the complete quoting form (Phase 3)
- **← Back to Slicer** — Returns to slicer to upload/slice another file

**Batch behavior**: When multiple files are sliced, the quick quote shows all files as line items on a single quote. Each line item shows its own time/weight/cost, with a combined total at the bottom. All items share the same customer. Individual items can have different filament/printer selections.

### Phase 3: Full Quote Form (Optional)

The complete LNL3D quoting form, pre-filled with slicer data. Available via "Full Details →" from the quick quote.

**Pre-filled from slicer:**
- Weight (g) — adjusted by material multiplier
- Print time — adjusted by material multiplier
- Printer — selected in quick quote
- Filament — selected in quick quote
- Quantity — from quick quote
- Customer — from quick quote

**User fills in:**
- Project name, description
- Labor (prep, post-processing)
- Finishing (sanding, painting, hardware)
- Shipping
- Rush multiplier
- Complexity rating
- Custom quoted price override
- Notes

All existing quoting features remain: real-time cost sidebar, pricing schedule, material comparison, templates.

### Navigation

The app uses phase-based navigation, not traditional tabs:

```
[Slicer] → [Quick Quote] → [Full Quote Form]
                ↕                    ↕
         [Quote Log] [Dashboard] [Customers] [Settings]
```

- **Slicer phase**: Full-screen slicer UI. No tab bar visible.
- **Quoting phase**: Tab bar appears with: Dashboard, New Quote, Quote Log, Customers, Settings
- **Quick Quote**: Appears as a modal/overlay after slicing, or accessible from "New Quote" tab
- **"← Back to Slicer"**: Always available from quoting phase to return to slicer

Users can also navigate directly to the quoting tabs (Quote Log, Customers, Settings) without going through the slicer — for managing existing quotes, customers, or settings.

---

## Material Multiplier System

### Concept

Slice once with stock PLA → get `base_weight_g` and `base_time_minutes`. For any other material:

```
adjusted_time = base_time_minutes × material.time_multiplier
adjusted_weight = base_weight_g × material.weight_multiplier
```

These adjusted values feed into the quoting engine's full calculation (failure rates, depreciation, electricity, markup, etc.).

### Configuration

The existing materials table in Settings gains two new columns:

| Field | Type | Description |
|-------|------|-------------|
| `time_multiplier` | float | Print time relative to PLA (PLA = 1.0) |
| `weight_multiplier` | float | Weight relative to PLA (PLA = 1.0) |

**Default values:**

| Material | Time Mult. | Weight Mult. | Rationale |
|----------|-----------|--------------|-----------|
| PLA | 1.0 | 1.0 | Baseline |
| PETG | 1.3 | 1.05 | Slower speeds, slightly denser |
| ABS | 1.1 | 0.87 | Similar speed, lighter |
| TPU | 1.8 | 1.0 | Much slower due to flexibility |
| ASA | 1.15 | 0.88 | Similar to ABS |
| Nylon | 1.4 | 0.92 | Slower, lighter |
| PLA+ | 1.0 | 1.0 | Essentially same as PLA |

These are user-editable defaults. The user can adjust multipliers in the Settings tab as they calibrate against real prints.

### Weight Multiplier Rationale

Weight changes because different filaments have different densities. Same volume of plastic, different mass:
- PLA: ~1.24 g/cm³
- PETG: ~1.27 g/cm³
- ABS: ~1.04 g/cm³

The multiplier captures this without needing to know exact volumes.

---

## Cost Calculation Flow

When a quick quote is displayed or updated:

1. **Start with slicer baseline**: `base_time`, `base_weight_g` from PLA slicing
2. **Apply material multipliers**: `time = base_time × mat.time_mult`, `weight = base_weight_g × mat.weight_mult`
3. **Feed into quoting engine** (existing `calcFromQuoteData` logic):
   - `filamentCost = (weight_kg) × (spool_price / spool_weight)`
   - `electricCost = print_hours × printer_power × energy_rate`
   - `depreciationCost = print_hours × depreciation_rate`
   - `fail = base_fail + (material_complexity × base_fail)` (capped at max_fail)
   - `machinePP = (filament + electric + depreciation + consumables) × (1 + fail)`
   - `costPP = machinePP` (quick quote has no labor/finishing — those are in full form)
   - `markup = getMarkupForQty(quantity)`
   - `suggested = max(costPP × qty × markup, min_fee)`
4. **Display**: Cost breakdown, quote price, margin, profit

Changing printer recalculates using that printer's power rating, depreciation rate, and associated profiles. Changing filament applies that material's multipliers, density, cost, and complexity. All instant — no server round-trip needed for the recalculation (JavaScript in browser).

---

## Batch Quoting

### Single Quote, Multiple Line Items

When the user slices multiple files, they become line items on one quote:

```
Quote #007-20260325-ABC
Customer: Acme Corp

Line Items:
  1. bracket_mount.stl    — PETG, 2h 15m, 42.3g   — $11.17
  2. housing_top.stl      — PETG, 4h 30m, 89.1g   — $22.40
  3. housing_bottom.stl   — PETG, 3h 45m, 72.8g   — $18.55
                                          ─────────────────
                                    Total:   $52.12
```

Each line item can have a different printer/filament selection. Customer and quantity settings are shared across the quote.

### Data Model

The existing quote object gains a `line_items` array:

```javascript
{
  serial: 7,
  quote_id: "007-20260325-ACM",
  customer: "Acme Corp",
  date: "2026-03-25",
  status: "Quoting",
  line_items: [
    {
      filename: "bracket_mount.stl",
      printer: "LNL3D D3",
      filament: "PETG",
      base_weight_g: 40.3,      // PLA baseline from slicer
      base_time_minutes: 115,   // PLA baseline from slicer
      weight_g: 42.3,           // adjusted
      print_time: "2h 15m",     // adjusted
      quantity: 1,
      // ... calculated costs
    },
    // ... more items
  ],
  // Shared fields
  quantity: 1,
  rush: 1.0,
  notes: "",
  // Aggregated totals
  total_cost: 52.12,
  total_time: "10h 30m",
  total_weight_g: 204.2,
  // ... etc
}
```

For single-file quotes, `line_items` has one entry. This unifies the data model.

### PDF Generation

The existing PDF generation is extended to list line items in a table format, with per-item and total pricing. The layout follows the existing professional white-background PDF style.

---

## Settings Integration

### Merged Settings Object

The combined settings object includes everything from the LNL3D site plus slicer-specific additions:

```javascript
{
  company: "LNL3D",
  currency: "$",
  energy_rate: 0.12,           // $/kWh
  labor_rate: 25,              // $/hour (skilled)
  post_labor_rate: 20,         // $/hour (post-process)
  base_fail: 0.10,             // 10% base failure rate
  max_fail: 0.50,              // 50% max failure rate
  min_fee: 5.00,               // minimum quote price

  discounts: [                 // quantity → markup tiers
    { qty: 1, markup: 2.0 },
    { qty: 10, markup: 1.8 },
    // ...
  ],

  printers: [
    {
      name: "LNL3D D3",
      price: 500,              // purchase price
      life: 5000,              // lifetime hours
      service: 200,            // service cost over lifetime
      power: 0.15,             // kW draw
    }
  ],

  materials: [
    {
      name: "PLA",
      complexity: 1,
      spool_price: 25,
      spool_weight: 1.0,       // kg
      density: 1.24,           // g/cm³
      time_multiplier: 1.0,    // NEW: relative to PLA
      weight_multiplier: 1.0,  // NEW: relative to PLA
    },
    {
      name: "PETG",
      complexity: 3,
      spool_price: 30,
      spool_weight: 1.0,
      density: 1.27,
      time_multiplier: 1.3,    // NEW
      weight_multiplier: 1.05, // NEW
    },
    // ...
  ]
}
```

### Settings UI

The existing Settings tab gains the two new columns in the materials table. The rest of the settings UI (company info, cost factors, printers, discount tiers, data import/export) remains unchanged.

---

## Migration & Compatibility

### Data Migration

- Existing `LNL3D_QuotingSite/data/*.json` files are copied to `Combined/data/`
- Existing quotes (without `line_items`) are auto-wrapped: `line_items: [{ ...quote_fields }]` on first load
- Existing materials without multipliers get `time_multiplier: 1.0, weight_multiplier: 1.0` defaults
- Slicer presets (`~/.prusaquoting_presets.json`) continue to work as-is

### What Gets Removed

- `LNL3D_QuotingSite/server.js` — functionality ported to Flask
- `LNL3D_QuotingSite/LNL3D_Quote.html` — frontend merged into Flask's template
- Node.js dependency entirely eliminated

### What Stays Unchanged

- PrusaSlicer/OrcaSlicer CLI integration
- All slicer features (orient, split, scale, mesh checks, GCode export, 3MF export)
- Quoting calculation engine (all formulas preserved exactly)
- PDF generation
- Customer management
- Quote templates
- Slicer presets
- Docker support

---

## Technical Notes

### Frontend Consolidation

Both apps currently embed all HTML/CSS/JS in a single file. The combined app continues this pattern — one large `render_template_string` in Flask. The slicer JS and quoting JS coexist, sharing the same global scope.

Phase transitions are CSS-based: show/hide top-level container divs (`#slicer-phase`, `#quoting-phase`). No page reloads.

### Calculation: Server vs Client

- **Slicing**: Server-side (PrusaSlicer CLI) — unchanged
- **Quick quote recalculation**: Client-side JavaScript — multipliers, cost formulas, markup. Instant updates when changing filament/printer/qty.
- **Full quote calculation**: Client-side JavaScript — existing `calcFromQuoteData` function, unchanged
- **Data persistence**: Server-side (Flask JSON endpoints)

### Stock PLA Profile Selection

The slicer needs to know which PLA profile to use as baseline. Strategy:
- Default to the first PLA filament profile found for the selected printer
- If no PLA profile exists, use the first available filament profile
- The baseline profile is a slicer-internal detail — the user sees material names from the quoting settings, not slicer profile names

---

## Out of Scope

- User authentication / multi-user support
- Database backend (staying with JSON files)
- WebSocket for progress (staying with polling)
- Email/SMS quote delivery
- Payment processing
- Inventory tracking
