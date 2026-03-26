# Multi-Part Full Quote Form Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the Full Quote form to support multiple line items (parts) via a tabbed interface, with per-part cost breakdowns and expandable quote log rows.

**Architecture:** All changes in `app.py` (single-file app). The form gets a tab bar for parts, each tab holding per-part fields. Shared fields (customer, shipping) stay outside tabs. The sidebar shows collapsible per-part breakdowns + combined total. Data model adds `line_items[]` array to quotes. Backwards-compatible with existing single-part quotes.

**Tech Stack:** Flask, vanilla JS, HTML/CSS (all inline in app.py)

**Spec:** `docs/superpowers/specs/2026-03-26-multi-part-full-quote-design.md`

**CRITICAL:** This is a Python file containing HTML/JS as a triple-quoted string. All JS newlines inside string literals must use `\\n` (double-backslash-n), not `\n`. A bare `\n` in a Python string becomes a literal newline which breaks JS single-quoted strings. This rule applies to ALL string content in JS: alert messages, confirm dialogs, template strings, etc.

---

## File Structure

All changes in one file:
- **Modify:** `app.py` — HTML form structure, CSS, and 9 JS functions

## Task Overview

| # | Task | Scope |
|---|------|-------|
| 1 | Add CSS for tabs, part cards, expandable rows | CSS only |
| 2 | Rebuild quote tab HTML with tabs + shared sections | HTML only |
| 3 | Rewrite JS data layer: qGetFormData, qSetFormData, part management | JS functions |
| 4 | Rewrite JS calc + sidebar: qUpdateQuoteCalc with per-part breakdowns | JS function |
| 5 | Rewrite JS form lifecycle: qClearForm, qLogFullQuote, qEditQuote | JS functions |
| 6 | Update qRenderQuoteLog with expandable rows | JS function |
| 7 | Update prefillQuoteForm for multi-part | JS function |
| 8 | Backwards compatibility for old single-part quotes | JS migration |
| 9 | Verify and restart | Testing |

---

### Task 1: Add CSS for tabs, part management, and expandable rows

**Files:**
- Modify: `app.py` — CSS section near lines 2205-2289

**Context:** The existing CSS has `.q-quote-layout`, `.q-form-section`, `.q-cost-preview`, etc. We need to add tab styles, part header styles, and expandable row styles without breaking existing styles.

- [ ] **Step 1: Add new CSS classes**

Find the line `.q-cost-row-value.yellow { color: var(--q-warn); }` (approximately line 2269) and add after it:

```css
  /* Part tabs */
  .q-part-tabs { display: flex; gap: 0; border-bottom: 2px solid var(--q-border); margin-bottom: 0; overflow-x: auto; }
  .q-part-tab { padding: 8px 16px; font-size: 12px; font-weight: 500; color: var(--q-text2); cursor: pointer; border: 1px solid transparent; border-bottom: none; border-radius: 8px 8px 0 0; white-space: nowrap; display: flex; align-items: center; gap: 6px; font-family: 'DM Sans', sans-serif; background: none; transition: all .15s; }
  .q-part-tab:hover { color: var(--q-text); background: var(--q-bg2); }
  .q-part-tab.active { color: var(--q-accent); background: var(--q-bg2); border-color: var(--q-border); border-bottom: 2px solid var(--q-bg2); margin-bottom: -2px; font-weight: 600; }
  .q-part-tab .q-tab-close { font-size: 10px; color: var(--q-text3); cursor: pointer; padding: 2px 4px; border-radius: 3px; line-height: 1; }
  .q-part-tab .q-tab-close:hover { color: var(--q-danger); background: rgba(255,107,107,.1); }
  .q-part-tab-add { color: var(--q-text3); font-size: 11px; padding: 8px 12px; cursor: pointer; background: none; border: none; font-family: 'DM Sans', sans-serif; }
  .q-part-tab-add:hover { color: var(--q-accent); }
  .q-part-content { background: var(--q-bg2); border: 1px solid var(--q-border); border-top: none; border-radius: 0 0 var(--q-rad2) var(--q-rad2); padding: 16px; }
  /* Expandable quote log rows */
  .q-log-expand { cursor: pointer; color: var(--q-text3); font-size: 11px; padding: 2px 6px; border-radius: 3px; background: none; border: none; transition: transform .15s; }
  .q-log-expand.open { transform: rotate(90deg); }
  .q-log-expand:hover { color: var(--q-accent); }
  .q-log-sub-row td { background: var(--q-bg3); font-size: 11px; color: var(--q-text2); padding: 4px 12px; border-bottom: 1px solid var(--q-border); }
  .q-log-sub-row td:first-child { padding-left: 32px; }
  .q-log-parts-badge { font-size: 10px; background: rgba(56,139,253,.1); color: var(--q-accent); padding: 2px 6px; border-radius: 3px; margin-left: 4px; }
  /* Per-part sidebar breakdown */
  .q-part-breakdown { border: 1px solid var(--q-border); border-radius: var(--q-rad2); overflow: hidden; margin-bottom: 8px; }
  .q-part-breakdown-header { padding: 8px 12px; background: var(--q-bg3); cursor: pointer; display: flex; justify-content: space-between; align-items: center; font-size: 12px; font-weight: 600; }
  .q-part-breakdown-header:hover { background: var(--q-bg2); }
  .q-part-breakdown-body { display: none; }
  .q-part-breakdown-body.open { display: block; }
  .q-part-breakdown .q-cost-row { padding: 4px 12px; font-size: 11px; }
```

- [ ] **Step 2: Verify** — `python3 -c "import app; print('OK')"`

- [ ] **Step 3: Commit** — `git commit -m "feat: add CSS for multi-part tabs, expandable rows, part breakdowns"`

---

### Task 2: Rebuild quote tab HTML with tabbed parts

**Files:**
- Modify: `app.py` — HTML inside `id="qtab-quote"` (lines ~4277-4400)

**Context:** Replace the current single-form layout with: shared fields top → part tab bar → part content area → shared fields bottom. The right sidebar gets per-part breakdown containers + combined total.

- [ ] **Step 1: Replace the quote tab HTML**

Find the opening `<div id="qtab-quote" class="q-tab-content">` and replace everything through its closing `</div>` (before `<div id="qtab-log"`) with the new multi-part layout.

The new HTML structure:

```html
<div id="qtab-quote" class="q-tab-content">
  <div class="q-flex-between q-mb-16">
    <div>
      <div class="q-page-title" id="q-quote-title">New Quote</div>
      <div class="q-page-sub" id="q-quote-sub">Fill in the job details and the cost preview updates live.</div>
    </div>
    <div style="display:flex;gap:8px">
      <button class="q-btn q-btn-ghost" onclick="qClearForm()">Clear</button>
      <button class="q-btn q-btn-primary q-btn-lg" onclick="qLogFullQuote()">Save Quote</button>
    </div>
  </div>
  <div id="q-quote-alert"></div>
  <div class="q-quote-layout">
    <div>
      <!-- Shared: Quote Details -->
      <div class="q-card" style="margin-bottom:16px">
        <div class="q-card-header">Quote Details</div>
        <div style="padding:16px">
          <div class="q-form-row q-form-row-2">
            <div class="q-form-group"><label class="q-form-label">Customer</label><input class="q-form-input" id="qf-customer" type="text" list="qf-customer-list" placeholder="Customer name"><datalist id="qf-customer-list"></datalist></div>
            <div class="q-form-group"><label class="q-form-label">Project</label><input class="q-form-input" id="qf-project" type="text"></div>
          </div>
          <div class="q-form-row q-form-row-2">
            <div class="q-form-group"><label class="q-form-label">Description</label><input class="q-form-input" id="qf-description" type="text"></div>
            <div class="q-form-group"><label class="q-form-label">Date</label><input class="q-form-input" id="qf-date" type="date"></div>
          </div>
          <div class="q-form-row q-form-row-3">
            <div class="q-form-group"><label class="q-form-label">Status</label><select class="q-form-input" id="qf-status"><option>Quoting</option><option>Accepted</option><option>In Progress</option><option>Complete</option><option>Declined</option></select></div>
            <div class="q-form-group"><label class="q-form-label">Rush</label><select class="q-form-input" id="qf-rush"><option value="1.0">1.0x</option><option value="1.25">1.25x</option><option value="1.5">1.5x</option><option value="1.75">1.75x</option><option value="2.0">2.0x</option></select></div>
            <div class="q-form-group"><label class="q-form-label">Quote Override ($)</label><input class="q-form-input" id="qf-quoted" type="number" step="0.01" placeholder="Leave blank for auto" oninput="qUpdateQuoteCalc()"></div>
          </div>
        </div>
      </div>

      <!-- Part Tabs -->
      <div id="q-part-tabs" class="q-part-tabs">
        <!-- Tabs inserted by JS -->
      </div>
      <div id="q-part-content" class="q-part-content">
        <!-- Active part form inserted by JS -->
      </div>

      <!-- Shared: Shipping & Notes -->
      <div class="q-card" style="margin-top:16px">
        <div class="q-card-header">Shipping &amp; Notes</div>
        <div style="padding:16px">
          <div class="q-form-row q-form-row-2">
            <div class="q-form-group"><label class="q-form-label">Packaging ($)</label><input class="q-form-input" id="qf-ship-pack" type="number" step="0.01" value="0" oninput="qUpdateQuoteCalc()"></div>
            <div class="q-form-group"><label class="q-form-label">Shipping ($)</label><input class="q-form-input" id="qf-ship-cost" type="number" step="0.01" value="0" oninput="qUpdateQuoteCalc()"></div>
          </div>
          <div class="q-form-group"><label class="q-form-label">Notes</label><textarea class="q-form-input" id="qf-notes" rows="3"></textarea></div>
        </div>
      </div>
    </div>

    <!-- Right Sidebar -->
    <div class="q-quote-sidebar">
      <div id="q-part-breakdowns">
        <!-- Per-part breakdowns inserted by JS -->
      </div>
      <div class="q-cost-preview">
        <div class="q-cost-preview-header">Combined Total</div>
        <div class="q-cost-row total"><span class="q-cost-row-label">Total Cost</span><span class="q-cost-row-value" id="qp-total-cost">$0.00</span></div>
        <div class="q-cost-row total highlight"><span class="q-cost-row-label">Suggested Price</span><span class="q-cost-row-value green" id="qp-total-suggested">$0.00</span></div>
        <div class="q-cost-row"><span class="q-cost-row-label">Quoted Price</span><span class="q-cost-row-value orange" id="qp-total-quoted">&mdash;</span></div>
        <div class="q-cost-row"><span class="q-cost-row-label">Margin</span><span class="q-cost-row-value" id="qp-total-margin">0%</span></div>
        <div class="q-cost-row"><span class="q-cost-row-label">Total Profit</span><span class="q-cost-row-value green" id="qp-total-profit">$0.00</span></div>
      </div>
      <div class="q-cost-preview" style="margin-top:8px">
        <div class="q-cost-preview-header">Pricing Schedule</div>
        <div style="overflow-x:auto">
          <table class="q-edit-table" style="font-size:11px">
            <thead><tr><th>Qty</th><th>Price/pc</th><th>Total</th><th>Margin</th></tr></thead>
            <tbody id="qp-schedule-body"></tbody>
          </table>
        </div>
      </div>
    </div>
  </div>
</div>
```

- [ ] **Step 2: Verify** — `python3 -c "import app; print('OK')"`

- [ ] **Step 3: Commit** — `git commit -m "feat: rebuild quote tab HTML with tabbed parts layout"`

---

### Task 3: Rewrite JS data layer — part state management

**Files:**
- Modify: `app.py` — JS functions near lines 5364-5660

**Context:** Replace the single-item form functions with a multi-part state system. The core data structure is an array `qFormParts[]` where each element holds one part's form data. A `qActivePartIdx` tracks which tab is active.

- [ ] **Step 1: Add part state management and tab rendering**

Replace `qPopulateFormSelects()`, `qGetFormData()`, and `qSetFormData()` (lines ~5366-5659) with the new multi-part system. Keep the function names but change their behavior.

The new code block (replaces from `var qCurrentEditSerial = null;` through end of `qSetFormData`):

```javascript
var qCurrentEditSerial = null;
var qFormParts = [];  // Array of part data objects
var qActivePartIdx = 0;

function qMakeEmptyPart(filename) {
  var printers = qState.settings.printers || [];
  var materials = qState.settings.materials || [];
  return {
    filename:         filename || '',
    printer:          printers.length ? printers[0].name : '',
    filament:         materials.length ? materials[0].name : '',
    weight_g:         0,
    print_time:       '',
    complexity:       1,
    quantity:         1,
    support_filament: '',
    support_weight_g: 0,
    prep_model:       0,
    prep_slice:       0,
    post_remove:      2,
    post_support:     5,
    post_extra:       0,
    fin_sand:         0,
    fin_paint:        0,
    fin_hardware:     0,
    fin_other:        0,
    consumables:      0,
    job_id:           null
  };
}

function qAddPart(partData) {
  qFormParts.push(partData || qMakeEmptyPart());
  qActivePartIdx = qFormParts.length - 1;
  qRenderPartTabs();
  qRenderActivePartForm();
  qUpdateQuoteCalc();
}

function qRemovePart(idx) {
  if (qFormParts.length <= 1) return;
  qFormParts.splice(idx, 1);
  if (qActivePartIdx >= qFormParts.length) qActivePartIdx = qFormParts.length - 1;
  qRenderPartTabs();
  qRenderActivePartForm();
  qUpdateQuoteCalc();
}

function qSwitchPart(idx) {
  qSaveActivePartToState();
  qActivePartIdx = idx;
  qRenderPartTabs();
  qRenderActivePartForm();
}

function qSaveActivePartToState() {
  if (qActivePartIdx < 0 || qActivePartIdx >= qFormParts.length) return;
  var p = qFormParts[qActivePartIdx];
  var v = function(id) { var el = document.getElementById(id); return el ? el.value : ''; };
  p.printer          = v('qfp-printer');
  p.filament         = v('qfp-filament');
  p.weight_g         = v('qfp-weight');
  p.print_time       = v('qfp-printtime');
  p.complexity       = v('qfp-complexity');
  p.quantity         = v('qfp-qty');
  p.support_filament = v('qfp-support-filament');
  p.support_weight_g = v('qfp-support-weight');
  p.prep_model       = v('qfp-prep-model');
  p.prep_slice       = v('qfp-prep-slice');
  p.post_remove      = v('qfp-post-remove');
  p.post_support     = v('qfp-post-support');
  p.post_extra       = v('qfp-post-extra');
  p.fin_sand         = v('qfp-fin-sand');
  p.fin_paint        = v('qfp-fin-paint');
  p.fin_hardware     = v('qfp-fin-hardware');
  p.fin_other        = v('qfp-fin-other');
  p.consumables      = v('qfp-consumables');
}

function qRenderPartTabs() {
  var container = document.getElementById('q-part-tabs');
  var html = '';
  for (var i = 0; i < qFormParts.length; i++) {
    var p = qFormParts[i];
    var label = p.filename ? p.filename : 'Part ' + (i + 1);
    if (label.length > 20) label = label.substring(0, 18) + '...';
    var closeBtn = qFormParts.length > 1 ? ' <span class="q-tab-close" onclick="event.stopPropagation();qRemovePart(' + i + ')">\\u2715</span>' : '';
    html += '<button class="q-part-tab' + (i === qActivePartIdx ? ' active' : '') + '" onclick="qSwitchPart(' + i + ')">' + label + closeBtn + '</button>';
  }
  html += '<button class="q-part-tab-add" onclick="qAddPart()">+ Add Part</button>';
  container.innerHTML = html;
}

function qRenderActivePartForm() {
  var p = qFormParts[qActivePartIdx];
  if (!p) return;
  var printers = qState.settings.printers || [];
  var materials = qState.settings.materials || [];
  var pOpts = printers.map(function(pr) { return '<option value="' + pr.name + '"' + (pr.name === p.printer ? ' selected' : '') + '>' + pr.name + '</option>'; }).join('');
  var mOpts = materials.map(function(m) { return '<option value="' + m.name + '"' + (m.name === p.filament ? ' selected' : '') + '>' + m.name + '</option>'; }).join('');
  var smOpts = '<option value="">None</option>' + materials.map(function(m) { return '<option value="' + m.name + '"' + (m.name === p.support_filament ? ' selected' : '') + '>' + m.name + '</option>'; }).join('');
  var cxOpts = '';
  for (var c = 1; c <= 10; c++) cxOpts += '<option value="' + c + '"' + (parseInt(p.complexity) === c ? ' selected' : '') + '>' + c + '</option>';

  var container = document.getElementById('q-part-content');
  container.innerHTML =
    '<div class="q-form-section" style="margin-top:0;border-top:none;padding-top:0">Print Details</div>' +
    '<div class="q-form-row q-form-row-3">' +
      '<div class="q-form-group"><label class="q-form-label">Printer</label><select class="q-form-input" id="qfp-printer" onchange="qPartFieldChanged()">' + pOpts + '</select></div>' +
      '<div class="q-form-group"><label class="q-form-label">Filament</label><select class="q-form-input" id="qfp-filament" onchange="qPartFieldChanged()">' + mOpts + '</select></div>' +
      '<div class="q-form-group"><label class="q-form-label">Quantity</label><input class="q-form-input" type="number" id="qfp-qty" value="' + (p.quantity || 1) + '" min="1" oninput="qPartFieldChanged()"></div>' +
    '</div>' +
    '<div class="q-form-row q-form-row-3">' +
      '<div class="q-form-group"><label class="q-form-label">Weight (g)</label><input class="q-form-input" type="number" id="qfp-weight" value="' + (p.weight_g || 0) + '" step="0.1" oninput="qPartFieldChanged()"></div>' +
      '<div class="q-form-group"><label class="q-form-label">Print Time (h)</label><input class="q-form-input" type="text" id="qfp-printtime" value="' + (p.print_time || '') + '" placeholder="5:47 or 5.78" oninput="qPartFieldChanged()"></div>' +
      '<div class="q-form-group"><label class="q-form-label">Complexity</label><select class="q-form-input" id="qfp-complexity" onchange="qPartFieldChanged()">' + cxOpts + '</select></div>' +
    '</div>' +
    '<div class="q-form-section">Secondary Material</div>' +
    '<div class="q-form-row q-form-row-2">' +
      '<div class="q-form-group"><label class="q-form-label">Support Filament</label><select class="q-form-input" id="qfp-support-filament" onchange="qPartFieldChanged()">' + smOpts + '</select></div>' +
      '<div class="q-form-group"><label class="q-form-label">Support Weight (g)</label><input class="q-form-input" type="number" id="qfp-support-weight" value="' + (p.support_weight_g || 0) + '" step="0.1" oninput="qPartFieldChanged()"></div>' +
    '</div>' +
    '<div class="q-form-section">Labor</div>' +
    '<div class="q-form-row q-form-row-3">' +
      '<div class="q-form-group"><label class="q-form-label">Prep Model (min)</label><input class="q-form-input" type="number" id="qfp-prep-model" value="' + (p.prep_model || 0) + '" oninput="qPartFieldChanged()"></div>' +
      '<div class="q-form-group"><label class="q-form-label">Prep Slice (min)</label><input class="q-form-input" type="number" id="qfp-prep-slice" value="' + (p.prep_slice || 0) + '" oninput="qPartFieldChanged()"></div>' +
      '<div class="q-form-group"><label class="q-form-label">Post Remove (min)</label><input class="q-form-input" type="number" id="qfp-post-remove" value="' + (p.post_remove !== undefined ? p.post_remove : 2) + '" oninput="qPartFieldChanged()"></div>' +
    '</div>' +
    '<div class="q-form-row q-form-row-2">' +
      '<div class="q-form-group"><label class="q-form-label">Post Support (min)</label><input class="q-form-input" type="number" id="qfp-post-support" value="' + (p.post_support !== undefined ? p.post_support : 5) + '" oninput="qPartFieldChanged()"></div>' +
      '<div class="q-form-group"><label class="q-form-label">Post Extra (min)</label><input class="q-form-input" type="number" id="qfp-post-extra" value="' + (p.post_extra || 0) + '" oninput="qPartFieldChanged()"></div>' +
    '</div>' +
    '<div class="q-form-section">Finishing Materials</div>' +
    '<div class="q-form-row q-form-row-4">' +
      '<div class="q-form-group"><label class="q-form-label">Sand ($)</label><input class="q-form-input" type="number" id="qfp-fin-sand" value="' + (p.fin_sand || 0) + '" step="0.01" oninput="qPartFieldChanged()"></div>' +
      '<div class="q-form-group"><label class="q-form-label">Paint ($)</label><input class="q-form-input" type="number" id="qfp-fin-paint" value="' + (p.fin_paint || 0) + '" step="0.01" oninput="qPartFieldChanged()"></div>' +
      '<div class="q-form-group"><label class="q-form-label">Hardware ($)</label><input class="q-form-input" type="number" id="qfp-fin-hardware" value="' + (p.fin_hardware || 0) + '" step="0.01" oninput="qPartFieldChanged()"></div>' +
      '<div class="q-form-group"><label class="q-form-label">Other ($)</label><input class="q-form-input" type="number" id="qfp-fin-other" value="' + (p.fin_other || 0) + '" step="0.01" oninput="qPartFieldChanged()"></div>' +
    '</div>' +
    '<div class="q-form-row q-form-row-2" style="margin-top:8px">' +
      '<div class="q-form-group"><label class="q-form-label">Consumables ($)</label><input class="q-form-input" type="number" id="qfp-consumables" value="' + (p.consumables || 0) + '" step="0.01" oninput="qPartFieldChanged()"></div>' +
      '<div></div>' +
    '</div>';
}

function qPartFieldChanged() {
  qSaveActivePartToState();
  qUpdateQuoteCalc();
}

// Shared fields getter (quote-level, not per-part)
function qGetSharedFormData() {
  var v = function(id) { var el = document.getElementById(id); return el ? el.value : ''; };
  return {
    customer:     v('qf-customer'),
    project:      v('qf-project'),
    description:  v('qf-description'),
    date:         v('qf-date'),
    status:       v('qf-status'),
    rush:         v('qf-rush'),
    notes:        v('qf-notes'),
    quoted_price: v('qf-quoted'),
    ship_pack:    v('qf-ship-pack'),
    ship_cost:    v('qf-ship-cost')
  };
}

// Build a calc-ready object for a single part
function qBuildPartCalcObj(part, shared) {
  return {
    filename:         part.filename || '',
    printer:          part.printer,
    filament:         part.filament,
    weight_g:         part.weight_g,
    print_time:       part.print_time,
    complexity:       part.complexity || 1,
    quantity:         part.quantity || 1,
    rush:             shared.rush || '1.0',
    support_filament: part.support_filament || '',
    support_weight_g: part.support_weight_g || 0,
    prep_model:       part.prep_model || 0,
    prep_slice:       part.prep_slice || 0,
    post_remove:      part.post_remove !== undefined ? part.post_remove : 2,
    post_support:     part.post_support !== undefined ? part.post_support : 5,
    post_extra:       part.post_extra || 0,
    fin_sand:         part.fin_sand || 0,
    fin_paint:        part.fin_paint || 0,
    fin_hardware:     part.fin_hardware || 0,
    fin_other:        part.fin_other || 0,
    ship_pack:        0,
    ship_cost:        0,
    consumables:      part.consumables || 0,
    quoted_price:     0
  };
}

// Keep old function names working for compatibility
function qPopulateFormSelects() {
  // No-op — selects are now rendered per-part in qRenderActivePartForm
}

function qGetFormData() {
  // Returns first part data merged with shared data for backwards compat
  qSaveActivePartToState();
  var shared = qGetSharedFormData();
  var part = qFormParts[0] || qMakeEmptyPart();
  var q = qBuildPartCalcObj(part, shared);
  q.customer = shared.customer;
  q.project = shared.project;
  q.description = shared.description;
  q.date = shared.date;
  q.status = shared.status;
  q.notes = shared.notes;
  q.quoted_price = shared.quoted_price;
  q.ship_pack = shared.ship_pack;
  q.ship_cost = shared.ship_cost;
  return q;
}

function qSetFormData(q) {
  // Legacy: load a single-part quote into the form
  var s = function(id, val) { var el = document.getElementById(id); if (el) el.value = val || ''; };
  s('qf-customer', q.customer);
  s('qf-project', q.project || '');
  s('qf-description', q.description);
  s('qf-date', q.date);
  s('qf-status', q.status || 'Quoting');
  s('qf-rush', q.rush || '1.0');
  s('qf-notes', q.notes);
  s('qf-quoted', q.quoted_price || '');
  s('qf-ship-pack', q.ship_pack || 0);
  s('qf-ship-cost', q.ship_cost || 0);
  // Load parts from line_items or single-part fields
  if (q.line_items && q.line_items.length > 0) {
    qFormParts = q.line_items.map(function(li) {
      return {
        filename: li.filename || '', printer: li.printer || '', filament: li.filament || '',
        weight_g: li.weight_g || 0, print_time: li.print_time || '', complexity: li.complexity || 1,
        quantity: li.quantity || 1, support_filament: li.support_filament || '', support_weight_g: li.support_weight_g || 0,
        prep_model: li.prep_model || 0, prep_slice: li.prep_slice || 0,
        post_remove: li.post_remove !== undefined ? li.post_remove : 2,
        post_support: li.post_support !== undefined ? li.post_support : 5,
        post_extra: li.post_extra || 0,
        fin_sand: li.fin_sand || 0, fin_paint: li.fin_paint || 0,
        fin_hardware: li.fin_hardware || 0, fin_other: li.fin_other || 0,
        consumables: li.consumables || 0, job_id: li.job_id || null
      };
    });
  } else {
    // Single-part legacy quote
    qFormParts = [{
      filename: q.description || '', printer: q.printer || '', filament: q.filament || '',
      weight_g: q.weight_g || 0, print_time: q.print_time || '', complexity: q.complexity || 1,
      quantity: q.quantity || 1, support_filament: q.support_filament || '', support_weight_g: q.support_weight_g || 0,
      prep_model: q.prep_model || 0, prep_slice: q.prep_slice || 0,
      post_remove: q.post_remove !== undefined ? q.post_remove : 2,
      post_support: q.post_support !== undefined ? q.post_support : 5,
      post_extra: q.post_extra || 0,
      fin_sand: q.fin_sand || 0, fin_paint: q.fin_paint || 0,
      fin_hardware: q.fin_hardware || 0, fin_other: q.fin_other || 0,
      consumables: q.consumables || 0, job_id: null
    }];
  }
  qActivePartIdx = 0;
  qRenderPartTabs();
  qRenderActivePartForm();
  qUpdateQuoteCalc();
}
```

**IMPORTANT:** All `\\u2715` in the code above is the correct Unicode escape for the X character used in tab close buttons. Do NOT convert this to a literal character.

- [ ] **Step 2: Verify** — `python3 -c "import app; print('OK')"`

- [ ] **Step 3: Commit** — `git commit -m "feat: rewrite JS data layer for multi-part state management"`

---

### Task 4: Rewrite qUpdateQuoteCalc with per-part sidebar breakdowns

**Files:**
- Modify: `app.py` — `qUpdateQuoteCalc()` function (lines ~5661-5709)

- [ ] **Step 1: Replace qUpdateQuoteCalc**

Replace the entire `qUpdateQuoteCalc()` function with:

```javascript
function qUpdateQuoteCalc() {
  var shared = qGetSharedFormData();
  var rush = parseFloat(shared.rush) || 1.0;
  var shipPack = parseFloat(shared.ship_pack) || 0;
  var shipCost = parseFloat(shared.ship_cost) || 0;
  var quotedOverride = parseFloat(shared.quoted_price) || 0;

  var breakdownContainer = document.getElementById('q-part-breakdowns');
  var breakdownHTML = '';
  var totalCost = 0, totalSuggested = 0, totalQty = 0;
  var allCalcs = [];

  for (var i = 0; i < qFormParts.length; i++) {
    var part = qFormParts[i];
    var q = qBuildPartCalcObj(part, shared);
    var c = qCalcFromQuoteData(q);
    allCalcs.push(c);
    totalCost += c.costTotal;
    totalSuggested += c.suggested;
    totalQty += Math.max(parseInt(part.quantity) || 1, 1);

    var label = part.filename ? part.filename : 'Part ' + (i + 1);
    if (label.length > 25) label = label.substring(0, 23) + '...';
    var isOpen = i === qActivePartIdx;
    breakdownHTML +=
      '<div class="q-part-breakdown">' +
        '<div class="q-part-breakdown-header" onclick="this.nextElementSibling.classList.toggle(\\\'open\\\')">' +
          '<span style="color:var(--q-text)">' + label + ' <span style="color:var(--q-text3);font-size:10px">(qty ' + (part.quantity || 1) + ')</span></span>' +
          '<span class="q-cost-row-value green">' + qCur(c.suggested) + '</span>' +
        '</div>' +
        '<div class="q-part-breakdown-body' + (isOpen ? ' open' : '') + '">' +
          '<div class="q-cost-row"><span class="q-cost-row-label">Material</span><span class="q-cost-row-value">' + qCur(c.filamentCost + c.suppCost) + '</span></div>' +
          '<div class="q-cost-row"><span class="q-cost-row-label">Machine</span><span class="q-cost-row-value">' + qCur(c.elecCost + c.deprCost) + '</span></div>' +
          '<div class="q-cost-row"><span class="q-cost-row-label">Labor</span><span class="q-cost-row-value">' + qCur(c.prepLabor + c.postLabor) + '</span></div>' +
          '<div class="q-cost-row"><span class="q-cost-row-label">Finishing</span><span class="q-cost-row-value">' + qCur(c.finishing) + '</span></div>' +
          '<div class="q-cost-row"><span class="q-cost-row-label">Failure</span><span class="q-cost-row-value yellow">' + (c.fail * 100).toFixed(0) + '%</span></div>' +
          '<div class="q-cost-row"><span class="q-cost-row-label">Cost/pc</span><span class="q-cost-row-value blue">' + qCur(c.costPP) + '</span></div>' +
          '<div class="q-cost-row"><span class="q-cost-row-label">Markup</span><span class="q-cost-row-value">' + c.markup.toFixed(2) + 'x</span></div>' +
        '</div>' +
      '</div>';
  }
  breakdownContainer.innerHTML = breakdownHTML;

  // Add shipping to totals
  totalCost += shipPack + shipCost;
  totalSuggested += shipPack + shipCost;

  var totalProfit = quotedOverride > 0 ? Math.max(quotedOverride - totalCost, 0) : Math.max(totalSuggested - totalCost, 0);
  var effectivePrice = quotedOverride > 0 ? quotedOverride : totalSuggested;
  var totalMargin = effectivePrice > 0 ? Math.max((effectivePrice - totalCost) / effectivePrice, 0) : 0;

  // Update combined totals
  var setText = function(id, val) { var el = document.getElementById(id); if (el) el.textContent = val; };
  setText('qp-total-cost', qCur(totalCost));
  setText('qp-total-suggested', qCur(totalSuggested));
  setText('qp-total-quoted', quotedOverride > 0 ? qCur(quotedOverride) : '\\u2014');
  setText('qp-total-margin', (totalMargin * 100).toFixed(0) + '%');
  setText('qp-total-profit', qCur(totalProfit));

  // Alert if quoted below cost
  var alertEl = document.getElementById('q-quote-alert');
  if (quotedOverride > 0 && quotedOverride < totalCost) {
    alertEl.innerHTML = '<div class="q-alert q-alert-danger">Quoted price (' + qCur(quotedOverride) + ') is below total cost (' + qCur(totalCost) + ')</div>';
  } else {
    alertEl.innerHTML = '';
  }

  // Pricing schedule (combined across all parts)
  var schedBody = document.getElementById('qp-schedule-body');
  var tiers = (qState.settings.discounts || []).slice().sort(function(a, b) { return a.qty - b.qty; });
  if (tiers.length > 0 && allCalcs.length > 0) {
    schedBody.innerHTML = tiers.map(function(tier) {
      var tierTotal = 0;
      for (var j = 0; j < qFormParts.length; j++) {
        var pc = allCalcs[j];
        var pQty = Math.max(parseInt(qFormParts[j].quantity) || 1, 1);
        var tierMarkup = Math.max(tier.markup, qState.settings.min_markup || 1.2) * rush;
        tierTotal += Math.max(pc.costPP * pQty * tierMarkup, qState.settings.min_fee || 5);
      }
      tierTotal += shipPack + shipCost;
      var tierPPU = totalQty > 0 ? tierTotal / totalQty : 0;
      var tierMargin = tierTotal > 0 ? Math.max((tierTotal - totalCost) / tierTotal, 0) : 0;
      var isActive = tier.qty <= totalQty;
      var lastActive = tiers.filter(function(t) { return t.qty <= totalQty; });
      var isCurrent = lastActive.length > 0 && tier.qty === lastActive[lastActive.length - 1].qty;
      return '<tr' + (isCurrent ? ' style="background:var(--q-bg3);font-weight:600"' : '') + '>' +
        '<td>' + Math.max(tier.qty, 1) + '+</td>' +
        '<td>' + qCur(tierPPU) + '</td>' +
        '<td>' + qCur(tierTotal) + '</td>' +
        '<td>' + (tierMargin * 100).toFixed(0) + '%</td></tr>';
    }).join('');
  } else {
    schedBody.innerHTML = '';
  }
}
```

- [ ] **Step 2: Verify** — `python3 -c "import app; print('OK')"`

- [ ] **Step 3: Commit** — `git commit -m "feat: rewrite qUpdateQuoteCalc with per-part sidebar breakdowns"`

---

### Task 5: Rewrite form lifecycle — qClearForm, qLogFullQuote, qEditQuote

**Files:**
- Modify: `app.py` — functions at lines ~5711-5788 and ~5466-5475

- [ ] **Step 1: Replace qClearForm**

Replace the entire `qClearForm()` function:

```javascript
function qClearForm() {
  qCurrentEditSerial = null;
  var titleEl = document.getElementById('q-quote-title');
  var subEl = document.getElementById('q-quote-sub');
  if (titleEl) titleEl.textContent = 'New Quote';
  if (subEl) subEl.textContent = 'Fill in the job details and the cost preview updates live.';
  var today = new Date().toISOString().slice(0, 10);
  var s = function(id, val) { var el = document.getElementById(id); if (el) el.value = val || ''; };
  s('qf-customer', '');
  s('qf-project', '');
  s('qf-description', '');
  s('qf-date', today);
  s('qf-status', 'Quoting');
  s('qf-rush', '1.0');
  s('qf-notes', '');
  s('qf-quoted', '');
  s('qf-ship-pack', '0');
  s('qf-ship-cost', '0');
  qFormParts = [qMakeEmptyPart()];
  qActivePartIdx = 0;
  qRenderPartTabs();
  qRenderActivePartForm();
  qUpdateQuoteCalc();
  var alertEl = document.getElementById('q-quote-alert');
  if (alertEl) alertEl.innerHTML = '';
}
```

- [ ] **Step 2: Replace qLogFullQuote**

Replace the entire `qLogFullQuote()` function:

```javascript
async function qLogFullQuote() {
  qSaveActivePartToState();
  var shared = qGetSharedFormData();
  if (!shared.customer) { alert('Enter a customer name.'); return; }

  // Build line_items from all parts
  var lineItems = qFormParts.map(function(part) {
    var q = qBuildPartCalcObj(part, shared);
    var c = qCalcFromQuoteData(q);
    return {
      filename: part.filename || '', printer: part.printer, filament: part.filament,
      weight_g: parseFloat(part.weight_g) || 0, print_time: part.print_time || '',
      complexity: parseInt(part.complexity) || 1, quantity: parseInt(part.quantity) || 1,
      support_filament: part.support_filament || '', support_weight_g: parseFloat(part.support_weight_g) || 0,
      prep_model: parseFloat(part.prep_model) || 0, prep_slice: parseFloat(part.prep_slice) || 0,
      post_remove: part.post_remove !== undefined ? parseFloat(part.post_remove) : 2,
      post_support: part.post_support !== undefined ? parseFloat(part.post_support) : 5,
      post_extra: parseFloat(part.post_extra) || 0,
      fin_sand: parseFloat(part.fin_sand) || 0, fin_paint: parseFloat(part.fin_paint) || 0,
      fin_hardware: parseFloat(part.fin_hardware) || 0, fin_other: parseFloat(part.fin_other) || 0,
      consumables: parseFloat(part.consumables) || 0, job_id: part.job_id || null,
      calc_cost_pp: c.costPP, calc_suggested: c.suggested, calc_margin: c.margin, calc_profit: c.totalProfit
    };
  });

  var totalCost = 0, totalSuggested = 0;
  lineItems.forEach(function(li) { totalCost += li.calc_cost_pp * li.quantity; totalSuggested += li.calc_suggested; });
  var shipTotal = (parseFloat(shared.ship_pack) || 0) + (parseFloat(shared.ship_cost) || 0);
  totalCost += shipTotal;
  totalSuggested += shipTotal;
  var quotedOverride = parseFloat(shared.quoted_price) || 0;
  var effectivePrice = quotedOverride > 0 ? quotedOverride : totalSuggested;
  var totalMargin = effectivePrice > 0 ? (effectivePrice - totalCost) / effectivePrice : 0;
  var totalProfit = effectivePrice - totalCost;

  await loadQuotingState();

  if (qCurrentEditSerial !== null) {
    var idx = qState.quotes.findIndex(function(q) { return q.serial === qCurrentEditSerial; });
    if (idx >= 0) {
      Object.assign(qState.quotes[idx], {
        customer: shared.customer, project: shared.project, description: shared.description,
        date: shared.date, status: shared.status, rush: shared.rush, notes: shared.notes,
        quoted_price: quotedOverride, ship_pack: parseFloat(shared.ship_pack) || 0, ship_cost: parseFloat(shared.ship_cost) || 0,
        line_items: lineItems, updated: new Date().toISOString(),
        calc_total_cost: totalCost, calc_total_suggested: totalSuggested,
        calc_total_margin: totalMargin, calc_total_profit: totalProfit
      });
      await saveQuotingState();
      alert('Quote #' + qFmtSerial(qCurrentEditSerial) + ' updated.');
      qCurrentEditSerial = null;
      qClearForm();
      showQTab('log');
      return;
    }
  }

  // New quote
  var serial = qState.settings.next_serial || 1;
  var dateStr = (shared.date || new Date().toISOString().slice(0, 10)).replace(/-/g, '');
  var custInit = (shared.customer || 'X').substring(0, 3).toUpperCase();
  var quoteId = serial + '-' + dateStr + '-' + custInit;
  var entry = {
    serial: serial, quote_id: quoteId,
    customer: shared.customer, project: shared.project, description: shared.description,
    date: shared.date, status: shared.status, rush: shared.rush, notes: shared.notes,
    quoted_price: quotedOverride, ship_pack: parseFloat(shared.ship_pack) || 0, ship_cost: parseFloat(shared.ship_cost) || 0,
    line_items: lineItems, created: new Date().toISOString(),
    calc_total_cost: totalCost, calc_total_suggested: totalSuggested,
    calc_total_margin: totalMargin, calc_total_profit: totalProfit
  };
  qState.quotes.push(entry);

  // Auto-create customer
  var custExists = (qState.customers || []).some(function(c) { return c.name === shared.customer; });
  if (!custExists) {
    qState.customers = qState.customers || [];
    qState.customers.push({ name: shared.customer, created: new Date().toISOString() });
  }
  qState.settings.next_serial = serial + 1;
  await saveQuotingState();
  alert('Quote #' + qFmtSerial(serial) + ' logged \\u2014 ' + qCur(totalSuggested));
  qCurrentEditSerial = null;
  qClearForm();
  showQTab('log');
}
```

- [ ] **Step 3: Replace qEditQuote**

Replace the entire `qEditQuote(serial)` function:

```javascript
function qEditQuote(serial) {
  var q = qState.quotes.find(function(q) { return q.serial === serial; });
  if (!q) return;
  qCurrentEditSerial = serial;
  showQTab('quote');
  qSetFormData(q);
  var titleEl = document.getElementById('q-quote-title');
  var subEl = document.getElementById('q-quote-sub');
  if (titleEl) titleEl.textContent = 'Editing Quote #' + qFmtSerial(serial);
  if (subEl) subEl.textContent = (q.customer || '') + ' \\u2014 ' + (q.description || '');
}
```

- [ ] **Step 4: Verify** — `python3 -c "import app; print('OK')"`

- [ ] **Step 5: Commit** — `git commit -m "feat: rewrite form lifecycle for multi-part quotes"`

---

### Task 6: Update qRenderQuoteLog with expandable rows

**Files:**
- Modify: `app.py` — `qRenderQuoteLog()` function (lines ~5411-5457)

- [ ] **Step 1: Replace qRenderQuoteLog**

Replace the entire `qRenderQuoteLog()` function:

```javascript
function qRenderQuoteLog() {
  var search = (document.getElementById('q-log-search').value || '').toLowerCase();
  var statusFilter = document.getElementById('q-log-status') ? document.getElementById('q-log-status').value : '';
  var quotes = (qState.quotes || []).slice().sort(function(a, b) { return (b.serial || 0) - (a.serial || 0); });
  var filtered = quotes.filter(function(q) {
    if (statusFilter && q.status !== statusFilter) return false;
    if (!search) return true;
    return ((q.customer || '') + ' ' + (q.description || '') + ' ' + (q.quote_id || '')).toLowerCase().indexOf(search) >= 0;
  });

  var table = document.getElementById('q-log-table');
  var empty = document.getElementById('q-log-empty');
  if (filtered.length === 0) {
    if (table) table.style.display = 'none';
    if (empty) { empty.style.display = 'block'; empty.textContent = search || statusFilter ? 'No quotes match your search.' : 'No quotes yet. Create one from the Quote tab.'; }
    return;
  }
  if (table) table.style.display = '';
  if (empty) empty.style.display = 'none';

  var body = document.getElementById('q-log-body');
  if (!body) return;
  body.innerHTML = filtered.map(function(q) {
    var s = q.serial || 0;
    var li = q.line_items || [];
    var partCount = li.length;
    var totalQty = 0;
    var totalSugg = q.calc_total_suggested || q.total_suggested || 0;
    if (partCount > 0) {
      li.forEach(function(item) { totalQty += (item.quantity || 1); });
    } else {
      totalQty = q.quantity || 1;
      totalSugg = q.calc_suggested || totalSugg;
    }
    var desc = q.description || '';
    var partsBadge = partCount > 1 ? '<span class="q-log-parts-badge">' + partCount + ' parts</span>' : '';
    var expandBtn = partCount > 1 ? '<button class="q-log-expand" onclick="qToggleLogExpand(this,' + s + ')">\\u25b6</button>' : '';
    var statusCls = (q.status || 'Quoting').toLowerCase().replace(/\\s+/g, '-');

    var mainRow = '<tr>' +
      '<td>' + expandBtn + qFmtSerial(s) + '</td>' +
      '<td style="font-size:11px">' + (q.quote_id || '') + '</td>' +
      '<td>' + (q.date || q.created || '').substring(0, 10) + '</td>' +
      '<td>' + (q.customer || '') + '</td>' +
      '<td>' + desc + partsBadge + '</td>' +
      '<td><span class="q-status-badge q-status-' + statusCls + '">' + (q.status || 'Quoting') + '</span></td>' +
      '<td>' + totalQty + '</td>' +
      '<td>' + qCur(totalSugg) + '</td>' +
      '<td><button class="q-btn q-btn-ghost q-btn-sm" onclick="qEditQuote(' + s + ')">Edit</button> <button class="q-btn q-btn-danger q-btn-sm" onclick="qDeleteQuote(' + s + ')">\\u2715</button></td>' +
    '</tr>';

    // Sub-rows for line items (hidden by default)
    var subRows = '';
    if (partCount > 1) {
      subRows = li.map(function(item) {
        return '<tr class="q-log-sub-row" data-serial="' + s + '" style="display:none">' +
          '<td></td>' +
          '<td colspan="2">' + (item.filename || 'Part') + '</td>' +
          '<td>' + (item.filament || '') + '</td>' +
          '<td>' + (item.printer || '') + '</td>' +
          '<td></td>' +
          '<td>' + (item.quantity || 1) + '</td>' +
          '<td>' + qCur(item.calc_suggested || item.suggested || 0) + '</td>' +
          '<td></td>' +
        '</tr>';
      }).join('');
    }

    return mainRow + subRows;
  }).join('');
}

function qToggleLogExpand(btn, serial) {
  btn.classList.toggle('open');
  var rows = document.querySelectorAll('.q-log-sub-row[data-serial="' + serial + '"]');
  rows.forEach(function(row) {
    row.style.display = row.style.display === 'none' ? '' : 'none';
  });
}
```

- [ ] **Step 2: Verify** — `python3 -c "import app; print('OK')"`

- [ ] **Step 3: Commit** — `git commit -m "feat: expandable rows in quote log for multi-part quotes"`

---

### Task 7: Update prefillQuoteForm for multi-part

**Files:**
- Modify: `app.py` — `prefillQuoteForm()` function (lines ~5790-5832)

- [ ] **Step 1: Replace prefillQuoteForm**

Replace the entire `prefillQuoteForm(qqItemsData)` function:

```javascript
function prefillQuoteForm(qqItemsData) {
  if (!qqItemsData || qqItemsData.length === 0) return;
  var customer = document.getElementById('qq-customer') ? document.getElementById('qq-customer').value : '';
  var today = new Date().toISOString().slice(0, 10);

  // Build line_items from all qqItems
  var parts = qqItemsData.map(function(item) {
    var mat = qGetMaterial(item.filament);
    var timeMult = mat ? (mat.time_multiplier || 1.0) : 1.0;
    var weightMult = mat ? (mat.weight_multiplier || 1.0) : 1.0;
    return {
      filename:         item.slicerData.filename || '',
      printer:          item.printer || '',
      filament:         item.filament || '',
      weight_g:         ((item.slicerData.base_weight_g || 0) * weightMult).toFixed(2),
      print_time:       (((item.slicerData.base_time_minutes || 0) / 60) * timeMult).toFixed(2),
      complexity:       item.slicerData.complexity || (mat ? mat.complexity : 1),
      quantity:         item.quantity || 1,
      support_filament: '',
      support_weight_g: 0,
      prep_model: 0, prep_slice: 0, post_remove: 2, post_support: 5, post_extra: 0,
      fin_sand: 0, fin_paint: 0, fin_hardware: 0, fin_other: 0,
      consumables: 0,
      job_id: item.slicerData.job_id || null
    };
  });

  // Build a quote-like object and load it
  qSetFormData({
    customer: customer,
    description: parts.length === 1 ? parts[0].filename : parts.length + ' parts from slicer',
    date: today,
    status: 'Quoting',
    rush: '1.0',
    notes: '',
    quoted_price: '',
    ship_pack: 0,
    ship_cost: 0,
    line_items: parts
  });
}
```

- [ ] **Step 2: Verify** — `python3 -c "import app; print('OK')"`

- [ ] **Step 3: Commit** — `git commit -m "feat: prefillQuoteForm creates tabs for all quick quote items"`

---

### Task 8: Backwards compatibility for old single-part quotes

**Files:**
- Modify: `app.py` — no new code needed

**Context:** The `qSetFormData` function in Task 3 already handles backwards compatibility: if a quote has no `line_items` array, it constructs a single-item array from root-level fields. The `qRenderQuoteLog` in Task 6 handles both formats too. This task verifies no edge cases were missed.

- [ ] **Step 1: Verify old Quick Quote logged quotes still load**

Quick Quote's `logQuickQuote()` already saves with a `line_items` array (since earlier in the session). The `qEditQuote` → `qSetFormData` path handles this because `qSetFormData` checks for `q.line_items`.

Check that `logQuickQuote` line items have all the fields the new form expects. Read the `logQuickQuote` function and verify its line item fields match the fields in `qSetFormData`'s `line_items` mapper.

If any fields are missing from `logQuickQuote`'s line items (e.g., `prep_model`, `post_remove`, etc.), they'll get defaults in `qSetFormData` — this is correct behavior.

- [ ] **Step 2: Verify** — `python3 -c "import app; print('OK')"`

- [ ] **Step 3: Commit** — `git commit -m "chore: verify backwards compatibility for single-part and quick-quote formats"`

---

### Task 9: Final verification — restart and test all paths

- [ ] **Step 1: Restart server**

```bash
lsof -ti :5111 | xargs kill 2>/dev/null; python3 app.py &
```

- [ ] **Step 2: Test new quote with single part**
- Go to Quote tab, verify single tab "Part 1" appears
- Fill in customer, printer, filament, weight, time
- Verify sidebar shows breakdown + combined total
- Save quote, verify it appears in log

- [ ] **Step 3: Test new quote with multiple parts**
- Click "+ Add Part" to add 2nd and 3rd tabs
- Fill different printers/filaments for each
- Switch between tabs, verify data persists
- Remove a part tab, verify remaining tabs reindex
- Save, verify log shows expandable row with part count badge

- [ ] **Step 4: Test edit flow**
- Click Edit on a multi-part quote in the log
- Verify all tabs restore with correct data
- Modify a field, save, verify update

- [ ] **Step 5: Test Quick Quote → Full Details flow**
- Batch slice 2+ files, send to Quick Quote
- Click "Full Details" from Quick Quote overlay
- Verify all items appear as tabs in Full Quote form
- Verify quantities, printers, filaments carry over

- [ ] **Step 6: Test backwards compat**
- Edit an existing single-part quote from the log
- Verify it loads as a single tab
- Save it — verify it saves in new line_items format

- [ ] **Step 7: Commit all remaining changes**

```bash
git add app.py
git commit -m "feat: multi-part full quote form complete"
```
