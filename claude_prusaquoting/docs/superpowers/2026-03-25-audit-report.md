# 3D Print Quoting Tool — Audit Report

**Date:** 2026-03-25
**Scope:** Full functional + UI/UX audit of app.py (~2988 lines)
**Focus:** Personal tool hardening — bugs, workflow friction, reliability

---

## Executive Summary

**44 issues found** across 5 audit sections (out of ~120 items checked).

| Severity | Count |
|----------|-------|
| High     | 3     |
| Medium   | 18    |
| Low      | 23    |

| Category            | Count |
|---------------------|-------|
| Bug                 | 19    |
| UX Friction         | 13    |
| Missing Validation  | 5     |
| Silent Swallow      | 6     |
| Design              | 1     |

---

## High Severity (3)

These break workflow or produce wrong results.

### H1. Missing PrusaSlicer binary crashes with cryptic error
- **ID:** 4.5a | **Category:** Bug | **Lines:** 87-88
- `run_slicer()` calls `subprocess.run()` with no existence check. If PrusaSlicer isn't at the configured path, Python raises `FileNotFoundError` with no helpful message.
- **Fix:** Check `os.path.exists(PRUSASLICER)` at startup or in `run_slicer()`. Raise a clear error: `"PrusaSlicer not found at {path}. Set PRUSASLICER_PATH env var."`
- **Complexity:** S

### H2. Missing OrcaSlicer binary kills entire quote instead of skipping orient
- **ID:** 1.8b / 4.5b | **Category:** Bug | **Lines:** 242-271
- `auto_orient()` calls `run_orca()` which raises `FileNotFoundError` if OrcaSlicer is missing. This exception is uncaught — it kills the entire quote with a 500 error instead of gracefully skipping orientation.
- **Fix:** Wrap `run_orca()` in try/except in `auto_orient()`. On `FileNotFoundError`, return `(input_path, "orient skipped — OrcaSlicer not found")`.
- **Complexity:** S

### H3. Concurrent tabs overwrite `_last_job`, corrupting 3MF/INI exports
- **ID:** 4.8a / 1.12c | **Category:** Bug | **Lines:** 35, 886-898, 1164-1198
- `_last_job` is a single global dict. If two tabs run quotes, the second overwrites the first's export data. Clicking "Download 3MF" returns the wrong model.
- **Fix:** Store export metadata in `_jobs[job_id]` instead of `_last_job`. Have 3MF/INI exports accept a `job_id` parameter.
- **Complexity:** M

---

## Medium Severity (18)

These are annoying, produce confusing behavior, or silently lose data.

### M1. `_progress` dict leaks entries and has no size cap
- **ID:** 4.1a / 4.7a | **Category:** Bug | **Lines:** 42, 44-54
- Page refresh mid-quote orphans progress entries permanently. Unlike `_jobs` (50 cap) and `_error_log` (100 cap), `_progress` is uncapped.
- **Fix:** Add timestamp tracking to entries. Evict entries older than 5 minutes on each `_emit()` call, or cap at 200 entries.
- **Complexity:** S

### M2. Double-click can fire duplicate quote requests
- **ID:** 4.3a | **Category:** Bug | **Lines:** 2177-2183
- `btn.disabled = true` is set after initial checks, so a fast double-click can enter `runQuote()` twice before the first call disables the button.
- **Fix:** Add an `_isQuoting` guard at the top of `runQuote()` that returns immediately if true. Set false in `finally`.
- **Complexity:** S

### M3. `PRESET_KEYS` missing several fields
- **ID:** 1.3a / 3.12h | **Category:** Bug | **Lines:** 687-689, 2779-2792
- Presets don't save/restore `time_factor`, `size_mode`, `size_val`, `quantity`, `auto_orient`, `auto_split`, or `auto_scale_fit`. Users who save a preset with specific sizing or feature toggles lose those settings on load.
- **Fix:** Add all missing fields to `PRESET_KEYS` and to the JS `confirmSavePreset()` body.
- **Complexity:** S

### M4. `clearQueue()` doesn't reset results panel
- **ID:** 2.3c | **Category:** Bug | **Lines:** 2147-2157
- After clearing the file queue, stale results/batch tables/error boxes remain visible. The right panel appears broken.
- **Fix:** Hide `#results`, `#batch-results`, `#error-box`, `#rc-tabs` and restore `#placeholder` in `clearQueue()`.
- **Complexity:** S

### M5. Scale mode may pass percentage as ratio to PrusaSlicer
- **ID:** 1.10d | **Category:** Bug | **Lines:** 429-431
- PrusaSlicer `--scale` expects a ratio (1.5 = 150%), but the UI may provide a percentage. Entering `150` meaning 150% would scale to 15000%.
- **Fix:** Verify the UI label. If it says "Scale %", divide by 100 before passing to `--scale`. Or clarify the label says "Scale factor".
- **Complexity:** S

### M6. No `MAX_CONTENT_LENGTH` — unlimited upload size
- **ID:** 1.15a | **Category:** Missing Validation | **Lines:** N/A
- Flask has no upload limit configured. Arbitrarily large files can consume all server memory.
- **Fix:** `app.config['MAX_CONTENT_LENGTH'] = 500 * 1024 * 1024`
- **Complexity:** S

### M7. Support mode values not validated server-side
- **ID:** 5.4a | **Category:** Bug | **Lines:** 541-552, 863
- JS sends `none/grid/snug/organic` but Python passes directly to PrusaSlicer with no validation. Invalid values produce opaque slicer errors.
- **Fix:** Validate against allowed set, return 400 for invalid values.
- **Complexity:** S

### M8. No cleanup of old GCode files in EXPORT_DIR
- **ID:** 4.6a | **Category:** Bug | **Lines:** 30-32, 1013, 1120-1121
- GCode files accumulate in `/tmp/prusaquoting_exports/` indefinitely. When `_jobs` evicts old entries, their files remain.
- **Fix:** Delete associated gcode files when evicting from `_jobs`. Add a startup sweep for files older than 24h.
- **Complexity:** S

### M9. `qty_subtotal=0` suppresses `total_price` via falsy check
- **ID:** 1.1b | **Category:** Bug | **Lines:** 1107
- `if markup and qty_subtotal` uses truthiness — when both costs are $0 (free material, no hourly rate), `qty_subtotal` is 0 (falsy) and `total_price` becomes `None`.
- **Fix:** Use explicit `qty_subtotal is not None` check.
- **Complexity:** S

### M10. Duplicate preset name silently overwrites
- **ID:** 3.12b | **Category:** UX Friction | **Lines:** 2776-2803
- Saving a preset with an existing name overwrites without confirmation.
- **Fix:** Check if name exists in `presetsCache` and prompt "Overwrite existing preset?".
- **Complexity:** S

### M11. Pre-flight check failure falls through silently to slicing
- **ID:** 3.3e | **Category:** UX Friction | **Lines:** 2226-2230
- If the `/api/check_size` fetch throws, the error is caught, hidden, and slicing proceeds with no warning.
- **Fix:** Show a brief warning that pre-flight failed before continuing, or log visibly.
- **Complexity:** S

### M12. `copyModalQuote()` gives no visual feedback
- **ID:** 3.6d | **Category:** UX Friction | **Lines:** 2501-2513
- Unlike `copyQuote()` which shows "Copied!", the modal copy function has no feedback.
- **Fix:** Add the same "Copied!" flash pattern.
- **Complexity:** S

### M13. No client-side validation before submit
- **ID:** 3.9f | **Category:** Missing Validation | **Lines:** 2177-2234
- No validation of numeric inputs (cost, markup, qty, farm_size). Empty pricing fields proceed without warning.
- **Fix:** Warn if pricing fields are empty. Clamp out-of-range values.
- **Complexity:** S

### M14. Init failure only shows subtle dropdown text
- **ID:** 3.3d | **Category:** UX Friction | **Lines:** 1808-1811
- If the server is unreachable at init, the printer dropdown shows "-- server unreachable --" but there's no prominent error banner.
- **Fix:** Show a visible error banner at the top of the page.
- **Complexity:** S

### M15. Quantity input allows zero/negative via keyboard
- **ID:** 3.9c | **Category:** Missing Validation | **Lines:** 1679
- HTML `min="1"` only constrains spinner, not keyboard input. `qty=0` produces a zero-cost quote.
- **Fix:** Clamp in `buildFormData()` or validate server-side.
- **Complexity:** S

### M16. Silent error swallows in mesh processing (4 locations)
- **ID:** 5.3b/5.3c/5.3g/5.3i | **Category:** Silent Swallow | **Lines:** 294-300, 320-325, 826-827, 1031-1033
- `get_mesh_bounds()` trimesh fallback, `_split_mesh_along_axis()`, outer health check block, and `slice_piece` RuntimeError all catch exceptions without calling `_log_error()`. Debugging failures is impossible.
- **Fix:** Add `_log_error()` calls in each location.
- **Complexity:** S

### M17. Batch settings snapshot taken lazily
- **ID:** 2.1a | **Category:** Design | **Lines:** 2119-2126
- Files added to queue have no settings snapshot. Settings are only captured when clicking a different queue item. The gear icon misleadingly implies per-file customization exists.
- **Fix:** Snapshot `getFormSettings()` for all items at batch-run time, or on file add.
- **Complexity:** S

### M18. 3MF export only supports last job, not per-job
- **ID:** 1.12b | **Category:** UX Friction | **Lines:** 1164-1198
- Unlike GCode export which accepts `job_id`, 3MF export always uses `_last_job`. In batch mode, only the last file's 3MF can be exported.
- **Fix:** Add `job_id` support, store export metadata in `_jobs`.
- **Complexity:** M

---

## Low Severity (23)

Cosmetic, theoretical edge cases, or minor polish.

| ID | Title | Category | Lines | Proposed Fix |
|----|-------|----------|-------|-------------|
| 1.1a | Empty markup string produces None price | Bug | 1087 | Default markup to "0" when empty |
| 1.2c | Fractional seconds in GCode not parsed | Missing Val. | 467-475 | Use `float()` in regex |
| 1.3b | Presets don't save size_mode/size_val | Enhancement | 687-689 | Add to PRESET_KEYS |
| 1.4c | localStorage not cleared on field clear | UX Friction | 2829-2830 | Store unconditionally |
| 1.5b | Stale profile silently submitted | UX Friction | 1826-1829 | Highlight when profile reverts |
| 1.14c | `/api/check_size` doesn't validate extension | Missing Val. | 750-757 | Add allowed set check |
| 2.1c | Settings drift between form and snapshot | Bug | 1947-1956 | Auto-save on form change |
| 2.2b | No re-quote single item in batch | Design | 2177-2180 | Add per-item re-quote button |
| 2.2c | Re-run batch when all done = silent no-op | Bug | 2390-2391 | Show "All files already quoted" |
| 2.3b | deleteQueueItem enables button without checking printer | Bug | 1965-1967 | Call `updateRunBtn()` |
| 2.6b | `_lastQuote` leaks from single to batch mode | Bug | 2272, 2652 | Clear in addFilesToQueue |
| 2.6d | `updateRunBtn` doesn't set button text | Bug | 2886-2891 | Set text based on queue length |
| 3.1b | Non-model files silently ignored on drop | UX Friction | 1871 | Show "Unsupported file type" toast |
| 3.1c | Non-file drag content = no-op without feedback | UX Friction | 1869-1872 | Show "Please drop model files" |
| 3.2c | Progress polling silently swallows errors | UX Friction | 2013-2014 | Show "connection lost" after N failures |
| 3.5c | Placeholder not restored on queue clear | UX Friction | 2147-2157 | Restore placeholder in clearQueue |
| 3.7c | Body scroll not locked when modal open | UX Friction | 2496 | Set body overflow hidden |
| 3.9e | Markup has no max | UX Friction | 1675 | Add max=500 or confirm extreme |
| 3.9g | Farm size allows zero (div by zero) | Missing Val. | 1685 | Validate >= 1 both sides |
| 4.2a | GCode download after restart = unhelpful error | Bug | 1211-1236 | Error message is adequate |
| 4.4a | Empty printer list shows no guidance | Bug | 1797-1811 | Add "No printers found" notice |
| 5.4b | Infill/layer_h/walls unvalidated server-side | Bug | 541-552 | Add numeric range checks |
| 5.5d | Circular INI inherits = exponential calls before depth cap | Bug | 179-201 | Add visited set |

---

## Recommended Fix Order

**Phase 1 — Quick wins (all S complexity, ~30 min total):**
H1, H2, M1, M2, M4, M5, M6, M7, M9, M12, M15

**Phase 2 — UX polish (~30 min):**
M3, M10, M11, M13, M14, M16, M17

**Phase 3 — Architecture (~1 hour):**
H3, M8, M18

**Phase 4 — Low-severity sweep (optional):**
All Low items, in any order
