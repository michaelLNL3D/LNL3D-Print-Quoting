# 3D Print Quoting Tool — Functional & UI/UX Audit Plan

**Goal:** Personal tool hardening — catch bugs, improve workflow efficiency, fix annoyances.
**Approach:** Clean-slate audit of all functionality and UI/UX in app.py (~2988 lines).

## 1. Functional Correctness

| # | Check | What to verify |
|---|-------|----------------|
| 1.1 | Quote math accuracy | Verify material_cost, machine_cost, markup, and total formulas match spec. Check rounding. Test edge values (0 markup, 0 hourly rate, qty=1 vs >1, farm_size=1 vs >1). |
| 1.2 | Time parsing robustness | `parseTimeToMins()` handles d/h/m/s — test with real GCode outputs including days, seconds-only, mixed formats. Check NaN propagation. |
| 1.3 | Preset save/load fidelity | Save preset, reload page, load — do ALL fields restore? Are newer fields missing from older presets? |
| 1.4 | LocalStorage persistence | Refresh page — do printer, profiles, overrides, toggles, size mode all restore? Fields that silently reset? |
| 1.5 | Cascading dropdown state | Select printer → profiles load → select print + filament → change printer → do dependent dropdowns reset correctly? Stale selections? |
| 1.6 | Pre-flight check accuracy | Does `check_size` correctly detect oversized models? Handles models with no readable bounds? Do Scale to Fit / Auto-Split / Quote Anyway all work? |
| 1.7 | Mesh health warnings | Are warnings (non-watertight, flipped normals, thin features, high poly) accurate? False positives on normal files? |
| 1.8 | Auto-orient behavior | Does auto-orient change the result? OrcaSlicer missing = graceful fallback or crash? |
| 1.9 | Auto-split behavior | Split produces correct pieces? Models that can't be split? Trimesh missing = graceful skip? |
| 1.10 | Scale-to-fit math | 95% build volume scaling correct? Uses correct axis constraints from printer INI? |
| 1.11 | GCode export | Single-piece download? Multi-piece ZIP? Job_id expiry from 50-job cache? |
| 1.12 | 3MF export | Exports last job correctly? Export before running any quote? |
| 1.13 | Build volume detection | INI inheritance chain walks `inherits` correctly? Non-rectangular beds? |
| 1.14 | File type handling | Test STL, OBJ, 3MF, AMF, STEP/STP. Error messages for unsupported formats? |
| 1.15 | Large file handling | Files >50MB, >100MB? Timeouts, memory issues, missing warnings? |

## 2. Batch Mode

| # | Check | What to verify |
|---|-------|----------------|
| 2.1 | Per-file settings | Queue 3 files with different settings — retained when switching? |
| 2.2 | Skip-done behavior | Re-run batch skips done files? Force re-quote single file? |
| 2.3 | Queue manipulation | Add, remove middle, add more — indexing correct? Clear All fully resets? |
| 2.4 | Batch results table | Totals correct? Row clicks open right modal? |
| 2.5 | Error in batch | One file fails — processing continues? Failed file clearly marked? |
| 2.6 | Single to Batch transition | Upload 1 file (single), add another (batch) — clean transition? |

## 3. UI/UX Friction

| # | Check | What to verify |
|---|-------|----------------|
| 3.1 | Drop zone feedback | Drag-over visible? Drop outside zone? Multiple rapid drops? |
| 3.2 | Loading/progress clarity | Always obvious slicing is in progress? Double-submit prevention? Progress bar meaningful? |
| 3.3 | Error message quality | Actionable messages or opaque failures? |
| 3.4 | Button state management | Disabled during ops? Run button text correct? |
| 3.5 | Results panel transitions | Placeholder → preflight → results → error: flicker, stale content, layout jumps? |
| 3.6 | Copy Quote formatting | Pasted text looks good? Missing fields? Weird formatting? |
| 3.7 | Modal behavior | Closes on Escape / click outside? Background scroll locked? |
| 3.8 | Form layout at breakpoint | 800px single-column works? Overlapping or truncated elements? |
| 3.9 | Input validation feedback | Negative values, text in number fields, empty required — clear feedback? |
| 3.10 | Toggle button clarity | Active/inactive states visually distinct? |
| 3.11 | Debug panel usability | Easy open/close? Interferes with main UI? Error entries useful? |
| 3.12 | Preset UX | Obvious save/load/delete? Empty name? Duplicate name? |

## 4. State & Edge Cases

| # | Check | What to verify |
|---|-------|----------------|
| 4.1 | Page refresh mid-quote | Orphaned progress entries? Zombie processes? |
| 4.2 | Server restart recovery | UI handles lost in-memory state gracefully? |
| 4.3 | Rapid operations | Double-click quote, upload during slicing, change printer during slicing — race conditions? |
| 4.4 | Empty state | No presets, no profiles — helpful guidance or empty dropdowns? |
| 4.5 | Missing slicer binaries | PrusaSlicer/OrcaSlicer not installed — clear error or crash? |
| 4.6 | Temp file cleanup | `/tmp/prusaquoting_exports/` grows unbounded? Cleanup mechanism? |
| 4.7 | Memory leaks | `_progress` dict leaks on errors? `_jobs` 50-cap enforced? |
| 4.8 | Concurrent tabs | Progress cross-contamination? `_last_job` overwritten? |

## 5. Code Quality (affecting reliability)

| # | Check | What to verify |
|---|-------|----------------|
| 5.1 | JS string escaping | Python `'\n\n'` in triple-quoted HTML breaking JS strings? |
| 5.2 | XSS in filenames | `esc()` catches everywhere? |
| 5.3 | Error logging coverage | All try/except blocks logging via `_log_error()`? Silent swallows? |
| 5.4 | Support mode strings | Hard-coded values match what PrusaSlicer accepts? |
| 5.5 | INI parsing edge cases | Special characters, spaces, unicode in printer profiles? |

## Deliverable

For each item:
1. Read relevant code to identify issue or confirm it's fine
2. Categorize: Bug, UX Friction, Missing Validation, or Enhancement
3. Rate severity: High (breaks workflow), Medium (annoying), Low (cosmetic/minor)
4. Propose fix with estimated complexity
