# Combined Slicer + Quoting App — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Merge the PrusaSlicer quoting tool and LNL3D quoting/invoice site into a single Flask application with a Slicer → Quick Quote → Full Quote pipeline.

**Architecture:** Single Flask server (`app.py`) handles slicing (PrusaSlicer CLI), data persistence (JSON files), and serves a combined frontend. The slicer is the landing page; after slicing, the UI transitions to a quick quote view with cost breakdown. Users can optionally expand to the full quoting form. Material changes use multipliers against a PLA baseline — no re-slicing.

**Tech Stack:** Flask (Python 3), PrusaSlicer CLI, OrcaSlicer CLI, trimesh, vanilla JavaScript, CSS custom properties

**Spec:** `docs/superpowers/specs/2026-03-25-combined-slicer-quoting-design.md`

---

## File Structure

All work happens in the root `Combined/` directory. The final app is a single Flask server.

| File | Role |
|------|------|
| `app.py` | Combined Flask backend + all HTML/CSS/JS (extended from `claude_prusaquoting/app.py`) |
| `data/settings.json` | Company settings, printers, materials (with multipliers), discount tiers |
| `data/customers.json` | Customer contact database |
| `data/quotes.json` | Logged quotes |
| `requirements.txt` | Python dependencies (from `claude_prusaquoting/requirements.txt`) |

**Source files read during implementation:**
- `claude_prusaquoting/app.py` — slicer backend + frontend (~2850 lines)
- `LNL3D_QuotingSite/LNL3D_Quote.html` — quoting frontend (~3258 lines)
- `LNL3D_QuotingSite/server.js` — Node.js JSON persistence (136 lines, being replaced)
- `LNL3D_QuotingSite/data/settings.json` — existing settings with printers/materials/discounts

---

## Task 1: Bootstrap the Combined Project

Copy the slicer app as the base and set up the data directory for JSON persistence.

**Files:**
- Copy: `claude_prusaquoting/app.py` → `app.py`
- Copy: `claude_prusaquoting/requirements.txt` → `requirements.txt`
- Copy: `LNL3D_QuotingSite/data/settings.json` → `data/settings.json`
- Create: `data/customers.json`
- Create: `data/quotes.json`

- [ ] **Step 1: Copy slicer app as the base**

```bash
cp claude_prusaquoting/app.py ./app.py
cp claude_prusaquoting/requirements.txt ./requirements.txt
```

- [ ] **Step 2: Create data directory and seed files**

```bash
mkdir -p data
cp LNL3D_QuotingSite/data/settings.json data/settings.json
echo '[]' > data/customers.json
echo '[]' > data/quotes.json
```

- [ ] **Step 3: If existing customers/quotes data exists, copy it too**

```bash
# Only if these have real data in the LNL3D project:
cp LNL3D_QuotingSite/data/customers.json data/customers.json 2>/dev/null || true
cp LNL3D_QuotingSite/data/quotes.json data/quotes.json 2>/dev/null || true
```

- [ ] **Step 4: Verify the slicer still runs**

```bash
cd /Users/michael/Documents/Claude_Projects/Combined
python3 app.py &
sleep 2
curl -s http://localhost:5111/ | head -20
# Expected: HTML output starting with <!DOCTYPE html>
kill %1
```

- [ ] **Step 5: Commit**

```bash
git add app.py requirements.txt data/
git commit -m "bootstrap: copy slicer as base, seed data directory"
```

---

## Task 2: Add JSON Persistence Endpoints to Flask

Port the 6 Node.js JSON CRUD endpoints into `app.py`. These are simple file read/write operations.

**Files:**
- Modify: `app.py` (add routes after existing Flask routes, before the HTML template)

- [ ] **Step 1: Add data directory constants and ensure-exists logic**

Add near the top of `app.py`, after the existing constants (after line ~31):

```python
# ── Data persistence (ported from Node.js server) ─────────────────────────────
DATA_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data")
QUOTES_FILE = os.path.join(DATA_DIR, "quotes.json")
CUSTOMERS_FILE = os.path.join(DATA_DIR, "customers.json")
SETTINGS_FILE = os.path.join(DATA_DIR, "settings.json")

os.makedirs(DATA_DIR, exist_ok=True)
for _f, _default in [(QUOTES_FILE, "[]"), (CUSTOMERS_FILE, "[]"), (SETTINGS_FILE, "{}")]:
    if not os.path.exists(_f):
        with open(_f, "w") as _fh:
            _fh.write(_default)
```

- [ ] **Step 2: Add helper functions for JSON file I/O**

Add after the constants:

```python
def _read_json(filepath, fallback):
    """Read a JSON file, return fallback string on error."""
    try:
        with open(filepath, "r", encoding="utf-8") as f:
            return f.read()
    except (OSError, IOError):
        return fallback


def _write_json(filepath, data_str):
    """Validate JSON string and write to file. Raises ValueError if invalid."""
    json.loads(data_str)  # validate
    with open(filepath, "w", encoding="utf-8") as f:
        f.write(data_str)
```

- [ ] **Step 3: Add the 6 CRUD routes**

Add after the existing slicer API routes (before the `HTML = """` line):

```python
# ── Data persistence API (quotes, settings, customers) ────────────────────────

@app.route("/api/qdata/quotes", methods=["GET"])
def api_get_quotes():
    return app.response_class(_read_json(QUOTES_FILE, "[]"), mimetype="application/json")


@app.route("/api/qdata/quotes", methods=["POST"])
def api_post_quotes():
    try:
        _write_json(QUOTES_FILE, request.get_data(as_text=True))
        return jsonify({"ok": True})
    except (ValueError, OSError) as e:
        return jsonify({"error": str(e)}), 400


@app.route("/api/qdata/settings", methods=["GET"])
def api_get_settings():
    return app.response_class(_read_json(SETTINGS_FILE, "{}"), mimetype="application/json")


@app.route("/api/qdata/settings", methods=["POST"])
def api_post_settings():
    try:
        _write_json(SETTINGS_FILE, request.get_data(as_text=True))
        return jsonify({"ok": True})
    except (ValueError, OSError) as e:
        return jsonify({"error": str(e)}), 400


@app.route("/api/qdata/customers", methods=["GET"])
def api_get_customers():
    return app.response_class(_read_json(CUSTOMERS_FILE, "[]"), mimetype="application/json")


@app.route("/api/qdata/customers", methods=["POST"])
def api_post_customers():
    try:
        _write_json(CUSTOMERS_FILE, request.get_data(as_text=True))
        return jsonify({"ok": True})
    except (ValueError, OSError) as e:
        return jsonify({"error": str(e)}), 400
```

**Note:** Endpoints use `/api/qdata/` prefix to avoid collision with the slicer's existing `/api/` endpoints (e.g., the slicer already has `/api/presets`).

- [ ] **Step 4: Test the persistence endpoints**

```bash
cd /Users/michael/Documents/Claude_Projects/Combined
python3 app.py &
sleep 2

# Test GET settings
curl -s http://localhost:5111/api/qdata/settings | python3 -m json.tool | head -5
# Expected: JSON object with company, energy, printers, materials, etc.

# Test POST quotes
curl -s -X POST http://localhost:5111/api/qdata/quotes \
  -H 'Content-Type: application/json' \
  -d '[{"test": true}]'
# Expected: {"ok": true}

# Verify it persisted
curl -s http://localhost:5111/api/qdata/quotes
# Expected: [{"test": true}]

# Restore empty quotes
curl -s -X POST http://localhost:5111/api/qdata/quotes \
  -H 'Content-Type: application/json' -d '[]'

kill %1
```

- [ ] **Step 5: Commit**

```bash
git add app.py
git commit -m "feat: add JSON persistence endpoints for quotes, settings, customers"
```

---

## Task 3: Add Material Multipliers to Settings Data

Extend the materials in `data/settings.json` with `time_multiplier` and `weight_multiplier` fields.

**Files:**
- Modify: `data/settings.json`

- [ ] **Step 1: Add multipliers to each material entry**

Edit `data/settings.json`. For each material in the `materials` array, add `time_multiplier` and `weight_multiplier`. Use these values:

| Material | time_multiplier | weight_multiplier |
|----------|----------------|-------------------|
| PLA+ | 1.0 | 1.0 |
| PETG | 1.3 | 1.02 |
| TPU | 1.8 | 0.85 |
| PETG-CF | 1.3 | 0.83 |
| ABS | 1.1 | 1.02 |
| ASA | 1.15 | 1.02 |
| LW PLA HT | 1.0 | 1.0 |
| LW PLA | 1.0 | 1.0 |
| PA12 | 1.4 | 1.0 |

For example, the PETG entry changes from:
```json
{"name":"PETG","complexity":3,"spool_price":25,"spool_kg":1,"density":1.19}
```
to:
```json
{"name":"PETG","complexity":3,"spool_price":25,"spool_kg":1,"density":1.19,"time_multiplier":1.3,"weight_multiplier":1.02}
```

Apply the same pattern to every material.

- [ ] **Step 2: Verify the JSON is valid**

```bash
python3 -c "import json; json.load(open('data/settings.json')); print('OK')"
# Expected: OK
```

- [ ] **Step 3: Commit**

```bash
git add data/settings.json
git commit -m "feat: add time/weight multipliers to material settings"
```

---

## Task 4: Add Phase Navigation and Quoting CSS to the Frontend

Set up the two-phase UI structure: slicer phase (existing) and quoting phase (new). Add the CSS from LNL3D for the quoting side, and wire up phase switching.

**Files:**
- Modify: `app.py` (the embedded HTML template)

**Source reference:** `LNL3D_QuotingSite/LNL3D_Quote.html` lines 9-450 (CSS), lines 70-130 (topbar/nav)

- [ ] **Step 1: Wrap the existing slicer HTML in a phase container**

In the HTML template inside `app.py`, find the outermost container of the slicer UI (the `<body>` content). Wrap it in a phase div:

```html
<div id="slicer-phase">
  <!-- ALL existing slicer HTML goes here -->
</div>

<div id="quoting-phase" style="display:none">
  <!-- Will be populated in later tasks -->
</div>
```

- [ ] **Step 2: Add phase transition CSS**

Add to the `<style>` section in the HTML template:

```css
/* ── Phase containers ── */
#slicer-phase, #quoting-phase {
  min-height: 100vh;
}
#quoting-phase {
  font-family: 'DM Sans', sans-serif;
}

/* ── Phase transition ── */
.phase-hidden { display: none !important; }
```

- [ ] **Step 3: Add the quoting phase topbar and nav tabs HTML skeleton**

Inside the `#quoting-phase` div:

```html
<div class="app">
  <div class="topbar">
    <div class="topbar-logo" onclick="showPhase('slicer')">
      <span>LNL3D</span> Quote
      <span class="logo-badge">BETA</span>
    </div>
    <div class="nav">
      <button class="nav-tab active" onclick="showQTab('dashboard')">Dashboard</button>
      <button class="nav-tab" onclick="showQTab('quote')">New Quote</button>
      <button class="nav-tab" onclick="showQTab('log')">Quote Log</button>
      <button class="nav-tab" onclick="showQTab('customers')">Customers</button>
      <button class="nav-tab" onclick="showQTab('settings')">Settings</button>
    </div>
    <div class="topbar-actions">
      <button class="btn btn-ghost" onclick="showPhase('slicer')">&#8592; Back to Slicer</button>
    </div>
  </div>
  <div class="main">
    <div id="qtab-dashboard"></div>
    <div id="qtab-quote" style="display:none"></div>
    <div id="qtab-log" style="display:none"></div>
    <div id="qtab-customers" style="display:none"></div>
    <div id="qtab-settings" style="display:none"></div>
  </div>
</div>
```

- [ ] **Step 4: Add phase switching JavaScript**

Add to the `<script>` section:

```javascript
// ── Phase navigation ─────────────────────────────────────────
function showPhase(phase) {
  document.getElementById('slicer-phase').classList.toggle('phase-hidden', phase !== 'slicer');
  document.getElementById('quoting-phase').classList.toggle('phase-hidden', phase !== 'quoting');
  if (phase === 'quoting') {
    loadQuotingState();
  }
}

function showQTab(tab) {
  const tabs = ['dashboard', 'quote', 'log', 'customers', 'settings'];
  tabs.forEach(t => {
    const el = document.getElementById('qtab-' + t);
    if (el) el.style.display = (t === tab) ? '' : 'none';
  });
  // Update nav tab active state
  document.querySelectorAll('#quoting-phase .nav-tab').forEach((btn, i) => {
    btn.classList.toggle('active', tabs[i] === tab);
  });
}
```

- [ ] **Step 5: Add the LNL3D CSS design tokens and component styles**

Copy the CSS from `LNL3D_QuotingSite/LNL3D_Quote.html` lines 9-450 into the `<style>` section of the HTML template in `app.py`. Scope it under `#quoting-phase` to avoid conflicts with slicer styles:

```css
/* ═══════════════════════════════════════════════════════════════
   QUOTING PHASE STYLES (from LNL3D)
═══════════════════════════════════════════════════════════════ */
#quoting-phase {
  /* Design tokens are already similar (both dark themes).
     Only add styles that don't conflict with slicer styles. */
}
#quoting-phase .topbar { /* ... copy from LNL3D ... */ }
#quoting-phase .nav-tab { /* ... copy from LNL3D ... */ }
#quoting-phase .btn { /* ... copy from LNL3D ... */ }
/* ... etc — copy all component styles from LNL3D, prefixed with #quoting-phase */
```

Since both apps use similar dark themes with nearly identical CSS variable names, many styles will work naturally. Focus on copying: topbar, nav tabs, buttons, form inputs, tables, cards, modals, and the edit-table styles used in settings.

- [ ] **Step 6: Add Google Fonts link for quoting typography**

In the `<head>` section of the HTML template, add:

```html
<link rel="preconnect" href="https://fonts.googleapis.com">
<link href="https://fonts.googleapis.com/css2?family=DM+Mono:wght@400;500&family=Syne:wght@400;600;700;800&family=DM+Sans:wght@300;400;500;600&display=swap" rel="stylesheet">
```

- [ ] **Step 7: Test phase switching**

```bash
python3 app.py &
sleep 2
# Open http://localhost:5111 in browser
# Verify slicer UI loads normally
# Open browser console, run: showPhase('quoting')
# Verify quoting phase shows with topbar and empty tabs
# Run: showPhase('slicer')
# Verify slicer returns
kill %1
```

- [ ] **Step 8: Commit**

```bash
git add app.py
git commit -m "feat: add two-phase UI structure with slicer/quoting navigation"
```

---

## Task 5: Integrate the Quoting State Management and Calculation Engine

Port the LNL3D quoting JavaScript: state management, `calcFromQuoteData`, helper functions, and server sync.

**Files:**
- Modify: `app.py` (the `<script>` section of the HTML template)

**Source reference:** `LNL3D_QuotingSite/LNL3D_Quote.html` lines 1440-1815 (state + calc engine)

- [ ] **Step 1: Add the quoting state object and server sync functions**

Add to the `<script>` section in the HTML template. Use a `Q` namespace prefix to avoid collisions with slicer JS globals:

```javascript
// ══════════════════════════════════════════════════════════════
// QUOTING ENGINE (ported from LNL3D_Quote.html)
// ══════════════════════════════════════════════════════════════

let qState = { settings: null, quotes: [], customers: [] };

async function loadQuotingState() {
  try {
    const [settings, quotes, customers] = await Promise.all([
      fetch('/api/qdata/settings').then(r => r.json()),
      fetch('/api/qdata/quotes').then(r => r.json()),
      fetch('/api/qdata/customers').then(r => r.json()),
    ]);
    qState.settings = settings;
    qState.quotes = quotes || [];
    qState.customers = customers || [];
    // Apply defaults for any missing multiplier fields
    (qState.settings.materials || []).forEach(m => {
      if (m.time_multiplier == null) m.time_multiplier = 1.0;
      if (m.weight_multiplier == null) m.weight_multiplier = 1.0;
    });
  } catch (e) {
    console.error('Failed to load quoting state:', e);
  }
}

function saveQuotingState() {
  localStorage.setItem('lnl3d_settings', JSON.stringify(qState.settings));
  localStorage.setItem('lnl3d_quotes', JSON.stringify(qState.quotes));
  localStorage.setItem('lnl3d_customers', JSON.stringify(qState.customers));
  // Fire-and-forget server saves
  fetch('/api/qdata/settings', { method: 'POST', headers: {'Content-Type':'application/json'}, body: JSON.stringify(qState.settings) }).catch(() => {});
  fetch('/api/qdata/quotes', { method: 'POST', headers: {'Content-Type':'application/json'}, body: JSON.stringify(qState.quotes) }).catch(() => {});
  fetch('/api/qdata/customers', { method: 'POST', headers: {'Content-Type':'application/json'}, body: JSON.stringify(qState.customers) }).catch(() => {});
}
```

- [ ] **Step 2: Add helper functions from LNL3D**

Copy these helper functions from `LNL3D_Quote.html` (adapting `state` → `qState`):

```javascript
function qGetMaterial(name) {
  return (qState.settings?.materials || []).find(m => m.name === name) || null;
}

function qGetPrinter(name) {
  return (qState.settings?.printers || []).find(p => p.name === name) || null;
}

function qParseTime(str) {
  // Parse "HH:MM" or decimal hours → decimal hours
  if (!str) return 0;
  if (str.includes(':')) {
    const [h, m] = str.split(':').map(Number);
    return h + (m || 0) / 60;
  }
  return parseFloat(str) || 0;
}

function qGetMarkupForQty(qty) {
  const tiers = qState.settings?.discounts || [];
  let markup = qState.settings?.min_markup || 1.2;
  for (const t of tiers) {
    if (qty >= t.qty) markup = t.markup;
  }
  return Math.max(markup, qState.settings?.min_markup || 1.2);
}

function qCur(n) { return (qState.settings?.currency || '$') + (n||0).toFixed(2); }
function qCur2(n) { return (qState.settings?.currency || '$') + (n||0).toFixed(2); }
function qFmtSerial(n) { return String(n).padStart(3, '0'); }
```

- [ ] **Step 3: Port the calcFromQuoteData function**

Copy `calcFromQuoteData` from `LNL3D_Quote.html` lines 1717-1815. Rename to `qCalcFromQuoteData` and change all references from `state` to `qState`, `getMaterial` to `qGetMaterial`, `getPrinter` to `qGetPrinter`, `getMarkupForQty` to `qGetMarkupForQty`, `parseTime` to `qParseTime`:

```javascript
function qCalcFromQuoteData(q) {
  const s = qState.settings;
  const mat = qGetMaterial(q.filament);
  const prt = qGetPrinter(q.printer);
  const suppMat = q.support_filament ? qGetMaterial(q.support_filament) : null;

  const weightKg   = (q.weight_g || 0) / 1000;
  const printH     = qParseTime(q.print_time);
  const complexity = parseFloat(q.complexity || 1);
  const qty        = Math.max(parseInt(q.quantity || 1), 1);
  const rush       = parseFloat(q.rush || 1.0);
  const prepMin    = (parseFloat(q.prep_model||0) + parseFloat(q.prep_slice||0));
  const postMin    = (parseFloat(q.post_remove||0) + parseFloat(q.post_support||0) + parseFloat(q.post_extra||0));
  const finishing   = (parseFloat(q.fin_sand||0) + parseFloat(q.fin_paint||0) + parseFloat(q.fin_hardware||0) + parseFloat(q.fin_other||0));
  const shipping    = (parseFloat(q.ship_pack||0) + parseFloat(q.ship_cost||0));
  const consumables = parseFloat(q.consumables||0);

  const filamentCost = mat ? weightKg * (mat.spool_price / mat.spool_kg) : 0;
  const filComplexity = mat ? mat.complexity : 1;
  const suppWeightKg = (q.support_weight_g || 0) / 1000;
  const suppCost = (suppMat && suppWeightKg) ? suppWeightKg * (suppMat.spool_price / suppMat.spool_kg) : 0;

  const deprRate = prt ? (prt.price + prt.service) / prt.life : 0;
  const elecCost = prt ? printH * prt.energy * s.energy : 0;
  const deprCost = printH * deprRate;

  const fail = Math.min(s.base_fail + ((complexity + filComplexity - 2) / 18) * (s.max_fail - s.base_fail), s.max_fail);

  const machinePP = (filamentCost + suppCost + elecCost + deprCost + consumables) * (1 + fail);

  const prepLabor = (prepMin / 60) * s.skilled_labor;
  const postLabor = (postMin / 60) * s.postprocess_labor;
  const prepPP    = (prepLabor * (1 + fail / 4)) / qty;
  const postPP    = postLabor * (1 + fail);
  const laborPP   = prepPP + postPP;

  const finPP  = finishing / qty;
  const shipPP = shipping / qty;

  const costPP = machinePP + laborPP + finPP + shipPP;

  const baseMarkup = qGetMarkupForQty(qty);
  const markup = baseMarkup * rush;
  const suggested = Math.max(costPP * qty * markup, s.min_fee);
  const quotedRaw = parseFloat(q.quoted_price || 0);
  const quoted = quotedRaw > 0 ? quotedRaw : 0;

  const pricePP    = suggested / qty;
  const profitPP   = Math.max(pricePP - costPP, 0);
  const margin     = pricePP > 0 ? Math.max((pricePP - costPP) / pricePP, 0) : 0;
  const costTotal  = costPP * qty;
  const totalProfit = quoted > 0 ? Math.max(quoted - costTotal, 0) : Math.max(suggested - costTotal, 0);

  const schedule = (s.discounts || []).map(tier => {
    const tQty  = Math.max(tier.qty, 1);
    const tMkup = Math.max(tier.markup, s.min_markup) * rush;
    const tPrepPP = (prepLabor * (1 + fail / 4)) / tQty;
    const tFinPP  = finishing / tQty;
    const tShipPP = shipping / tQty;
    const tCostPP = machinePP + tPrepPP + postPP + tFinPP + tShipPP;
    const tPriceRaw = tCostPP * tMkup;
    const tTotal   = Math.max(tPriceRaw * tQty, s.min_fee);
    const tPricePP = tTotal / tQty;
    const tMargin  = tPricePP > 0 ? Math.max((tPricePP - tCostPP) / tPricePP, 0) : 0;
    return { qty: tier.qty, markup: tMkup, costPP: tCostPP, pricePP: tPricePP, total: tTotal, margin: tMargin };
  });

  const matComparison = (s.materials || []).map(m2 => {
    const fc2   = weightKg * (m2.spool_price / m2.spool_kg);
    const fail2 = Math.min(s.base_fail + ((complexity + m2.complexity - 2) / 18) * (s.max_fail - s.base_fail), s.max_fail);
    const mach2 = (fc2 + suppCost + elecCost + deprCost + consumables) * (1 + fail2);
    const prep2 = (prepLabor * (1 + fail2 / 4)) / qty;
    const post2 = postLabor * (1 + fail2);
    const cost2 = mach2 + prep2 + post2 + finPP + shipPP;
    const total2 = Math.max(cost2 * markup * qty, s.min_fee);
    const price2 = total2 / qty;
    return { name: m2.name, pricePP: price2, total: total2, current: m2.name === q.filament };
  });

  return {
    filamentCost, suppCost, elecCost, deprCost, consumables,
    prepLabor, postLabor, finishing, shipping,
    fail, machinePP, laborPP, costPP, baseMarkup, markup,
    suggested, quoted, pricePP, profitPP, margin, costTotal, totalProfit,
    schedule, matComparison, qty, rush
  };
}
```

- [ ] **Step 4: Add the quick-quote calculation function (uses multipliers)**

This is the new function that takes slicer baseline data and applies material multipliers before feeding into the full calc engine:

```javascript
function qCalcQuickQuote(slicerData, overrides) {
  // slicerData: { base_weight_g, base_time_minutes, filename }
  // overrides: { printer, filament, quantity }
  const mat = qGetMaterial(overrides.filament);
  const timeMult = mat?.time_multiplier || 1.0;
  const weightMult = mat?.weight_multiplier || 1.0;

  const adjWeightG = slicerData.base_weight_g * weightMult;
  const adjTimeMins = slicerData.base_time_minutes * timeMult;
  const adjTimeH = Math.floor(adjTimeMins / 60);
  const adjTimeM = Math.round(adjTimeMins % 60);
  const printTimeStr = adjTimeH + ':' + String(adjTimeM).padStart(2, '0');

  // Build a minimal quote data object for the calc engine
  const q = {
    printer: overrides.printer,
    filament: overrides.filament,
    weight_g: adjWeightG,
    print_time: printTimeStr,
    complexity: mat?.complexity || 1,
    quantity: overrides.quantity || 1,
    rush: 1.0,
    // No labor/finishing/shipping in quick quote
    prep_model: 0, prep_slice: 0,
    post_remove: 0, post_support: 5, post_extra: 0,
    fin_sand: 0, fin_paint: 0, fin_hardware: 0, fin_other: 0,
    ship_pack: 0, ship_cost: 0,
    consumables: 0,
  };

  const calc = qCalcFromQuoteData(q);
  return {
    ...calc,
    adjWeightG,
    adjTimeMins,
    printTimeStr,
    filename: slicerData.filename,
    base_weight_g: slicerData.base_weight_g,
    base_time_minutes: slicerData.base_time_minutes,
  };
}
```

- [ ] **Step 5: Test the calc engine in the browser console**

```bash
python3 app.py &
sleep 2
# Open http://localhost:5111 in browser
# Open console and run:
#   await loadQuotingState();
#   console.log(qState.settings.materials[0]);  // should show PLA+ with multipliers
#   const result = qCalcQuickQuote(
#     { base_weight_g: 42.3, base_time_minutes: 135, filename: 'test.stl' },
#     { printer: 'Tenlog TL-D3', filament: 'PLA+', quantity: 1 }
#   );
#   console.log(result.suggested, result.costPP, result.fail);
# Expected: numeric values (suggested > costPP > 0)
kill %1
```

- [ ] **Step 6: Commit**

```bash
git add app.py
git commit -m "feat: port quoting state management and calculation engine"
```

---

## Task 6: Build the Quick Quote View

Create the quick quote UI that appears after slicing. Shows cost breakdown with editable printer/filament/qty/customer dropdowns.

**Files:**
- Modify: `app.py` (HTML template — add Quick Quote HTML + JS)

- [ ] **Step 1: Add the Quick Quote overlay HTML**

Add inside the `#slicer-phase` div (it overlays the slicer results):

```html
<div id="quick-quote-overlay" style="display:none">
  <div class="qq-container">
    <div class="qq-header">
      <h2>Quick Quote</h2>
      <button class="btn btn-ghost" onclick="closeQuickQuote()">&#8592; Back to Slicer</button>
    </div>

    <div id="qq-items">
      <!-- Populated by JS: one card per sliced file -->
    </div>

    <div class="qq-totals" id="qq-totals" style="display:none">
      <!-- Batch total row -->
    </div>

    <div class="qq-customer-row">
      <label>Customer</label>
      <input id="qq-customer" list="qq-customer-list" placeholder="Select or type customer name..." autocomplete="off">
      <datalist id="qq-customer-list"></datalist>
    </div>

    <div class="qq-actions">
      <button class="btn btn-primary" onclick="logQuickQuote()">Log Quote</button>
      <button class="btn btn-ghost" onclick="openFullQuoteForm()">Full Details &#8594;</button>
      <button class="btn btn-ghost" onclick="closeQuickQuote()">Cancel</button>
    </div>
  </div>
</div>
```

- [ ] **Step 2: Add Quick Quote CSS**

Add to the `<style>` section:

```css
/* ── Quick Quote Overlay ── */
#quick-quote-overlay {
  position: fixed; inset: 0;
  background: rgba(0,0,0,0.7);
  z-index: 1000;
  display: flex; align-items: flex-start; justify-content: center;
  padding: 40px 20px;
  overflow-y: auto;
}
.qq-container {
  background: #161b22;
  border: 1px solid #30363d;
  border-radius: 12px;
  padding: 28px;
  width: 100%; max-width: 700px;
  box-shadow: 0 8px 32px rgba(0,0,0,.6);
}
.qq-header {
  display: flex; justify-content: space-between; align-items: center;
  margin-bottom: 20px;
}
.qq-header h2 { font-family: 'Syne', sans-serif; font-size: 20px; font-weight: 700; }

.qq-item {
  background: #0d1117;
  border: 1px solid #30363d;
  border-radius: 8px;
  padding: 16px;
  margin-bottom: 12px;
}
.qq-item-filename {
  font-family: 'DM Mono', monospace;
  font-size: 13px;
  color: #388bfd;
  margin-bottom: 10px;
}
.qq-item-controls {
  display: flex; gap: 8px; margin-bottom: 12px;
}
.qq-item-controls select, .qq-item-controls input {
  background: #21262d; border: 1px solid #30363d; color: #e6edf3;
  padding: 6px 10px; border-radius: 6px; font-size: 13px;
  font-family: 'DM Sans', sans-serif;
}
.qq-item-controls select { flex: 1; }
.qq-item-controls input[type="number"] { width: 70px; text-align: center; }

.qq-breakdown {
  background: #161b22;
  border: 1px solid #21262d;
  border-radius: 6px;
  padding: 10px 12px;
  font-size: 13px;
  font-family: 'DM Mono', monospace;
}
.qq-row {
  display: flex; justify-content: space-between; padding: 2px 0;
}
.qq-row.qq-label { color: #8b949e; }
.qq-row.qq-total {
  border-top: 1px solid #30363d;
  margin-top: 6px; padding-top: 8px;
  font-size: 16px; font-weight: 700;
}
.qq-row.qq-total .qq-price { color: #ff9f43; }
.qq-row.qq-sub { font-size: 12px; color: #8b949e; }

.qq-customer-row {
  margin: 16px 0;
  display: flex; align-items: center; gap: 12px;
}
.qq-customer-row label {
  font-size: 13px; color: #8b949e; min-width: 70px;
}
.qq-customer-row input {
  flex: 1; background: #21262d; border: 1px solid #30363d; color: #e6edf3;
  padding: 8px 12px; border-radius: 6px; font-size: 13px;
  font-family: 'DM Sans', sans-serif;
}

.qq-actions {
  display: flex; gap: 8px; justify-content: flex-end;
  padding-top: 16px; border-top: 1px solid #30363d;
}

.qq-totals {
  background: #0d1117; border: 1px solid #30363d; border-radius: 8px;
  padding: 12px 16px; margin-bottom: 12px;
  font-family: 'DM Mono', monospace;
}
```

- [ ] **Step 3: Add Quick Quote rendering JavaScript**

```javascript
// ── Quick Quote state ────────────────────────────────────────
let qqItems = []; // Array of { slicerData, printer, filament, quantity, calc }

function openQuickQuote(slicerResults) {
  // slicerResults: array of { filename, weight_g, time_minutes, job_id }
  // (from slicer /api/quote responses)
  qqItems = slicerResults.map(r => ({
    slicerData: {
      base_weight_g: r.weight_g,
      base_time_minutes: r.time_minutes,
      filename: r.filename,
      job_id: r.job_id,
    },
    printer: qState.settings?.printers?.[0]?.name || '',
    filament: (qState.settings?.materials || []).find(m => m.name.includes('PLA'))?.name
              || qState.settings?.materials?.[0]?.name || '',
    quantity: 1,
    calc: null,
  }));

  renderQuickQuote();
  document.getElementById('quick-quote-overlay').style.display = 'flex';

  // Populate customer datalist
  const dl = document.getElementById('qq-customer-list');
  dl.innerHTML = (qState.customers || []).map(c =>
    '<option value="' + (c.name || '') + '">'
  ).join('');
}

function closeQuickQuote() {
  document.getElementById('quick-quote-overlay').style.display = 'none';
}

function renderQuickQuote() {
  const container = document.getElementById('qq-items');
  const s = qState.settings;
  const printerOpts = (s?.printers || []).map(p =>
    '<option value="' + p.name + '">' + p.name + '</option>'
  ).join('');
  const matOpts = (s?.materials || []).map(m =>
    '<option value="' + m.name + '">' + m.name + '</option>'
  ).join('');

  let totalSuggested = 0;
  let totalCost = 0;
  let totalTimeMins = 0;
  let totalWeightG = 0;

  container.innerHTML = qqItems.map((item, i) => {
    const calc = qCalcQuickQuote(item.slicerData, {
      printer: item.printer,
      filament: item.filament,
      quantity: item.quantity,
    });
    item.calc = calc;
    totalSuggested += calc.suggested;
    totalCost += calc.costTotal;
    totalTimeMins += calc.adjTimeMins;
    totalWeightG += calc.adjWeightG;

    const timeStr = Math.floor(calc.adjTimeMins / 60) + 'h ' + Math.round(calc.adjTimeMins % 60) + 'm';

    return '<div class="qq-item">'
      + '<div class="qq-item-filename">' + item.slicerData.filename + '</div>'
      + '<div class="qq-item-controls">'
      + '  <select onchange="qqUpdateItem(' + i + ',\'printer\',this.value)">'
      +    printerOpts.replace('value="' + item.printer + '"', 'value="' + item.printer + '" selected')
      + '  </select>'
      + '  <select onchange="qqUpdateItem(' + i + ',\'filament\',this.value)">'
      +    matOpts.replace('value="' + item.filament + '"', 'value="' + item.filament + '" selected')
      + '  </select>'
      + '  <input type="number" min="1" value="' + item.quantity + '" onchange="qqUpdateItem(' + i + ',\'quantity\',+this.value)">'
      + '</div>'
      + '<div class="qq-breakdown">'
      + '  <div class="qq-row"><span class="qq-label">Print Time</span><span>' + timeStr + '</span></div>'
      + '  <div class="qq-row"><span class="qq-label">Weight</span><span>' + calc.adjWeightG.toFixed(1) + ' g</span></div>'
      + '  <div class="qq-row"><span class="qq-label">Material</span><span>' + qCur(calc.filamentCost) + '</span></div>'
      + '  <div class="qq-row"><span class="qq-label">Machine</span><span>' + qCur(calc.elecCost + calc.deprCost) + '</span></div>'
      + '  <div class="qq-row"><span class="qq-label">Failure adj.</span><span>+' + qCur(calc.machinePP - (calc.filamentCost + calc.elecCost + calc.deprCost)) + '</span></div>'
      + '  <div class="qq-row" style="border-top:1px solid #30363d;margin-top:4px;padding-top:4px"><span class="qq-label">Cost/pc</span><span>' + qCur(calc.costPP) + '</span></div>'
      + '  <div class="qq-row"><span class="qq-label">Markup (' + calc.markup.toFixed(1) + 'x)</span><span>+' + qCur(calc.pricePP - calc.costPP) + '</span></div>'
      + '  <div class="qq-row qq-total"><span>Quote Price</span><span class="qq-price">' + qCur(calc.suggested) + '</span></div>'
      + '  <div class="qq-row qq-sub"><span>Margin: ' + (calc.margin * 100).toFixed(0) + '%</span><span>Profit/pc: ' + qCur(calc.profitPP) + '</span></div>'
      + '</div>'
      + '</div>';
  }).join('');

  // Show totals row if batch (multiple items)
  const totalsEl = document.getElementById('qq-totals');
  if (qqItems.length > 1) {
    const totalTimeStr = Math.floor(totalTimeMins / 60) + 'h ' + Math.round(totalTimeMins % 60) + 'm';
    totalsEl.style.display = '';
    totalsEl.innerHTML = '<div class="qq-row" style="font-weight:700"><span>Total (' + qqItems.length + ' items)</span><span></span></div>'
      + '<div class="qq-row"><span class="qq-label">Total Time</span><span>' + totalTimeStr + '</span></div>'
      + '<div class="qq-row"><span class="qq-label">Total Weight</span><span>' + totalWeightG.toFixed(1) + ' g</span></div>'
      + '<div class="qq-row qq-total"><span>Total Price</span><span class="qq-price">' + qCur(totalSuggested) + '</span></div>';
  } else {
    totalsEl.style.display = 'none';
  }
}

function qqUpdateItem(index, field, value) {
  qqItems[index][field] = value;
  renderQuickQuote();
}
```

- [ ] **Step 4: Test the quick quote overlay manually**

```bash
python3 app.py &
sleep 2
# Open http://localhost:5111 in browser
# Open console, run:
#   await loadQuotingState();
#   openQuickQuote([
#     { filename: 'bracket.stl', weight_g: 42.3, time_minutes: 135, job_id: 'abc123' },
#     { filename: 'housing.stl', weight_g: 89.1, time_minutes: 270, job_id: 'def456' }
#   ]);
# Expected: Quick quote overlay appears with 2 item cards, each with cost breakdown
# Change filament dropdown → numbers should update (multipliers applied)
# Change quantity → price should update
kill %1
```

- [ ] **Step 5: Commit**

```bash
git add app.py
git commit -m "feat: build quick quote overlay with cost breakdown and editable controls"
```

---

## Task 7: Wire Slicer Results to Quick Quote

Connect the existing slicer flow so that after slicing completes, the Quick Quote overlay opens automatically with the slicer results.

**Files:**
- Modify: `app.py` (the existing slicer JavaScript — `showResults` and `showBatchResults` functions)

- [ ] **Step 1: Add a helper to extract baseline data from slicer response**

```javascript
function extractSlicerBaseline(d) {
  // d = response from /api/quote
  // Parse total time to minutes
  let timeMins = 0;
  const timeStr = d.time || '';
  const dm = timeStr.match(/(\d+)d/);
  const hm = timeStr.match(/(\d+)h/);
  const mm = timeStr.match(/(\d+)m/);
  if (dm) timeMins += parseInt(dm[1]) * 1440;
  if (hm) timeMins += parseInt(hm[1]) * 60;
  if (mm) timeMins += parseInt(mm[1]);

  return {
    filename: d.filename,
    weight_g: d.weight_g || 0,
    time_minutes: timeMins,
    job_id: d.job_id || '',
  };
}
```

- [ ] **Step 2: Store slicer results for handoff**

Add a global to accumulate results during batch slicing:

```javascript
let _slicerResultsForQuote = [];
```

- [ ] **Step 3: Modify the single-file result flow**

Find where `showResults(d)` is called after a successful `/api/quote` response. After the existing results display logic, add a "Send to Quote" button to the results panel, AND auto-open the quick quote:

In the existing `showResults(d)` function, find the section that builds action buttons (near the end, where "Copy Quote" and "Download GCode" buttons are). Add a new button:

```javascript
// Add after existing action buttons in showResults():
html += '<button class="action-btn" onclick="sendToQuickQuote()">Send to Quote &#8594;</button>';
```

And add the handler:

```javascript
function sendToQuickQuote() {
  if (_slicerResultsForQuote.length === 0) return;
  loadQuotingState().then(() => {
    openQuickQuote(_slicerResultsForQuote);
  });
}
```

- [ ] **Step 4: Capture slicer results during slicing**

In the `_runBatchSlice` function (or wherever `/api/quote` responses are processed), capture each result:

At the start of `runBatch()` or `_runBatchSlice()`, reset the accumulator:
```javascript
_slicerResultsForQuote = [];
```

After each successful `/api/quote` response is received, push the baseline:
```javascript
_slicerResultsForQuote.push(extractSlicerBaseline(data));
```

- [ ] **Step 5: Also add "Send to Quote" to batch results**

In `showBatchResults()`, find where the batch summary table is rendered. Add a prominent button below the table:

```javascript
// At the end of showBatchResults(), add:
html += '<div style="margin-top:16px;text-align:center">'
     +  '<button class="action-btn" style="font-size:15px;padding:10px 24px" onclick="sendToQuickQuote()">'
     +  'Send All to Quote &#8594;</button></div>';
```

- [ ] **Step 6: Test the full slicer → quick quote flow**

```bash
python3 app.py &
sleep 2
# Open http://localhost:5111
# Upload a test STL file
# Select printer/profile, click Generate Quote
# Wait for slicing to complete
# Verify "Send to Quote →" button appears in results
# Click it → Quick Quote overlay should open with the sliced file's data
# Verify weight and time match slicer output
# Change filament → verify numbers update with multipliers
kill %1
```

- [ ] **Step 7: Commit**

```bash
git add app.py
git commit -m "feat: wire slicer results to quick quote overlay"
```

---

## Task 8: Implement Quote Logging from Quick Quote

Add the ability to log a quote directly from the Quick Quote view, saving it to the quotes JSON with a generated quote ID.

**Files:**
- Modify: `app.py` (JavaScript section)

- [ ] **Step 1: Add the logQuickQuote function**

```javascript
function logQuickQuote() {
  const customer = document.getElementById('qq-customer').value.trim();
  if (!customer) {
    alert('Please enter a customer name.');
    return;
  }
  if (qqItems.length === 0) return;

  const s = qState.settings;
  const serial = s.next_serial || 1;
  const dateStr = new Date().toISOString().slice(0, 10);
  const custInitials = customer.replace(/\\s/g, '').slice(0, 3).toUpperCase();
  const quoteId = qFmtSerial(serial) + '-' + dateStr.replace(/-/g, '') + '-' + custInitials;

  // Build line items
  const lineItems = qqItems.map(item => {
    const calc = item.calc;
    return {
      filename: item.slicerData.filename,
      printer: item.printer,
      filament: item.filament,
      base_weight_g: item.slicerData.base_weight_g,
      base_time_minutes: item.slicerData.base_time_minutes,
      weight_g: calc.adjWeightG,
      print_time: calc.printTimeStr,
      quantity: item.quantity,
      job_id: item.slicerData.job_id,
      suggested: calc.suggested,
      costPP: calc.costPP,
      pricePP: calc.pricePP,
      margin: calc.margin,
    };
  });

  const totalSuggested = lineItems.reduce((s, li) => s + li.suggested, 0);
  const totalWeightG = lineItems.reduce((s, li) => s + li.weight_g, 0);

  const entry = {
    serial,
    quote_id: quoteId,
    customer,
    date: dateStr,
    status: 'Quoting',
    logged_at: new Date().toISOString(),
    description: lineItems.map(li => li.filename).join(', '),
    line_items: lineItems,
    // Top-level aggregates for backwards compat with quote log display
    filament: lineItems[0]?.filament || '',
    printer: lineItems[0]?.printer || '',
    weight_g: totalWeightG,
    quantity: lineItems.reduce((s, li) => s + li.quantity, 0),
    calc_cost_pp: lineItems.length === 1 ? lineItems[0].costPP : null,
    calc_suggested: totalSuggested,
    calc_margin: lineItems.length === 1 ? lineItems[0].margin : null,
    calc_profit: totalSuggested - lineItems.reduce((s, li) => s + li.costPP * li.quantity, 0),
  };

  qState.quotes.push(entry);
  s.next_serial = serial + 1;

  // Ensure customer exists
  if (!qState.customers.find(c => c.name === customer)) {
    qState.customers.push({
      id: Date.now(),
      name: customer,
      company: '',
      email: '',
      phone: '',
      notes: '',
      created: new Date().toISOString(),
    });
  }

  saveQuotingState();
  closeQuickQuote();
  alert('Quote #' + qFmtSerial(serial) + ' logged for ' + customer + ' — ' + qCur(totalSuggested));
}
```

- [ ] **Step 2: Add the openFullQuoteForm function (transitions to quoting phase)**

```javascript
function openFullQuoteForm() {
  // Transition to quoting phase with the first item's data pre-filled
  const customer = document.getElementById('qq-customer').value.trim();
  const item = qqItems[0];
  if (!item) return;

  closeQuickQuote();
  showPhase('quoting');
  showQTab('quote');

  // Pre-fill the quote form (will be wired in Task 10)
  if (typeof prefillQuoteForm === 'function') {
    prefillQuoteForm({
      customer,
      printer: item.printer,
      filament: item.filament,
      weight_g: item.calc.adjWeightG,
      print_time: item.calc.printTimeStr,
      quantity: item.quantity,
      line_items: qqItems,
    });
  }
}
```

- [ ] **Step 3: Test quote logging**

```bash
python3 app.py &
sleep 2
# Open http://localhost:5111
# In browser console:
#   await loadQuotingState();
#   openQuickQuote([{ filename: 'test.stl', weight_g: 42, time_minutes: 135, job_id: 'x' }]);
# Type a customer name, click "Log Quote"
# Verify alert shows quote was logged
# Check: curl http://localhost:5111/api/qdata/quotes | python3 -m json.tool
# Expected: array with one entry containing serial, quote_id, line_items, etc.
kill %1
```

- [ ] **Step 4: Commit**

```bash
git add app.py
git commit -m "feat: implement quote logging from quick quote view"
```

---

## Task 9: Integrate the Settings Tab

Port the LNL3D Settings tab into the quoting phase, including the materials table with the new multiplier columns.

**Files:**
- Modify: `app.py` (HTML template — `#qtab-settings` content + JS)

**Source reference:** `LNL3D_QuotingSite/LNL3D_Quote.html` lines 1044-1130 (settings HTML), lines 3113-3200 (renderSettings JS)

- [ ] **Step 1: Add Settings tab HTML**

Populate the `#qtab-settings` div with the settings form. Copy the structure from `LNL3D_Quote.html` lines 1044-1130, adapting IDs to use `q-` prefix to avoid collisions:

```html
<div id="qtab-settings">
  <h2 style="font-family:var(--font-head);margin-bottom:20px">Settings</h2>

  <div class="settings-grid">
    <!-- Company -->
    <div class="settings-section">
      <h3>Company</h3>
      <label>Company Name <input id="q-set-company" onchange="qUpdateSetting('company',this.value)"></label>
      <label>Currency Symbol <input id="q-set-currency" style="width:60px" onchange="qUpdateSetting('currency',this.value)"></label>
    </div>

    <!-- Cost Factors -->
    <div class="settings-section">
      <h3>Cost Factors</h3>
      <label>Energy Rate ($/kWh) <input type="number" step="0.01" id="q-set-energy" onchange="qUpdateSetting('energy',+this.value)"></label>
      <label>Skilled Labor ($/hr) <input type="number" id="q-set-skilled" onchange="qUpdateSetting('skilled_labor',+this.value)"></label>
      <label>Post-Process Labor ($/hr) <input type="number" id="q-set-postprocess" onchange="qUpdateSetting('postprocess_labor',+this.value)"></label>
      <label>Base Failure Rate <input type="number" step="0.01" id="q-set-basefail" onchange="qUpdateSetting('base_fail',+this.value)"></label>
      <label>Max Failure Rate <input type="number" step="0.01" id="q-set-maxfail" onchange="qUpdateSetting('max_fail',+this.value)"></label>
      <label>Min Fee ($) <input type="number" id="q-set-minfee" onchange="qUpdateSetting('min_fee',+this.value)"></label>
    </div>
  </div>

  <!-- Discount Tiers -->
  <h3 style="margin-top:24px">Discount Tiers</h3>
  <table class="edit-table" id="q-discounts-table">
    <thead><tr><th>Min Qty</th><th>Markup</th><th></th></tr></thead>
    <tbody id="q-discounts-body"></tbody>
  </table>
  <button class="btn btn-ghost" onclick="qAddDiscountRow()" style="margin-top:6px">+ Add Tier</button>

  <!-- Printers -->
  <h3 style="margin-top:24px">Printers</h3>
  <table class="edit-table" id="q-printers-table">
    <thead><tr><th>Name</th><th>Price ($)</th><th>Life (h)</th><th>Service ($)</th><th>Energy (kWh/h)</th><th>Depr ($/h)</th><th></th></tr></thead>
    <tbody id="q-printers-body"></tbody>
  </table>
  <button class="btn btn-ghost" onclick="qAddPrinterRow()" style="margin-top:6px">+ Add Printer</button>

  <!-- Materials (with multiplier columns) -->
  <h3 style="margin-top:24px">Materials</h3>
  <table class="edit-table" id="q-materials-table">
    <thead><tr>
      <th>Name</th><th>Complexity</th><th>Spool ($)</th><th>Spool (kg)</th><th>Density</th>
      <th>Time Mult.</th><th>Weight Mult.</th>
      <th>$/kg</th><th></th>
    </tr></thead>
    <tbody id="q-materials-body"></tbody>
  </table>
  <button class="btn btn-ghost" onclick="qAddMaterialRow()" style="margin-top:6px">+ Add Material</button>

  <!-- Data Management -->
  <h3 style="margin-top:24px">Data</h3>
  <div style="display:flex;gap:8px;margin-top:8px">
    <button class="btn btn-ghost" onclick="qExportData()">Export JSON Backup</button>
    <label class="btn btn-ghost" style="cursor:pointer">Import JSON Backup <input type="file" accept=".json" onchange="qImportData(this)" style="display:none"></label>
  </div>
</div>
```

- [ ] **Step 2: Add Settings rendering JavaScript**

```javascript
function qRenderSettings() {
  const s = qState.settings;
  if (!s) return;

  // Scalars
  document.getElementById('q-set-company').value = s.company || '';
  document.getElementById('q-set-currency').value = s.currency || '$';
  document.getElementById('q-set-energy').value = s.energy || 0;
  document.getElementById('q-set-skilled').value = s.skilled_labor || 0;
  document.getElementById('q-set-postprocess').value = s.postprocess_labor || 0;
  document.getElementById('q-set-basefail').value = s.base_fail || 0;
  document.getElementById('q-set-maxfail').value = s.max_fail || 0;
  document.getElementById('q-set-minfee').value = s.min_fee || 0;

  // Discount tiers
  document.getElementById('q-discounts-body').innerHTML = (s.discounts || []).map((d, i) =>
    '<tr>'
    + '<td><input type="number" value="' + d.qty + '" data-i="' + i + '" data-f="qty" onchange="qUpdateDiscount(this)"></td>'
    + '<td><input type="number" step="0.1" value="' + d.markup + '" data-i="' + i + '" data-f="markup" onchange="qUpdateDiscount(this)"></td>'
    + '<td><button class="btn btn-danger btn-sm" onclick="qRemoveDiscount(' + i + ')">&#10005;</button></td>'
    + '</tr>'
  ).join('');

  // Printers
  document.getElementById('q-printers-body').innerHTML = (s.printers || []).map((p, i) =>
    '<tr>'
    + '<td><input value="' + p.name + '" data-i="' + i + '" data-f="name" onchange="qUpdatePrinter(this)"></td>'
    + '<td><input type="number" value="' + p.price + '" data-i="' + i + '" data-f="price" onchange="qUpdatePrinter(this)"></td>'
    + '<td><input type="number" value="' + p.life + '" data-i="' + i + '" data-f="life" onchange="qUpdatePrinter(this)"></td>'
    + '<td><input type="number" value="' + p.service + '" data-i="' + i + '" data-f="service" onchange="qUpdatePrinter(this)"></td>'
    + '<td><input type="number" step="0.01" value="' + p.energy + '" data-i="' + i + '" data-f="energy" onchange="qUpdatePrinter(this)"></td>'
    + '<td style="color:#3fb950;font-size:12px">' + ((p.price + p.service) / p.life).toFixed(4) + '</td>'
    + '<td><button class="btn btn-danger btn-sm" onclick="qRemovePrinter(' + i + ')">&#10005;</button></td>'
    + '</tr>'
  ).join('');

  // Materials (with multiplier columns)
  document.getElementById('q-materials-body').innerHTML = (s.materials || []).map((m, i) =>
    '<tr>'
    + '<td><input value="' + m.name + '" data-i="' + i + '" data-f="name" onchange="qUpdateMaterial(this)"></td>'
    + '<td><input type="number" min="1" max="10" value="' + m.complexity + '" data-i="' + i + '" data-f="complexity" onchange="qUpdateMaterial(this)"></td>'
    + '<td><input type="number" value="' + m.spool_price + '" data-i="' + i + '" data-f="spool_price" onchange="qUpdateMaterial(this)"></td>'
    + '<td><input type="number" step="0.1" value="' + m.spool_kg + '" data-i="' + i + '" data-f="spool_kg" onchange="qUpdateMaterial(this)"></td>'
    + '<td><input type="number" step="0.01" value="' + m.density + '" data-i="' + i + '" data-f="density" onchange="qUpdateMaterial(this)"></td>'
    + '<td><input type="number" step="0.05" value="' + (m.time_multiplier || 1.0) + '" data-i="' + i + '" data-f="time_multiplier" onchange="qUpdateMaterial(this)"></td>'
    + '<td><input type="number" step="0.05" value="' + (m.weight_multiplier || 1.0) + '" data-i="' + i + '" data-f="weight_multiplier" onchange="qUpdateMaterial(this)"></td>'
    + '<td style="color:#3fb950;font-size:12px">' + qCur2(m.spool_price / m.spool_kg) + '/kg</td>'
    + '<td><button class="btn btn-danger btn-sm" onclick="qRemoveMaterial(' + i + ')">&#10005;</button></td>'
    + '</tr>'
  ).join('');
}

function qUpdateSetting(key, val) {
  qState.settings[key] = val;
  saveQuotingState();
}

function qUpdateDiscount(el) {
  const i = +el.dataset.i, f = el.dataset.f;
  qState.settings.discounts[i][f] = +el.value;
  saveQuotingState();
}
function qAddDiscountRow() {
  qState.settings.discounts.push({ qty: 0, markup: 1.5 });
  saveQuotingState(); qRenderSettings();
}
function qRemoveDiscount(i) {
  qState.settings.discounts.splice(i, 1);
  saveQuotingState(); qRenderSettings();
}

function qUpdatePrinter(el) {
  const i = +el.dataset.i, f = el.dataset.f;
  qState.settings.printers[i][f] = f === 'name' ? el.value : +el.value;
  saveQuotingState(); qRenderSettings();
}
function qAddPrinterRow() {
  qState.settings.printers.push({ name: 'New Printer', price: 500, life: 4000, service: 200, energy: 0.15 });
  saveQuotingState(); qRenderSettings();
}
function qRemovePrinter(i) {
  qState.settings.printers.splice(i, 1);
  saveQuotingState(); qRenderSettings();
}

function qUpdateMaterial(el) {
  const i = +el.dataset.i, f = el.dataset.f;
  qState.settings.materials[i][f] = f === 'name' ? el.value : +el.value;
  saveQuotingState(); qRenderSettings();
}
function qAddMaterialRow() {
  qState.settings.materials.push({
    name: 'New Material', complexity: 1, spool_price: 25, spool_kg: 1,
    density: 1.24, time_multiplier: 1.0, weight_multiplier: 1.0
  });
  saveQuotingState(); qRenderSettings();
}
function qRemoveMaterial(i) {
  qState.settings.materials.splice(i, 1);
  saveQuotingState(); qRenderSettings();
}

function qExportData() {
  const blob = new Blob([JSON.stringify({ settings: qState.settings, quotes: qState.quotes, customers: qState.customers }, null, 2)], { type: 'application/json' });
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  a.download = 'lnl3d-backup-' + new Date().toISOString().slice(0, 10) + '.json';
  document.body.appendChild(a); a.click(); a.remove();
}

function qImportData(input) {
  const file = input.files[0];
  if (!file) return;
  const reader = new FileReader();
  reader.onload = function(e) {
    try {
      const data = JSON.parse(e.target.result);
      if (data.settings) qState.settings = data.settings;
      if (data.quotes) qState.quotes = data.quotes;
      if (data.customers) qState.customers = data.customers;
      saveQuotingState();
      qRenderSettings();
      alert('Data imported successfully.');
    } catch (err) {
      alert('Invalid JSON file.');
    }
  };
  reader.readAsText(file);
}
```

- [ ] **Step 3: Hook settings rendering into phase/tab navigation**

Update the `showQTab` function to trigger rendering:

```javascript
// Add to showQTab() function:
if (tab === 'settings') qRenderSettings();
```

- [ ] **Step 4: Add the edit-table CSS**

Copy the table styles from `LNL3D_Quote.html` (scoped to `#quoting-phase`):

```css
#quoting-phase .edit-table {
  width: 100%; border-collapse: collapse; margin-top: 8px;
}
#quoting-phase .edit-table th {
  text-align: left; padding: 6px 8px; font-size: 11px;
  color: #8b949e; text-transform: uppercase; letter-spacing: 0.5px;
  border-bottom: 1px solid #30363d;
}
#quoting-phase .edit-table td { padding: 4px 4px; }
#quoting-phase .edit-table input {
  background: #0d1117; border: 1px solid #30363d; color: #e6edf3;
  padding: 5px 8px; border-radius: 4px; font-size: 13px; width: 100%;
  font-family: 'DM Mono', monospace;
}
#quoting-phase .edit-table input:focus {
  border-color: #388bfd; outline: none;
}
#quoting-phase .settings-grid {
  display: grid; grid-template-columns: 1fr 1fr; gap: 20px;
}
#quoting-phase .settings-section {
  background: #161b22; border: 1px solid #30363d; border-radius: 8px; padding: 16px;
}
#quoting-phase .settings-section h3 {
  font-family: 'Syne', sans-serif; font-size: 14px; margin-bottom: 12px; color: #388bfd;
}
#quoting-phase .settings-section label {
  display: flex; justify-content: space-between; align-items: center;
  padding: 4px 0; font-size: 13px; color: #8b949e;
}
#quoting-phase .settings-section input {
  background: #0d1117; border: 1px solid #30363d; color: #e6edf3;
  padding: 5px 8px; border-radius: 4px; font-size: 13px; width: 120px;
  text-align: right; font-family: 'DM Mono', monospace;
}
#quoting-phase .btn-danger { background: #3d0c0a; color: #f85149; border: 1px solid #f85149; }
#quoting-phase .btn-sm { padding: 2px 8px; font-size: 12px; }
#quoting-phase .btn-ghost {
  background: none; border: 1px solid #30363d; color: #8b949e;
  padding: 7px 16px; border-radius: 6px; font-size: 13px;
}
#quoting-phase .btn-ghost:hover { color: #e6edf3; border-color: #484f58; }
```

- [ ] **Step 5: Test settings tab**

```bash
python3 app.py &
sleep 2
# Open http://localhost:5111
# In console: showPhase('quoting'); showQTab('settings');
# Verify: printers table shows, materials table shows with Time Mult. and Weight Mult. columns
# Change a material's time multiplier, verify it persists (refresh page, check again)
kill %1
```

- [ ] **Step 6: Commit**

```bash
git add app.py
git commit -m "feat: integrate settings tab with material multiplier columns"
```

---

## Task 10: Integrate Quote Log and Dashboard Tabs

Port the Quote Log table and Dashboard from LNL3D into the quoting phase.

**Files:**
- Modify: `app.py` (HTML template)

**Source reference:** `LNL3D_QuotingSite/LNL3D_Quote.html` lines 641-690 (dashboard), 971-1012 (quote log)

- [ ] **Step 1: Add Dashboard tab HTML and rendering**

Populate `#qtab-dashboard`:

```html
<div id="qtab-dashboard">
  <div class="stats-grid" id="q-stats-grid">
    <div class="stat-card"><div class="stat-value" id="q-stat-total">0</div><div class="stat-label">Total Quotes</div></div>
    <div class="stat-card"><div class="stat-value" id="q-stat-accepted" style="color:#3fb950">0</div><div class="stat-label">Accepted</div></div>
    <div class="stat-card"><div class="stat-value" id="q-stat-progress" style="color:#d29922">0</div><div class="stat-label">In Progress</div></div>
    <div class="stat-card"><div class="stat-value" id="q-stat-complete" style="color:#388bfd">0</div><div class="stat-label">Complete</div></div>
  </div>
  <h3 style="margin:20px 0 10px;font-family:var(--font-head)">Recent Quotes</h3>
  <table class="edit-table" id="q-recent-table">
    <thead><tr><th>#</th><th>Date</th><th>Customer</th><th>Description</th><th>Status</th><th>Suggested</th></tr></thead>
    <tbody id="q-recent-body"></tbody>
  </table>
</div>
```

Add the rendering function:

```javascript
function qRenderDashboard() {
  const quotes = qState.quotes || [];
  document.getElementById('q-stat-total').textContent = quotes.length;
  document.getElementById('q-stat-accepted').textContent = quotes.filter(q => q.status === 'Accepted').length;
  document.getElementById('q-stat-progress').textContent = quotes.filter(q => q.status === 'In Progress').length;
  document.getElementById('q-stat-complete').textContent = quotes.filter(q => q.status === 'Complete').length;

  const recent = quotes.slice(-5).reverse();
  document.getElementById('q-recent-body').innerHTML = recent.map(q =>
    '<tr>'
    + '<td style="font-family:var(--font-mono)">' + qFmtSerial(q.serial) + '</td>'
    + '<td>' + (q.date || '') + '</td>'
    + '<td>' + (q.customer || '') + '</td>'
    + '<td>' + (q.description || '').slice(0, 40) + '</td>'
    + '<td>' + (q.status || '') + '</td>'
    + '<td style="font-family:var(--font-mono);color:#ff9f43">' + qCur(q.calc_suggested) + '</td>'
    + '</tr>'
  ).join('');
}
```

Add dashboard CSS:

```css
#quoting-phase .stats-grid {
  display: grid; grid-template-columns: repeat(4, 1fr); gap: 16px; margin-bottom: 20px;
}
#quoting-phase .stat-card {
  background: #161b22; border: 1px solid #30363d; border-radius: 10px;
  padding: 20px; text-align: center;
}
#quoting-phase .stat-value {
  font-family: 'DM Mono', monospace; font-size: 32px; font-weight: 700;
}
#quoting-phase .stat-label {
  font-size: 12px; color: #8b949e; margin-top: 4px; text-transform: uppercase;
  letter-spacing: 0.5px;
}
```

- [ ] **Step 2: Add Quote Log tab HTML and rendering**

Populate `#qtab-log`:

```html
<div id="qtab-log">
  <div style="display:flex;gap:12px;margin-bottom:16px;align-items:center">
    <input id="q-log-search" placeholder="Search quotes..." oninput="qRenderQuoteLog()"
      style="flex:1;background:#0d1117;border:1px solid #30363d;color:#e6edf3;padding:8px 12px;border-radius:6px;font-size:13px">
    <select id="q-log-filter" onchange="qRenderQuoteLog()"
      style="background:#0d1117;border:1px solid #30363d;color:#e6edf3;padding:8px 12px;border-radius:6px;font-size:13px">
      <option value="">All Statuses</option>
      <option value="Quoting">Quoting</option>
      <option value="Accepted">Accepted</option>
      <option value="In Progress">In Progress</option>
      <option value="Complete">Complete</option>
      <option value="Declined">Declined</option>
    </select>
  </div>
  <table class="edit-table">
    <thead><tr><th>#</th><th>Quote ID</th><th>Date</th><th>Customer</th><th>Description</th><th>Status</th><th>Qty</th><th>Suggested</th><th>Actions</th></tr></thead>
    <tbody id="q-log-body"></tbody>
  </table>
</div>
```

Add the rendering function:

```javascript
function qRenderQuoteLog() {
  const search = (document.getElementById('q-log-search')?.value || '').toLowerCase();
  const filter = document.getElementById('q-log-filter')?.value || '';
  let quotes = (qState.quotes || []).slice().reverse();

  if (search) {
    quotes = quotes.filter(q =>
      (q.customer || '').toLowerCase().includes(search)
      || (q.description || '').toLowerCase().includes(search)
      || (q.quote_id || '').toLowerCase().includes(search)
    );
  }
  if (filter) {
    quotes = quotes.filter(q => q.status === filter);
  }

  document.getElementById('q-log-body').innerHTML = quotes.map(q =>
    '<tr>'
    + '<td style="font-family:var(--font-mono)">' + qFmtSerial(q.serial) + '</td>'
    + '<td style="font-family:var(--font-mono);font-size:12px">' + (q.quote_id || '') + '</td>'
    + '<td>' + (q.date || '') + '</td>'
    + '<td>' + (q.customer || '') + '</td>'
    + '<td>' + (q.description || '').slice(0, 30) + '</td>'
    + '<td>' + (q.status || '') + '</td>'
    + '<td style="text-align:center">' + (q.quantity || 1) + '</td>'
    + '<td style="font-family:var(--font-mono);color:#ff9f43">' + qCur(q.calc_suggested) + '</td>'
    + '<td><button class="btn btn-danger btn-sm" onclick="qDeleteQuote(' + q.serial + ')">&#10005;</button></td>'
    + '</tr>'
  ).join('');
}

function qDeleteQuote(serial) {
  if (!confirm('Delete quote #' + qFmtSerial(serial) + '?')) return;
  qState.quotes = qState.quotes.filter(q => q.serial !== serial);
  saveQuotingState();
  qRenderQuoteLog();
  qRenderDashboard();
}
```

- [ ] **Step 3: Hook tab rendering into showQTab**

Update `showQTab` to trigger rendering for each tab:

```javascript
// In showQTab(), add:
if (tab === 'dashboard') qRenderDashboard();
if (tab === 'log') qRenderQuoteLog();
```

- [ ] **Step 4: Test dashboard and quote log**

```bash
python3 app.py &
sleep 2
# Open http://localhost:5111
# Slice a file, send to quick quote, log it
# In console: showPhase('quoting');
# Verify dashboard shows count of 1, recent quote visible
# Click "Quote Log" tab — verify the quote appears in the table
# Test search and status filter
kill %1
```

- [ ] **Step 5: Commit**

```bash
git add app.py
git commit -m "feat: integrate dashboard and quote log tabs"
```

---

## Task 11: Integrate Customers Tab

Port the customer management UI.

**Files:**
- Modify: `app.py` (HTML template)

**Source reference:** `LNL3D_QuotingSite/LNL3D_Quote.html` lines 1012-1044 (customers HTML)

- [ ] **Step 1: Add Customers tab HTML and JS**

Populate `#qtab-customers`:

```html
<div id="qtab-customers">
  <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:16px">
    <h2 style="font-family:var(--font-head)">Customers</h2>
    <button class="btn btn-primary" onclick="qAddCustomer()">+ Add Customer</button>
  </div>
  <table class="edit-table">
    <thead><tr><th>Name</th><th>Company</th><th>Email</th><th>Phone</th><th>Notes</th><th>Created</th><th></th></tr></thead>
    <tbody id="q-customers-body"></tbody>
  </table>
</div>
```

Add rendering:

```javascript
function qRenderCustomers() {
  document.getElementById('q-customers-body').innerHTML = (qState.customers || []).map((c, i) =>
    '<tr>'
    + '<td><input value="' + (c.name||'') + '" data-i="' + i + '" data-f="name" onchange="qUpdateCustomer(this)"></td>'
    + '<td><input value="' + (c.company||'') + '" data-i="' + i + '" data-f="company" onchange="qUpdateCustomer(this)"></td>'
    + '<td><input value="' + (c.email||'') + '" data-i="' + i + '" data-f="email" onchange="qUpdateCustomer(this)"></td>'
    + '<td><input value="' + (c.phone||'') + '" data-i="' + i + '" data-f="phone" onchange="qUpdateCustomer(this)"></td>'
    + '<td><input value="' + (c.notes||'') + '" data-i="' + i + '" data-f="notes" onchange="qUpdateCustomer(this)"></td>'
    + '<td style="font-size:12px;color:#8b949e">' + (c.created||'').slice(0,10) + '</td>'
    + '<td><button class="btn btn-danger btn-sm" onclick="qRemoveCustomer(' + i + ')">&#10005;</button></td>'
    + '</tr>'
  ).join('');
}

function qUpdateCustomer(el) {
  const i = +el.dataset.i, f = el.dataset.f;
  qState.customers[i][f] = el.value;
  saveQuotingState();
}

function qAddCustomer() {
  qState.customers.push({ id: Date.now(), name: '', company: '', email: '', phone: '', notes: '', created: new Date().toISOString() });
  saveQuotingState();
  qRenderCustomers();
}

function qRemoveCustomer(i) {
  if (!confirm('Delete customer ' + (qState.customers[i]?.name || '') + '?')) return;
  qState.customers.splice(i, 1);
  saveQuotingState();
  qRenderCustomers();
}
```

- [ ] **Step 2: Hook into showQTab**

```javascript
// In showQTab(), add:
if (tab === 'customers') qRenderCustomers();
```

- [ ] **Step 3: Test customers tab**

```bash
python3 app.py &
sleep 2
# Open http://localhost:5111
# console: showPhase('quoting'); showQTab('customers');
# Add a customer, edit fields, verify persistence
kill %1
```

- [ ] **Step 4: Commit**

```bash
git add app.py
git commit -m "feat: integrate customers management tab"
```

---

## Task 12: Integrate the Full Quote Form (New Quote Tab)

Port the complete LNL3D New Quote form into the quoting phase, with pre-fill support from the quick quote.

**Files:**
- Modify: `app.py` (HTML template)

**Source reference:** `LNL3D_QuotingSite/LNL3D_Quote.html` lines 690-970 (quote form HTML), lines 1815-2090 (form rendering JS)

- [ ] **Step 1: Add the New Quote form HTML**

Populate `#qtab-quote` with the form layout. This is a large block — copy the form structure from `LNL3D_Quote.html` lines 690-970, adapting all IDs to use `q-` prefix. Key sections:

- Basic info: customer, project, description, date, expiry, status
- Print specs: printer (select from qState printers), filament (select from qState materials), weight_g, print_time, complexity, quantity, rush
- Support: support_filament, support_weight_g
- Labor: prep_model, prep_slice, post_remove, post_support, post_extra
- Finishing: fin_sand, fin_paint, fin_hardware, fin_other
- Shipping: ship_pack, ship_cost
- Other: consumables, quoted_price, notes
- Right sidebar: live cost calculation display (from calcFromQuoteData)

Each input should call `qUpdateQuoteCalc()` on change/input to recalculate the sidebar.

The form HTML is extensive (~280 lines). Copy it from the source file, prefix all IDs with `q-`, and change all function references to use the `q`-prefixed versions.

- [ ] **Step 2: Add the form data getter and live calculation display**

```javascript
function qGetFormData() {
  const val = id => document.getElementById(id)?.value || '';
  return {
    customer: val('q-f-customer'),
    project: val('q-f-project'),
    description: val('q-f-description'),
    date: val('q-f-date'),
    status: val('q-f-status'),
    printer: val('q-f-printer'),
    filament: val('q-f-filament'),
    weight_g: +val('q-f-weight') || 0,
    print_time: val('q-f-time'),
    complexity: +val('q-f-complexity') || 1,
    quantity: +val('q-f-qty') || 1,
    rush: +val('q-f-rush') || 1.0,
    support_filament: val('q-f-support-mat'),
    support_weight_g: +val('q-f-support-weight') || 0,
    prep_model: +val('q-f-prep-model') || 0,
    prep_slice: +val('q-f-prep-slice') || 0,
    post_remove: +val('q-f-post-remove') || 0,
    post_support: +val('q-f-post-support') || 5,
    post_extra: +val('q-f-post-extra') || 0,
    fin_sand: +val('q-f-fin-sand') || 0,
    fin_paint: +val('q-f-fin-paint') || 0,
    fin_hardware: +val('q-f-fin-hw') || 0,
    fin_other: +val('q-f-fin-other') || 0,
    ship_pack: +val('q-f-ship-pack') || 0,
    ship_cost: +val('q-f-ship-cost') || 0,
    consumables: +val('q-f-consumables') || 0,
    quoted_price: +val('q-f-quoted') || 0,
    notes: val('q-f-notes'),
  };
}

function qUpdateQuoteCalc() {
  const q = qGetFormData();
  const c = qCalcFromQuoteData(q);
  const el = document.getElementById('q-calc-sidebar');
  if (!el) return;
  el.innerHTML = ''
    + '<div class="qq-row"><span class="qq-label">Material</span><span>' + qCur(c.filamentCost) + '</span></div>'
    + '<div class="qq-row"><span class="qq-label">Support</span><span>' + qCur(c.suppCost) + '</span></div>'
    + '<div class="qq-row"><span class="qq-label">Electricity</span><span>' + qCur(c.elecCost) + '</span></div>'
    + '<div class="qq-row"><span class="qq-label">Depreciation</span><span>' + qCur(c.deprCost) + '</span></div>'
    + '<div class="qq-row"><span class="qq-label">Failure (' + (c.fail*100).toFixed(0) + '%)</span><span>+' + qCur(c.machinePP - c.filamentCost - c.elecCost - c.deprCost) + '</span></div>'
    + '<div class="qq-row"><span class="qq-label">Prep Labor</span><span>' + qCur(c.prepLabor) + '</span></div>'
    + '<div class="qq-row"><span class="qq-label">Post Labor</span><span>' + qCur(c.postLabor) + '</span></div>'
    + '<div class="qq-row"><span class="qq-label">Finishing</span><span>' + qCur(c.finishing) + '</span></div>'
    + '<div class="qq-row"><span class="qq-label">Shipping</span><span>' + qCur(c.shipping) + '</span></div>'
    + '<div class="qq-row" style="border-top:1px solid #30363d;margin-top:6px;padding-top:6px;font-weight:700"><span>Cost/pc</span><span>' + qCur(c.costPP) + '</span></div>'
    + '<div class="qq-row"><span class="qq-label">Markup (' + c.markup.toFixed(1) + 'x)</span><span>' + qCur(c.pricePP - c.costPP) + '</span></div>'
    + '<div class="qq-row qq-total"><span>Suggested</span><span class="qq-price">' + qCur(c.suggested) + '</span></div>'
    + (c.quoted > 0 ? '<div class="qq-row qq-total"><span>Quoted</span><span style="color:#ff9f43">' + qCur(c.quoted) + '</span></div>' : '')
    + '<div class="qq-row qq-sub"><span>Margin: ' + (c.margin*100).toFixed(0) + '%</span><span>Profit: ' + qCur(c.totalProfit) + '</span></div>';
}
```

- [ ] **Step 3: Add the prefillQuoteForm function**

This is called from `openFullQuoteForm()` in the quick quote:

```javascript
function prefillQuoteForm(data) {
  const set = (id, val) => { const el = document.getElementById(id); if (el) el.value = val; };
  set('q-f-customer', data.customer || '');
  set('q-f-printer', data.printer || '');
  set('q-f-filament', data.filament || '');
  set('q-f-weight', data.weight_g?.toFixed(1) || '');
  set('q-f-time', data.print_time || '');
  set('q-f-qty', data.quantity || 1);
  set('q-f-date', new Date().toISOString().slice(0, 10));
  if (data.line_items && data.line_items.length > 1) {
    set('q-f-description', data.line_items.map(li => li.slicerData.filename).join(', '));
  }
  qUpdateQuoteCalc();
}
```

- [ ] **Step 4: Add quote form log button and function**

```javascript
function qLogFullQuote() {
  const q = qGetFormData();
  if (!q.customer) { alert('Please enter a customer name.'); return; }
  if (!q.description) { alert('Please enter a description.'); return; }

  const c = qCalcFromQuoteData(q);
  const s = qState.settings;
  const serial = s.next_serial || 1;
  const dateStr = q.date || new Date().toISOString().slice(0, 10);
  const custInitials = q.customer.replace(/\\s/g, '').slice(0, 3).toUpperCase();

  const entry = {
    ...q,
    serial,
    quote_id: qFmtSerial(serial) + '-' + dateStr.replace(/-/g, '') + '-' + custInitials,
    logged_at: new Date().toISOString(),
    calc_cost_pp: c.costPP,
    calc_suggested: c.suggested,
    calc_margin: c.margin,
    calc_profit: c.totalProfit,
  };

  qState.quotes.push(entry);
  s.next_serial = serial + 1;

  if (!qState.customers.find(cu => cu.name === q.customer)) {
    qState.customers.push({
      id: Date.now(), name: q.customer, company: '', email: '', phone: '',
      notes: '', created: new Date().toISOString()
    });
  }

  saveQuotingState();
  alert('Quote #' + qFmtSerial(serial) + ' logged for ' + q.customer + ' — ' + qCur(c.suggested));
  // Clear form
  document.querySelectorAll('#qtab-quote input, #qtab-quote select, #qtab-quote textarea').forEach(el => {
    if (el.type === 'number') el.value = el.defaultValue || '';
    else el.value = '';
  });
  qUpdateQuoteCalc();
}
```

- [ ] **Step 5: Populate printer/filament dropdowns when tab opens**

In `showQTab`, when `tab === 'quote'`:

```javascript
if (tab === 'quote') {
  // Populate printer dropdown
  const pSel = document.getElementById('q-f-printer');
  if (pSel && pSel.options.length <= 1) {
    pSel.innerHTML = '<option value="">Select...</option>'
      + (qState.settings?.printers || []).map(p => '<option value="' + p.name + '">' + p.name + '</option>').join('');
  }
  // Populate filament dropdown
  const mSel = document.getElementById('q-f-filament');
  if (mSel && mSel.options.length <= 1) {
    mSel.innerHTML = '<option value="">Select...</option>'
      + (qState.settings?.materials || []).map(m => '<option value="' + m.name + '">' + m.name + '</option>').join('');
  }
  qUpdateQuoteCalc();
}
```

- [ ] **Step 6: Test the full quote form**

```bash
python3 app.py &
sleep 2
# Open http://localhost:5111
# Slice a file, send to quick quote, click "Full Details →"
# Verify form opens with weight/time/printer/filament pre-filled
# Fill in customer, description, add labor, verify sidebar recalculates
# Click Log Quote, verify it appears in Quote Log tab
kill %1
```

- [ ] **Step 7: Commit**

```bash
git add app.py
git commit -m "feat: integrate full quote form with pre-fill from slicer"
```

---

## Task 13: Load Quoting State on App Start

Ensure the quoting state loads when the app first opens (not just when switching phases), so the quick quote overlay works immediately after slicing.

**Files:**
- Modify: `app.py` (JavaScript section)

- [ ] **Step 1: Add auto-load on page init**

Find the existing `DOMContentLoaded` or page initialization code in the slicer JS. Add:

```javascript
// Load quoting state on page load (needed for quick quote overlay)
loadQuotingState();
```

If there's no DOMContentLoaded handler, add one:

```javascript
document.addEventListener('DOMContentLoaded', function() {
  loadQuotingState();
});
```

- [ ] **Step 2: Verify state loads at startup**

```bash
python3 app.py &
sleep 2
# Open http://localhost:5111
# In console: console.log(qState.settings?.materials?.length)
# Expected: 9 (or however many materials are in settings.json)
# Should NOT be null/undefined
kill %1
```

- [ ] **Step 3: Commit**

```bash
git add app.py
git commit -m "feat: auto-load quoting state on page startup"
```

---

## Task 14: End-to-End Testing and Polish

Run through the complete flow and fix any integration issues.

**Files:**
- Modify: `app.py` (as needed for fixes)

- [ ] **Step 1: Test single-file flow**

```bash
python3 app.py &
sleep 2
# 1. Open http://localhost:5111
# 2. Upload an STL file
# 3. Select printer and profile, click Generate Quote
# 4. Wait for slicing
# 5. Click "Send to Quote →"
# 6. Verify Quick Quote overlay shows correct weight/time
# 7. Change filament to PETG — verify time increases by ~1.3x
# 8. Enter customer name, click Log Quote
# 9. Click "← Back to Slicer" on topbar logo (or use console: showPhase('quoting'))
# 10. Check Dashboard — quote count should be 1
# 11. Check Quote Log — quote should appear with correct details
# 12. Check Settings — materials should show multiplier columns
kill %1
```

- [ ] **Step 2: Test batch flow**

```bash
python3 app.py &
sleep 2
# 1. Upload 2-3 STL files
# 2. Click "Quote All"
# 3. Wait for all to slice
# 4. Click "Send All to Quote →"
# 5. Verify Quick Quote shows all items as separate cards
# 6. Verify totals row at bottom
# 7. Set different filaments on different items
# 8. Log the quote
# 9. Check Quote Log — single quote with description listing all filenames
kill %1
```

- [ ] **Step 3: Test settings persistence**

```bash
python3 app.py &
sleep 2
# 1. Go to Settings tab
# 2. Change PETG time multiplier from 1.3 to 1.5
# 3. Add a new material
# 4. Stop and restart the server
# 5. Verify changes persisted
kill %1
```

- [ ] **Step 4: Test the Full Details expansion**

```bash
python3 app.py &
sleep 2
# 1. Slice a file, Send to Quote
# 2. In Quick Quote, click "Full Details →"
# 3. Verify the full form has weight/time/printer/filament pre-filled
# 4. Add labor, finishing costs
# 5. Verify sidebar recalculates
# 6. Log the full quote
kill %1
```

- [ ] **Step 5: Fix any issues found and commit**

```bash
git add app.py data/
git commit -m "fix: end-to-end integration polish"
```

---

## Summary

| Task | Description | Key Output |
|------|-------------|------------|
| 1 | Bootstrap project | Combined app.py + data directory |
| 2 | JSON persistence endpoints | /api/qdata/* routes in Flask |
| 3 | Material multipliers | settings.json with time/weight multipliers |
| 4 | Phase navigation + CSS | Slicer ↔ Quoting phase switching |
| 5 | Quoting state + calc engine | qState, qCalcFromQuoteData, qCalcQuickQuote |
| 6 | Quick Quote overlay | Cost breakdown UI with editable controls |
| 7 | Slicer → Quick Quote wiring | "Send to Quote" button, data handoff |
| 8 | Quote logging | Log quotes from quick quote view |
| 9 | Settings tab | Printers, materials (with multipliers), discount tiers |
| 10 | Dashboard + Quote Log | Stats, recent quotes, searchable log |
| 11 | Customers tab | Customer CRUD |
| 12 | Full Quote form | Complete quote form with pre-fill from slicer |
| 13 | Auto-load state | Quoting state loads on page startup |
| 14 | E2E testing | Full flow verification and polish |
