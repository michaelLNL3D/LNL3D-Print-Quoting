# Functional & UI/UX Audit — Execution Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Audit the 3D Print Quoting Tool (app.py, ~2988 lines) for bugs, UX friction, missing validation, and reliability issues. Produce an itemized findings report.

**Architecture:** Five parallel audit agents each examine a section of the codebase, writing findings to individual markdown files. A final task merges them into a single prioritized report.

**Tech Stack:** Python/Flask (app.py), vanilla JS/CSS (embedded in app.py), PrusaSlicer CLI

**Reference — app.py line map:**
- Lines 1-66: Imports, constants, state dicts, helpers (`_emit`, `_log_error`)
- Lines 68-82: Flask init, global error handler
- Lines 87-91: `run_slicer()`, `run_orca()`
- Lines 94-142: Printer/profile discovery
- Lines 147-237: INI parsing, build volume detection
- Lines 242-271: Auto-orient (OrcaSlicer)
- Lines 276-418: Mesh bounds, splitting
- Lines 423-485: Size parsing, GCode parsing, time helpers
- Lines 490-662: Profile flags, machine limits, `slice_piece()`
- Lines 667-669: GET `/` route
- Lines 672-723: Printers, profiles, presets routes
- Lines 726-743: Debug log, progress routes
- Lines 746-846: POST `/api/check_size` (pre-flight)
- Lines 848-1161: POST `/api/quote` (main quote logic, cost calc at 1070-1118)
- Lines 1164-1236: Export routes (3MF, INI, GCode)
- Lines 1241-1525: CSS (`<style>` block)
- Lines 1526-1791: HTML body markup
- Lines 1792-2911: Main JS (`<script>` block 1)
- Lines 2912-2973: Debug panel JS (`<script>` block 2)
- Lines 2976-2988: Server startup

---

### Task 1: Audit — Functional Correctness (items 1.1–1.15)

**Files to read:**
- `app.py:848-1161` — `/api/quote` route (cost calc at 1070-1118)
- `app.py:436-485` — GCode parsing, `time_to_minutes()`, `mins_to_str()`
- `app.py:686-723` — Preset routes and persistence
- `app.py:746-846` — `/api/check_size` pre-flight
- `app.py:276-418` — `get_mesh_bounds()`, split logic
- `app.py:242-271` — `auto_orient()`
- `app.py:423-431` — `parse_size()`
- `app.py:147-237` — INI parsing, `get_build_volume()`
- `app.py:633-662` — `slice_piece()`
- `app.py:1164-1236` — Export routes (3MF, GCode)
- `app.py:1792-2911` — JS: `parseTimeToMins()`, `buildFormData()`, localStorage restore

**Audit checklist — examine each and document findings:**

- [ ] **1.1 Quote math accuracy** — Read cost calc (lines 1070-1118). Verify: `material_cost = (weight_g / 1000) * cost_per_kg`, `machine_cost = (time_mins / 60) * hourly_rate`, `subtotal = material + machine`, `quote_price = subtotal * (1 + markup/100)`. Check: What happens with markup=0? hourly_rate=0? qty>1 multipliers? farm_size>1 division? Any floating point rounding issues in the JSON response?

- [ ] **1.2 Time parsing** — Read `time_to_minutes()` (lines 467-475) and JS `parseTimeToMins()` (search for `parseTimeToMins` in JS block). Check: Do both handle days? Seconds-only? Empty string? Do they agree on the same input? Can `parseTimeToMins` return NaN, and if so, does it propagate into cost display?

- [ ] **1.3 Preset fidelity** — Read `PRESET_KEYS` (line 689), `_load_presets()` (691), `_save_presets()` (698). Read JS `savePreset()` and `loadPreset()`. Check: Does `PRESET_KEYS` include ALL saveable fields (size_mode, support_mode, auto_orient, auto_split, scale_to_fit, time_factor)? What happens loading a preset saved before a new field was added (missing key)?

- [ ] **1.4 LocalStorage persistence** — Read JS `restoreInputs()` and `saveInputs()` (search in JS block). Check: Which fields are saved? Which are NOT saved but should be? Does restore happen before or after printers load (race condition)?

- [ ] **1.5 Cascading dropdowns** — Read JS `loadProfiles()` (line 1814) and the printer `onchange` handler. Check: When printer changes, are print_profile and filament dropdowns cleared and reloaded? Can a stale filament selection persist across printer changes?

- [ ] **1.6 Pre-flight accuracy** — Read `/api/check_size` (lines 746-846). Check: What happens when `get_mesh_bounds()` returns None? Are the three user actions (scale_fit, split, warn) correctly passed through to `/api/quote`? Does the overflow comparison use the correct axes?

- [ ] **1.7 Mesh health warnings** — Read health check logic in `/api/check_size` (lines 746-846, look for trimesh usage). Check: Are thresholds reasonable? Can healthy files trigger false warnings? What if trimesh is not installed?

- [ ] **1.8 Auto-orient** — Read `auto_orient()` (lines 242-271). Check: What happens if OrcaSlicer binary doesn't exist? Is the error caught and reported? Does the oriented file actually replace the original?

- [ ] **1.9 Auto-split** — Read `split_if_needed()` (lines 335-418). Check: What if the model fits? What if trimesh import fails? What if the cut produces an empty piece? Is recursion depth bounded?

- [ ] **1.10 Scale-to-fit** — Read `parse_size()` (lines 423-431) and how `--scale-to-fit` is used in `slice_piece()` (lines 633-662). Check: Is the 95% factor applied? Correct axis order?

- [ ] **1.11 GCode export** — Read `/api/export_gcode` (lines 1211-1236). Check: What if job_id not found? What if gcode file was deleted from /tmp? Multi-piece ZIP logic correct?

- [ ] **1.12 3MF export** — Read `/api/export_3mf` (lines 1164-1198). Check: What if `_last_job` is empty? Error handling?

- [ ] **1.13 Build volume detection** — Read `get_build_volume()` (lines 204-237). Check: `inherits` chain depth limit? Non-rectangular bed_shape parsing? Missing max_print_height?

- [ ] **1.14 File type handling** — Read file save logic in `/api/quote` (around line 872-885) and `/api/check_size`. Check: Are all 6 formats (STL, OBJ, 3MF, AMF, STEP, STP) accepted? Extension validation? Error message for unsupported?

- [ ] **1.15 Large file handling** — Check: Is there a file size limit? Upload timeout? Memory concerns with large trimesh operations?

- [ ] **Write findings** — Document each item as: OK, Bug, UX Friction, Missing Validation, or Enhancement. Include severity (High/Medium/Low), the specific code location, and a proposed fix.

---

### Task 2: Audit — Batch Mode (items 2.1–2.6)

**Files to read:**
- `app.py:1792-2911` — JS block: `fileQueue`, `queueFile()`, `removeFile()`, `clearQueue()`, `selectQueueFile()`, `processBatch()`, `getFormSettings()`, `buildFormData()`
- `app.py:1526-1791` — HTML: queue UI, batch results table, modal
- `app.py:848-1161` — `/api/quote` (how it handles single vs batch)

**Audit checklist:**

- [ ] **2.1 Per-file settings** — Read `queueFile()`, `selectQueueFile()`, `getFormSettings()`. Check: When does the queue item's settings snapshot get taken — on add or on quote? When switching queue items, does the form update to that file's settings? Can settings drift?

- [ ] **2.2 Skip-done behavior** — Read `processBatch()`. Check: Does it check `item.status === 'done'` before slicing? Is there a way to force re-quote a single done item? What resets the status?

- [ ] **2.3 Queue manipulation** — Read `removeFile()`, `clearQueue()`. Check: After removing item at index 2 of 5, does `selectedQueueIdx` update correctly? Does `clearQueue()` reset all state including results panel?

- [ ] **2.4 Batch results table** — Read batch results rendering (search for `showBatchResults` or batch table rendering). Check: Are totals summed correctly (time in minutes, not string concatenation)? Do row clicks open the correct modal with the right data?

- [ ] **2.5 Error in batch** — Read error handling in `processBatch()`. Check: If file 2 of 5 fails, does processing continue to files 3-5? Is the failed file marked with `status: 'error'`? Is the error message shown?

- [ ] **2.6 Single→Batch transition** — Read queue/UI logic. Check: With 1 file uploaded, is it single mode? Adding a 2nd file switches to batch? Does the results panel handle this transition without leftover state?

- [ ] **Write findings** — Document each item with category, severity, code location, proposed fix.

---

### Task 3: Audit — UI/UX Friction (items 3.1–3.12)

**Files to read:**
- `app.py:1241-1525` — CSS (`<style>` block)
- `app.py:1526-1791` — HTML body
- `app.py:1792-2911` — JS block 1 (all UI logic)
- `app.py:2912-2973` — JS block 2 (debug panel)

**Audit checklist:**

- [ ] **3.1 Drop zone** — Read drop zone HTML and JS event handlers (dragover, dragleave, drop). Check: Is there a visual state change on dragover? Does dropping outside the zone cause issues? What about dropping non-file content (text, URLs)?

- [ ] **3.2 Loading/progress** — Read progress polling logic and button state during operations. Check: Is the Run button disabled during slicing? Can you click it twice? Is the progress panel always visible during operations? What if polling fails?

- [ ] **3.3 Error messages** — Read all `catch` blocks and error display logic. Check: Are errors shown to the user or only logged to debug panel? Are slicer stderr messages surfaced? Is "PrusaSlicer not found" a clear message?

- [ ] **3.4 Button states** — Read Run button text logic (Generate Quote vs Quote All). Check: Does it update when queue length changes? Is it disabled when no file is loaded? Does it re-enable after completion/error?

- [ ] **3.5 Results panel transitions** — Read the right panel rendering. Check: When switching from preflight warnings to results, is the preflight panel hidden? Any flicker or double-render? Is stale content from a previous quote ever visible?

- [ ] **3.6 Copy Quote** — Read `copyQuote()` function. Check: Does copied text include all relevant fields? Is formatting clean for pasting? Does it handle multi-piece quotes? Farm mode? Is the copy button feedback clear (tooltip/flash)?

- [ ] **3.7 Modal** — Read modal open/close logic. Check: Does Escape close it? Does clicking the backdrop close it? Is body scroll prevented while modal is open? Can you open two modals?

- [ ] **3.8 Responsive layout** — Read CSS `@media` queries (around 800px breakpoint). Check: Does single-column mode hide anything important? Are inputs full-width? Does the results panel stack correctly?

- [ ] **3.9 Input validation** — Read number inputs in HTML. Check: Do they have `min`/`max`/`step` attributes? What happens with negative cost_per_kg? Zero quantity? Non-numeric text in number fields? Is there any client-side validation before submit?

- [ ] **3.10 Toggle buttons** — Read toggle CSS (`.toggle-btn`, `.toggle-btn.active`). Check: Is active state visually distinct (not just subtle border change)? Is the current selection obvious at a glance?

- [ ] **3.11 Debug panel** — Read debug panel HTML and JS (lines 2912-2973). Check: Does it overlay content or push it? Can you still interact with the main UI? Does the toggle button position interfere with other elements? Is the panel useful (timestamps, tracebacks)?

- [ ] **3.12 Preset UX** — Read preset UI HTML and JS. Check: Can you save with empty name? Duplicate name overwrites silently or warns? Is delete confirmation present? Is the dropdown clearly labeled?

- [ ] **Write findings** — Document each item with category, severity, code location, proposed fix.

---

### Task 4: Audit — State & Edge Cases (items 4.1–4.8)

**Files to read:**
- `app.py:34-66` — State dicts (`_last_job`, `_jobs`, `_progress`, `_error_log`), `_emit()`, `_log_error()`
- `app.py:848-1161` — `/api/quote` (job storage, progress tracking)
- `app.py:736-743` — Progress routes
- `app.py:1164-1236` — Export routes (depend on in-memory state)
- `app.py:87-91` — `run_slicer()`, `run_orca()` (subprocess management)
- `app.py:30-32` — Export directory setup
- `app.py:2976-2988` — Server startup
- `app.py:1792-2911` — JS: progress polling, queue state

**Audit checklist:**

- [ ] **4.1 Page refresh mid-quote** — Read progress polling JS and `/api/progress/<pid>` route. Check: If user refreshes, does the old `pid` entry leak in `_progress`? Is the slicer subprocess orphaned (no kill signal)? Does the new page load show stale progress?

- [ ] **4.2 Server restart** — Read all in-memory state. Check: After restart, `_jobs` is empty — what happens if user clicks "Download GCode" for an old job? `_last_job` is empty — what if user clicks "Export 3MF"? Are error messages clear?

- [ ] **4.3 Rapid operations** — Read button disable logic and form submission. Check: Can double-clicking the quote button fire two `/api/quote` requests? Can changing the printer dropdown during slicing corrupt the in-flight request (form reads current values vs snapshot)?

- [ ] **4.4 Empty state** — Read `init()` JS function and printer loading. Check: If PrusaSlicer has no printer profiles, what does the dropdown show? Is there guidance text? Can you still interact with the form?

- [ ] **4.5 Missing slicer binaries** — Read `run_slicer()` (line 87) and `run_orca()` (line 90). Check: If the binary path doesn't exist, is the error caught before `subprocess.run`? Is the error message helpful? Does auto-orient gracefully skip when OrcaSlicer is missing?

- [ ] **4.6 Temp file cleanup** — Read `EXPORT_DIR` setup (line 30-32) and how gcode files are written. Check: Are old files ever cleaned up? Is there a startup cleanup? What about failed slicing runs leaving partial files?

- [ ] **4.7 Memory leaks** — Read `_progress` dict usage. Check: Is it cleaned up on error paths (not just success)? Read `_jobs` — is the 50-cap enforced on every insert? Read `_error_log` — is the 100-cap enforced?

- [ ] **4.8 Concurrent tabs** — Read `_last_job` usage. Check: Two tabs quoting simultaneously — does tab B's result overwrite tab A's `_last_job`? Progress polling — can tab A see tab B's progress if they share a `pid` pattern? Are `job_id`s unique enough?

- [ ] **Write findings** — Document each item with category, severity, code location, proposed fix.

---

### Task 5: Audit — Code Quality / Reliability (items 5.1–5.5)

**Files to read:**
- `app.py:1792-2911` — All JS code (string escaping, XSS, error handling)
- `app.py:1241-1525` — CSS (for any broken variable references)
- `app.py:848-1161` — `/api/quote` (try/except coverage)
- `app.py:746-846` — `/api/check_size` (try/except coverage)
- `app.py:490-603` — Profile flags, machine limits (support mode strings)
- `app.py:147-237` — INI parsing

**Audit checklist:**

- [ ] **5.1 JS string escaping** — Search the entire JS block for Python string interpolation (`\\n` vs `\n`). Check: Are there any raw `'\n'` inside JS string literals that would break? The CLAUDE.md warns about this — find any remaining instances.

- [ ] **5.2 XSS in filenames** — Read the `esc()` JS function. Search for all places filenames are inserted into HTML (innerHTML, textContent, template literals). Check: Is `esc()` used consistently? Any `innerHTML` assignments with unescaped user input (filename, error messages)?

- [ ] **5.3 Error logging coverage** — Read all `try/except` blocks in Python routes. Check: Do they all call `_log_error()`? Are any exceptions caught and silently ignored? Are there bare `except:` clauses that swallow everything?

- [ ] **5.4 Support mode strings** — Read `_override_flags()` (lines 541-552) and how support mode is passed from JS to Python. Check: What values does the JS send? Does the Python validate them? Would an invalid value cause PrusaSlicer to fail silently or error?

- [ ] **5.5 INI parsing edge cases** — Read `_load_ini_sections()` (lines 147-163) and `_resolve_key()` (lines 179-201). Check: What happens with malformed INI files? Keys with `=` in values? UTF-8 BOM? Section names with special characters?

- [ ] **Write findings** — Document each item with category, severity, code location, proposed fix.

---

### Task 6: Merge Findings into Final Report

**Depends on:** Tasks 1-5 complete

**Files:**
- Read: `docs/superpowers/audit-findings-task-*.md` (outputs from tasks 1-5)
- Create: `docs/superpowers/2026-03-25-audit-report.md`

- [ ] **Step 1: Collect all findings** — Read the five individual findings files.

- [ ] **Step 2: Deduplicate** — Remove any items found by multiple audit tasks.

- [ ] **Step 3: Prioritize** — Sort all findings into three tiers:
  - **High** — Breaks workflow, data loss, or incorrect quotes
  - **Medium** — Annoying friction, confusing behavior, missing validation
  - **Low** — Cosmetic, minor polish, theoretical edge cases

- [ ] **Step 4: Write final report** — Format as a single markdown file with:
  - Executive summary (total counts by severity and category)
  - High-severity findings (with fix proposals)
  - Medium-severity findings (with fix proposals)
  - Low-severity findings (with fix proposals)
  - Each finding: ID, title, category, severity, code location (file:line), description, proposed fix, estimated complexity (S/M/L)

- [ ] **Step 5: Present to user** — Summarize key findings and ask which to fix first.
