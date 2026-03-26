# Multi-Piece Quoting Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix all bugs in the multi-model/multi-piece quoting flow so that batch quotes correctly calculate, display, log, and export pricing for multiple items.

**Architecture:** All fixes are in `app.py` (single-file app). The quoting system has 3 consumers of `qqItems[]`: the Quick Quote overlay UI, the PDF generator, and the quote logger. Each needs fixes for multi-item handling. The Full Quote form is single-item by design — we'll make the transition explicit rather than silently dropping data.

**Tech Stack:** Flask, vanilla JS, trimesh (Python)

---

## Bug Summary

| # | Bug | Severity | Location |
|---|-----|----------|----------|
| 1 | `extractSlicerBaseline` calculates qty but doesn't return it | MEDIUM | ~line 2877 |
| 2 | `slicerQuickPDF` forces qty:1, ignoring slicer quantity | MEDIUM | ~line 5102 |
| 3 | Volume tier PDF table uses tier threshold qty instead of actual item qtys | CRITICAL | ~line 4968 |
| 4 | Volume tier PPU divides by tier threshold instead of total actual qty | CRITICAL | ~line 4974 |
| 5 | `logQuickQuote` uses `mat.complexity` instead of item's auto-complexity | MEDIUM | ~line 5137 |
| 6 | `openFullQuoteForm` silently drops all items after the first | CRITICAL | ~line 5776 |

---

### Task 1: Fix extractSlicerBaseline returning quantity

**Files:**
- Modify: `app.py` — `extractSlicerBaseline` function (~line 2875)

**Problem:** The function reads `document.getElementById('quantity').value` into a local `qty` variable and includes it in the return object, but this is a global slicer form field — in batch mode all items get the same qty. The quantity should come from the quote result's `quantity` field when available.

- [ ] **Step 1: Fix qty source**

Change `extractSlicerBaseline` to prefer the quote result's quantity, falling back to the form field:

```javascript
function extractSlicerBaseline(d, sizeCheck) {
  const timeMins = parseTimeToMins(d.time || '0');
  const qty = d.quantity || parseInt(document.getElementById('quantity').value) || 1;
  return {
    filename:         d.filename || 'unknown',
    base_weight_g:    d.weight_g || 0,
    base_time_minutes: timeMins,
    job_id:           d.job_id || null,
    quantity:         qty,
    complexity:       d.complexity || null,
    complexity_breakdown: d.complexity_breakdown || null
  };
}
```

- [ ] **Step 2: Verify** — `python3 -c "import app; print('OK')"`

- [ ] **Step 3: Commit** — `git commit -m "fix: extractSlicerBaseline uses quote result quantity"`

---

### Task 2: Fix slicerQuickPDF preserving quantities

**Files:**
- Modify: `app.py` — `slicerQuickPDF` function (~line 5095)

**Problem:** `slicerQuickPDF` builds qqItems with hardcoded `quantity: 1` for every item, ignoring `sr.quantity` from the slicer baseline.

- [ ] **Step 1: Use sr.quantity**

Change the map inside `slicerQuickPDF`:

```javascript
async function slicerQuickPDF() {
  if (_slicerResultsForQuote.length === 0) return;
  await loadQuotingState();
  var defaultPrinter  = ((qState.settings.printers||[])[0]||{}).name || '';
  var mats = qState.settings.materials || [];
  var defaultFilament = ((mats.find(function(m){return m.name.indexOf('PLA')>=0;}) || mats[0])||{}).name || 'PLA+';
  qqItems = _slicerResultsForQuote.map(function(sr) {
    var qty = sr.quantity || 1;
    var calc = qCalcQuickQuote(sr, { printer: defaultPrinter, filament: defaultFilament, quantity: qty });
    return { slicerData: sr, printer: defaultPrinter, filament: defaultFilament, quantity: qty, calc: calc };
  });
  qqDownloadPDF();
}
```

- [ ] **Step 2: Verify** — `python3 -c "import app; print('OK')"`

- [ ] **Step 3: Commit** — `git commit -m "fix: slicerQuickPDF preserves item quantities from slicer"`

---

### Task 3: Fix volume tier calculation in PDF for multi-item quotes

**Files:**
- Modify: `app.py` — volume tier section inside `qqDownloadPDF` (~lines 4958-4997)

**Problem:** The volume tier table recalculates each item at the tier's threshold quantity (e.g., qty=10, qty=25) instead of keeping each item's actual quantity and just applying the tier's markup rate. This makes the table show wildly wrong numbers for multi-item quotes.

The correct behavior for the customer-facing PDF: "If you ordered X+ total pieces, here's what each item would cost at that volume rate." Each item keeps its own quantity but gets the tier's markup.

- [ ] **Step 1: Rewrite volume tier calculation**

The tier table should show: at each tier level, what would the total quote cost if the tier's markup applied. We compute total pieces across all items, then for each tier, recalculate each item using its own qty but at the tier's markup rate.

Replace the volume tier block (from `// Volume price breaks` through the closing `}` of `if (tiers.length > 1)`) with:

```javascript
  // Volume price breaks — show what-if pricing at each tier rate
  var tiers = [...(s.discounts||[])].sort(function(a,b) { return a.qty - b.qty; });
  var tiersHTML = '';
  if (tiers.length > 1) {
    var totalQty = 0;
    qqItems.forEach(function(item) { totalQty += item.quantity; });

    var tierRows = tiers.map(function(t) {
      // Recalculate each item at its OWN quantity but with this tier's markup
      var tierTotal = 0;
      qqItems.forEach(function(item) {
        var tierCalc = qCalcQuickQuote(item.slicerData, {
          printer: item.printer, filament: item.filament, quantity: item.quantity
        });
        // Override markup: apply this tier's markup instead of the qty-based one
        var tierMarkup = Math.max(t.markup, s.min_markup || 1.2);
        var itemTotal = Math.max(tierCalc.costPP * item.quantity * tierMarkup, s.min_fee || 5);
        tierTotal += itemTotal;
      });
      var tierPPU = totalQty > 0 ? tierTotal / totalQty : 0;

      // Is this the active tier?
      var activeTier = tiers.filter(function(r) { return r.qty <= totalQty; });
      var isActive = activeTier.length > 0 && t.qty === activeTier[activeTier.length - 1].qty;

      // Savings vs first tier
      var baseTierTotal = 0;
      qqItems.forEach(function(item) {
        var bc = qCalcQuickQuote(item.slicerData, {
          printer: item.printer, filament: item.filament, quantity: item.quantity
        });
        var baseMarkup = Math.max(tiers[0].markup, s.min_markup || 1.2);
        baseTierTotal += Math.max(bc.costPP * item.quantity * baseMarkup, s.min_fee || 5);
      });
      var basePPU = totalQty > 0 ? baseTierTotal / totalQty : 0;
      var savings = basePPU > 0 ? ((1 - tierPPU / basePPU) * 100).toFixed(0) : 0;

      return '<tr class="' + (isActive ? 'active-tier' : '') + '">' +
        '<td>' + t.qty + '+ pieces' + (isActive ? '<span class="qq-pdf-tier-label">Your Qty</span>' : '') + '</td>' +
        '<td>' + cur(tierPPU) + '</td>' +
        '<td>' + cur(tierTotal) + '</td>' +
        '<td>' + (savings > 0 ? '<span class="qq-pdf-tier-savings">' + savings + '% savings</span>' : '') + '</td>' +
      '</tr>';
    }).join('');
    tiersHTML = '<div class="qq-pdf-section">Volume Pricing</div>' +
      '<table class="qq-pdf-tiers">' +
        '<thead><tr><th>Quantity</th><th>Avg Price/Unit</th><th>Total</th><th></th></tr></thead>' +
        '<tbody>' + tierRows + '</tbody>' +
      '</table>';
  }
```

- [ ] **Step 2: Verify** — `python3 -c "import app; print('OK')"`

- [ ] **Step 3: Manual test** — Open Quick Quote with 2+ items at different quantities, click PDF, verify tier table shows sensible numbers

- [ ] **Step 4: Commit** — `git commit -m "fix: volume tier PDF uses actual item quantities with tier markup rates"`

---

### Task 4: Fix logQuickQuote complexity assignment

**Files:**
- Modify: `app.py` — `logQuickQuote` function, line item assembly (~line 5137)

**Problem:** Each line item uses `mat ? mat.complexity : 1` instead of the item's auto-calculated complexity from model analysis.

- [ ] **Step 1: Find and fix the complexity line**

In `logQuickQuote`, in the `lineItems = qqItems.map(...)` block, change:

```javascript
complexity:    mat ? mat.complexity : 1,
```

to:

```javascript
complexity:    item.slicerData.complexity || (mat ? mat.complexity : 1),
```

- [ ] **Step 2: Verify** — `python3 -c "import app; print('OK')"`

- [ ] **Step 3: Commit** — `git commit -m "fix: logQuickQuote uses auto-calculated complexity per item"`

---

### Task 5: Fix Full Quote form transition for multi-item quotes

**Files:**
- Modify: `app.py` — `openFullQuoteForm` and `prefillQuoteForm` functions

**Problem:** The Full Quote form is single-item (one set of fields). When multiple items are passed from Quick Quote, only the first item's data populates the form and the rest are silently lost (just mentioned in notes). This is confusing — the user thinks they're sending all items but only one arrives.

**Solution:** When multiple items exist, show an alert explaining the limitation and let the user choose which item to send, or log them as separate quotes.

- [ ] **Step 1: Update openFullQuoteForm to handle multi-item**

Replace `openFullQuoteForm`:

```javascript
function openFullQuoteForm() {
  if (qqItems.length === 0) return;
  var itemsCopy = qqItems.slice();
  if (itemsCopy.length > 1) {
    var msg = 'The Full Details form handles one part at a time.\n\n' +
      'You have ' + itemsCopy.length + ' parts in this quote.\n' +
      'The first part (' + (itemsCopy[0].slicerData.filename || 'unknown') + ') will be loaded.\n\n' +
      'To quote all parts, use "Log Quote" from the Quick Quote view instead.';
    if (!confirm(msg)) return;
  }
  closeQuickQuote();
  showPhase('quoting');
  showQTab('quote');
  if (typeof prefillQuoteForm === 'function') {
    prefillQuoteForm(itemsCopy);
  }
}
```

- [ ] **Step 2: Verify** — `python3 -c "import app; print('OK')"`

- [ ] **Step 3: Commit** — `git commit -m "fix: Full Details form warns user about single-item limitation with multi-item quotes"`

---

### Task 6: Final verification — restart and test all paths

- [ ] **Step 1: Restart server**

```bash
lsof -ti :5111 | xargs kill 2>/dev/null; python3 app.py &
```

- [ ] **Step 2: Test single-item flow**
- Upload 1 model, set qty=5
- Send to Quick Quote → verify qty=5 shows
- Click PDF → verify line item shows qty=5, total correct
- Click Full Details → verify form has qty=5, weight, time

- [ ] **Step 3: Test multi-item flow**
- Upload 2+ models in batch mode
- Send All to Quote → verify all items show in Quick Quote overlay
- Change qty on each item independently
- Verify totals sum correctly
- Click PDF → verify all items listed, tier table shows correct numbers
- Click Log Quote → verify quote saved with all line items
- Click Full Details → verify warning dialog appears

- [ ] **Step 4: Commit all remaining changes**

```bash
git add app.py
git commit -m "fix: multi-piece quoting bugs across all paths"
```
