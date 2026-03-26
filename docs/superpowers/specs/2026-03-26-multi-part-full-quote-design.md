# Multi-Part Full Quote Form — Design Spec

## Goal

Rebuild the Full Quote form to support multiple parts (line items) in a single quote, each with independent print settings, labor, and finishing costs. Enable proper multi-part quoting from slicer batch results through to quote logging and PDF export.

## Architecture

The Full Quote form transitions from a single-item form to a tabbed multi-part form. Shared quote-level fields (customer, project, shipping) remain as single inputs. Per-part fields (printer, filament, weight, time, labor, finishing) live inside tabs — one tab per part. The right sidebar shows collapsible per-part cost breakdowns plus a combined total. The quote data structure gains a `line_items[]` array. Existing single-part quotes are backwards-compatible as quotes with one line item.

## UI Layout

### Form Structure (Left Column)

**Shared section — top:**
- Customer (text, with datalist autocomplete)
- Project (text)
- Description (text)
- Date (date input)
- Status (select: Quoting / Accepted / In Progress / Complete / Declined)
- Rush multiplier (select: 1.0x–2.0x)

**Part tabs:**
- Tab bar: `Part 1: filename.stl` | `Part 2: filename2.stl` | `+ Add Part`
- Each tab has an X button to remove the part (disabled if only 1 part)
- Active tab is highlighted with accent color border
- Only one tab's content visible at a time

**Per-part form (inside active tab):**
- Print Details: Printer (select), Filament (select), Weight (g), Print Time, Complexity (1-10), Quantity
- Support Material: Support Filament (select), Support Weight (g)
- Labor: Prep Model (min), Prep Slice (min), Post Remove (min, default 2), Post Support (min, default 5), Post Extra (min)
- Finishing Materials: Sand ($), Paint ($), Hardware ($), Other ($)
- Consumables ($)

**Shared section — bottom:**
- Shipping: Packaging ($), Shipping Cost ($)
- Notes (textarea)
- Quoted Price override (number, optional — applies to whole quote total)

### Right Sidebar

**Per-part breakdown sections (one per part, collapsible):**
- Header: Part name (filename) + part suggested price
- Rows: Material cost, Electricity, Depreciation, Consumables, Prep labor, Post labor, Finishing, Failure rate %, Cost/pc, Markup, Suggested price
- Clicking a part breakdown header scrolls to / activates that tab

**Combined total section (always visible, bottom of sidebar):**
- Total Cost (sum of all parts' costTotal)
- Total Suggested Price (sum of all parts' suggested)
- Total Quoted (if override entered)
- Total Margin
- Total Profit

**Pricing schedule table:**
- Shows volume tiers using combined total quantity across all parts
- Each tier recalculates all parts at the tier's markup rate

### Quote Log — Expandable Rows

**Default row (collapsed):** Serial, Quote ID, Date, Customer, Description (shows part count if multi-part, e.g. "3 parts"), Status badge, Total Qty (sum across parts), Total Suggested Price, Edit/Delete actions.

**Expanded row:** Clicking the expand arrow reveals a sub-table of line items:
- Columns: Part (filename), Material, Printer, Qty, Weight, Time, Price
- Light background to distinguish from main row

## Data Structure

### Quote object (stored in quotes.json)

```json
{
  "serial": 1,
  "quote_id": "Q-001",
  "customer": "Acme Corp",
  "project": "Bracket Assembly",
  "description": "Multi-part bracket set",
  "date": "2026-03-26",
  "status": "Quoting",
  "rush": 1.0,
  "notes": "",
  "ship_pack": 0,
  "ship_cost": 0,
  "quoted_price": 0,
  "created": "2026-03-26T00:00:00Z",
  "updated": "2026-03-26T00:00:00Z",
  "line_items": [
    {
      "filename": "bracket_v2.stl",
      "printer": "Tenlog TL-D3",
      "filament": "PLA+",
      "weight_g": 202.4,
      "print_time": "21.22",
      "complexity": 3,
      "quantity": 5,
      "support_filament": "",
      "support_weight_g": 0,
      "prep_model": 0,
      "prep_slice": 0,
      "post_remove": 2,
      "post_support": 5,
      "post_extra": 0,
      "fin_sand": 0,
      "fin_paint": 0,
      "fin_hardware": 0,
      "fin_other": 0,
      "consumables": 0,
      "job_id": "abc123"
    },
    {
      "filename": "housing.stl",
      "printer": "LNL3D D3",
      "filament": "PETG",
      "weight_g": 340.1,
      "print_time": "32.5",
      "complexity": 5,
      "quantity": 2,
      "support_filament": "PLA+",
      "support_weight_g": 15.2,
      "prep_model": 5,
      "prep_slice": 0,
      "post_remove": 2,
      "post_support": 10,
      "post_extra": 0,
      "fin_sand": 5,
      "fin_paint": 0,
      "fin_hardware": 3,
      "fin_other": 0,
      "consumables": 2
    }
  ],
  "calc_total_cost": 45.20,
  "calc_total_suggested": 87.30,
  "calc_total_margin": 0.48,
  "calc_total_profit": 42.10
}
```

### Backwards Compatibility

Existing single-part quotes have fields at the root level (weight_g, print_time, printer, filament, etc.) and no `line_items` array. When loading an old-format quote:
- If `line_items` is absent, construct a single-item `line_items` array from the root-level fields
- Save back in the new format on next edit
- No migration script needed — conversion happens on load

Existing quotes logged via `logQuickQuote` already have a `line_items` array — these are already compatible.

## Calculation Flow

Each part is independently calculated through `qCalcFromQuoteData()`:
1. Build a per-part `q` object from the tab's form fields + shared rush multiplier
2. Call `qCalcFromQuoteData(q)` → returns per-part calc object
3. Aggregate: sum costTotal, suggested, profit across all parts
4. Add shipping (shared) to the aggregate
5. Apply quoted_price override if set (replaces total suggested)
6. Compute combined margin from aggregated numbers

The pricing schedule iterates over discount tiers, applying each tier's markup to all parts' costPP values and summing.

## Prefill from Quick Quote

`prefillQuoteForm(qqItemsData)` creates one tab per qqItem:
- Each tab populated with: printer, filament, weight (adjusted), time (adjusted), complexity, quantity, filename
- Shared fields: customer from qq-customer input, date = today, status = Quoting
- First tab is active
- Notes populated with summary if helpful

## Form Actions

- **Log Quote** — Assembles quote object with line_items array from all tabs, saves to qState.quotes
- **Clear** — Resets to single empty tab, clears shared fields
- **Edit from log** — Loads quote, creates one tab per line item, populates shared fields

## PDF Integration

The existing `qqDownloadPDF` already handles multi-item via `qqItems[]`. When generating PDF from the Full Quote form:
- Build qqItems-compatible objects from the line_items array
- Reuse the same PDF generation function

## Out of Scope

- Drag-to-reorder tabs (parts always in creation order)
- Per-part quoted price override (override is quote-level only)
- Splitting a multi-part quote into separate quotes
- Inline 3D preview per part
