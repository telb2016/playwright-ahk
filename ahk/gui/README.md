# Playwright AHK — Overnight GUI

Three-tab AutoHotkey **v2** front-end around the official Playwright CLI (pinned **1.63.0**).  
This does **not** rewrite Node/Playwright — it shells `npx --no-install playwright …` from the **repo root**.

## 60-second morning handoff

On a cold Windows work machine:

```bat
cd path\to\playwright-ahk
npm ci
npx playwright install chromium
```

Install / sign in **GitHub Copilot CLI** so this works in `cmd.exe`:

```bat
where copilot
copilot -p "hello" --allow-all-tools
```

Then double-click:

```text
ahk\gui\PlaywrightAhkApp.ahk
```

- **Tab 1** needs `copilot` on `PATH` (and authenticated).  
- **Tab 2** loads `scripts\puzzle-pieces.json` and defaults to:

```bat
npx --no-install playwright test --project=chromium
```

- **Tab 3** is Windows Desktop UIA only (never Playwright) — Record clicks/dblclick/rclick/drag/wheel/**hover**/typing/key-chords + **Wait** steps → `recordings\windows\`.

Optional demo hotkeys: run `ahk\InvestorDemo.ahk`  
(`Ctrl+Alt+1` Test · `Ctrl+Alt+2` Codegen · `Ctrl+Alt+3` ShowReport · `Ctrl+Alt+0` launch overnight GUI).

**Tray / focus:** `Ctrl+Alt+P` shows or hides the overnight GUI (close button hides to tray; Exit is on the tray menu).

## Prerequisites

| Tool | Why |
|------|-----|
| [AutoHotkey v2](https://www.autohotkey.com/) | `#Requires AutoHotkey v2.0` |
| Node.js **≥ 20** | engines in `package.json` |
| `npm ci` at repo root | installs pinned `@playwright/test@1.63.0` |
| `npx playwright install chromium` | browser for default project |
| `copilot` CLI on `PATH` | **Tab 1 only** |

Do **not** run GUI shells from `ahk\gui\` alone — working directory is always the repo root (folder with `package.json` + `ahk\`).

## Tab 1 — Copilot prompt studio

- Split layout: **left** Copilot prompt/reply · **right** Recording → Copilot pane.
- Dark multi-line prompt + editable response pane.
- **Send** runs asynchronously: `copilot -p "<prompt>" --allow-all-tools` (stdout+stderr streamed into the reply pane; GUI does not freeze on `RunWait`).
- **Cancel** aborts an in-flight Copilot job (process kill + timer stop).
- **Use reply as next prompt** one-click promotes the reply pane into the prompt (cycle edits).
- Missing `copilot` / auth failures fail **loud** in the reply pane (banner when login/auth strings detected).
- Last prompt saved to `PlaywrightAhkApp.ini` next to the script.
- `Ctrl+Enter` sends (Tab 1); `Esc` focuses the tab strip (or cancels an in-progress chip drag).

### Record → file → Copilot (right pane)

1. Optional **URL** (default `https://playwright.dev`).
2. **Record (headed codegen)** — prefers `npm run codegen:record -- [url]` when present (PR #5); else  
   `npx --no-install playwright codegen --target=playwright-test -o recordings/latest.spec.js [url]`.  
   Creates `recordings/` (+ archive). AHK archives prior `latest.spec.js` on the npx fallback path.  
   Waits for process **EXIT** only (no mid-session stdout poll), then loads `recordings/latest.spec.js` into the pane.
3. **Send recording to Copilot** — blocked if `latest.spec.js` missing or &lt; ~20 bytes. Builds prompt: fenced spec + seed (`keep @playwright/test + getByRole`) + your instruction last; fires the existing async Copilot Send.
4. **Save as test** — after a reply, strips markdown fences, requires `test(` + `@playwright/test` import, writes `tests/recorded-YYYYMMDD-HHmmss.spec.js`. Else toast **not a runnable test**.
5. **Run saved test** — `npx --no-install playwright test --project=chromium` on the new file (via Tab 2 canvas Run).
6. **Reload latest** / **Open recordings** — re-read `recordings/latest.spec.js` or open the folder in Explorer.

## Tab 2 — Playwright CLI puzzle

- Loads **`scripts/puzzle-pieces.json`** (20 pieces).
- **Drag** a chip onto the command canvas to append (ghost follows cursor; release over canvas to drop). **Click** still adds (fallback).
- Pieces with slots open a **dark Slot editor** dialog (not `InputBox`); cancel / empty required slots block the drop.
- Canvas is editable; one command per line.
- **Run** executes from **repo root**; multi-line stops on first nonzero exit.
- **Cancel run** aborts the in-flight puzzle job.
- Empty canvas / incomplete slots (e.g. `--grep=` with no value) **block Run**.
- Helpers: Clear · Default · Backspace · Copy command · Save · Copy/Clear terminal · Open repo folder.
- Piece **Filter** box hides non-matching chips (status debounced while typing).
- `F5` Run · `Delete` Backspace · `Ctrl+S` save · `Ctrl+1`/`Ctrl+2`/`Ctrl+3` tabs · `Ctrl+Shift+C` copy cmd · `Ctrl+Shift+T` copy terminal · autosave 60s.

Default first drop: piece flagged `defaultFirstDrop` → `test --project=chromium` (skipped when a saved canvas is restored from ini).

## Tab 3 — Windows desktop UIA (NOT Playwright)

Bulletproof **AutoHotkey + UI Automation** recorder for the Windows machine itself.

- **Record** — clicks, **double-clicks**, **right-clicks**, **drags**, **mouse wheel**, **hover** (dwell), typed text, and **keyboard chords / hotkeys** via `IUIAutomation` (`UiaCore.ahk`) + AHK v2 `InputHook` / `~WheelUp|Down` hotkeys. Each pointer/type/key step stores a **ranked target list**:
  1. `AutomationId`
  2. `Name` + `ControlType`
  3. `LocalizedControlType` + index among siblings
  Soft **window-relative** click is rank 99 last-resort only (never primary verifier).
- **Double-click** — `action: "dblclick"`. Left-button edges are deferred for `GetDoubleClickTime()` (same position slop) so a true dblclick is **one** step, not two clicks. Playback: `UiaCore.InvokeDoubleClick` (clickable point / bounds ×2).
- **Drag** — `action: "drag"`. LButton press → move past ~**10px** (`DragThresholdPx`) before release becomes **one** drag step (not click/dblclick). Cancels the pending-click timer; captures start `targets`/`window`/`screen` (+ optional Strict spots at start only) and end `endTargets`/`endWindow`/`endScreen`. Flushes pending type/wheel; skipped while this GUI is focused. Never emits a left-click for a completed drag. Playback: hard-fail start window → resolve start via ranked targets → end via `endTargets` else soft `endScreen`/relative → `UiaCore.InvokeDrag` / `SoftDragRelative`.
- **Mouse wheel** — `action: "wheel"` with signed `notches` (+up / −down) and `delta` (= notches × 120). Rapid same-direction notches within ~**180ms** coalesce into one JSON step (keeps recordings sane). Window/target captured under cursor on the first notch of a batch. Playback: activate hard-keys → move to target when resolved → `WheelUp`/`WheelDown`.
- **Right-click** — `action: "rclick"`. Right-button down edge (same ~**180ms** debounce as left-click); flushes pending type/click/wheel first; ranked UIA targets + window hard-keys under cursor. Skipped while this GUI is focused. Never emits a left-click for the right button. Playback: same hard gate → ranked UIA → optional Strict spots; `UiaCore.InvokeRightClick` (clickable point / bounds) or soft relative with Right. Legacy `action:"rightclick"` still plays.
- **Hover** — `action: "hover"`. While Record is active, pointer stays within ~**6px** (`HoverSlopPx`) with **no** LButton/RButton down for ~**700ms** (`HoverDwellMs`) and the UIA target under cursor stays stable → **one** hover step (ranked targets + window hard-keys + screen; optional Strict spots like click). After a hover, pointer must **leave the target** or move beyond slop before another can fire. Ignored while pending click/drag/type/wheel flush is active; skipped while this GUI is focused; flushes pending type before commit. Button down or significant move cancels the dwell (does not steal click/dblclick/drag). Playback: hard-gate window → ranked UIA → `UiaCore.InvokeHover` (`MoveToElement` + settle, no click) or soft `SoftMoveRelative`; Strict spots when present. ListBox: `hover …`.
- **Typing** — `action: "type"` steps with a `text` field. Batched ~**500ms** after last key (idle debounce); pure modifiers ignored; **Enter** commits early (appends `\n`). Focused-element ranked targets attached when UIA can describe them. Typing while this GUI is focused is skipped. Ordinary printable text stays `type` (not `key`).
- **Key / chord** — `action: "key"` with a `keys` string in AHK **Send**-friendly form (e.g. `^s`, `{F5}`, `!{F4}`, `^{Left}`). While recording, **Ctrl/Alt/Win** + key, or standalone function/nav keys (F1–F12, arrows, Home/End/PgUp/PgDn, Insert/Delete, Apps/Menu), flush any pending type batch and emit one key step (ranked targets from focused element when available; optional Strict spots on the active window). **Identical consecutive** `keys` within ~**200ms** (`KeyRepeatDebounceMs`) are **debounced** so arrow/F-key auto-repeat does not flood the step list; distinct rapid chords (e.g. Ctrl+S then Ctrl+V) still record as separate steps. **Esc** still **StopRecord** — never recorded as a key step. Skipped while this GUI is focused. Playback: hard-gate window → **SetFocus** when resolved → `Send("{Blind}" keys)` → Strict spots verify when present. ListBox: `key ^s` / `key {F5}`.
- **Wait** — `action: "wait"` with `ms` (default **1000**, clamped **0–60000**). Inserted via Tab3 **Wait** button (InputBox for ms; inserts **after** the selected ListBox step, or **appends** if none selected) — not captured by a record hotkey (avoids Esc/chord fights). Play/Verify: `Sleep(ms)` only — **no** window hard gate, **no** Strict spots; ListBox still highlights the step. ListBox: `wait 1000ms`.
- **Play / Verify** — order: (1) window/process class hard gate → (2) ranked UIA targets → (3) optional **Strict fullscreen spots** (skipped for `wait`). For `type`: focus + **SetValue** when possible, else `SendText`. For `key`: focus then `Send("{Blind}" …)`. For `drag`: start→end as above. For `hover`: move-only (no click). For `wait`: `Sleep(ms)`. ListBox **highlights the current step** as Play/Verify runs; **failing step stays selected** on hard-fail.
- **Step list editor** — ListBox (index · action · short target, including `dblclick` / `rclick` / `hover …` / `drag …→…` / `wheelUp|Down xN` / `key ^s` / `wait Nms`); **Delete** / **Up** / **Down** / **Wait**; **Clear all** confirms. Stays synced with Steps JSON + ini.
- **Strict fullscreen spots** (Tab 3 toggle, default ON) — 9 client-area samples as **% of client W/H** (never taskbar/clock/tray). Settle wait ~200ms (spots unchanged) before hash. Playback allows ±Δ RGB + partial pass (~2/3). Snapshot **display profile** (resolution, DPI/scale, monitor count) — hard-fail early if changed. Pixel identity for *controls* remains last-resort soft only. Unchanged for type/key steps.
- **Save** — `recordings/windows/desktop-*.json` (+ `.ahk` stub). Gitignored payloads; folder kept.
- **Send desktop → Copilot** — seeds *AutoHotkey + UI Automation* — **never** `@playwright/test`. Separate from Tab 1 browser Record pane.
- **Boundary** — Tab 3 never pipes into `npx playwright` / codegen / Save as test (Save as test explicitly refuses `windows-uia` / AHK UIA seed text).

Controls: **Record · Stop · Play · Verify · Save · Folder · Load · Clear all · Probe · Strict spots · step Delete/Up/Down/Wait · Send desktop → Copilot**. Hotkeys `Ctrl+3`, `Ctrl+Shift+J` copy JSON.

## UX polish

- **Text-train tab transition** — custom tab strip (not raw Tab3 blink); sliding train wipe banner when swapping Copilot ↔ puzzle.
- **Rounded chrome** — `Theme.ApplyRoundedRegion` + dark title bar on create/resize.
- **True chip→canvas drag-drop** — `ChipDrag.ahk` (WM_LBUTTONDOWN + threshold + ghost); click-to-add retained.
- **Dark slot editor** — `SlotEditor.ahk` modal for grep/url/file/out slots.
- **Tray + Ctrl+Alt+P** — hide to tray on close; global hotkey toggles show/focus; tray Save / Cancel busy / Exit; icon tip shows busy state.
- **Ini persistence** — prompt, canvas, last terminal snippet, active tab (`1`/`2`/`3`), window size/pos, slot memory, last saved recorded test, Desktop StepsJson/Instruction/StrictSpots.
- Loud Copilot auth banner when output looks unauthenticated.

## Layout

```text
ahk/gui/PlaywrightAhkApp.ahk   ← main entry
ahk/gui/Lib/Theme.ahk
ahk/gui/Lib/ShellExec.ahk      ← async capture jobs + Cancel
ahk/gui/Lib/Json.ahk
ahk/gui/Lib/PuzzlePieces.ahk
ahk/gui/Lib/SlotEditor.ahk     ← dark slot dialog
ahk/gui/Lib/ChipDrag.ahk       ← chip→canvas DnD
ahk/gui/Lib/RecordSession.ahk  ← headed codegen → latest.spec.js → Copilot
ahk/gui/Lib/UiaCore.ahk         ← IUIAutomation helpers (Tab 3)
ahk/gui/Lib/DesktopRecord.ahk   ← Windows desktop UIA record/play/verify
ahk/gui/Lib/ScreenSpots.ahk     ← Strict fullscreen client-% spot verifier
ahk/InvestorDemo.ahk
ahk/Playwright.ahk             ← hardened wrappers (#Include)
scripts/puzzle-pieces.json     ← Tab 2 catalog (repo root)
```

## CHANGELOG (overnight polish)

### PR #6 — `ahk/overnight-polish-2`
- **Tab 3 — hover dwell** — `action:"hover"` when pointer dwells ~700ms within 6px with no buttons and stable UIA target; leave-target debounce; `UiaCore.InvokeHover` / `SoftMoveRelative` play (no click); ListBox `hover …`.
- **Tab 3 — wait steps** — `action:"wait"` + `ms` (default 1000, clamp 0–60000); Tab3 **Wait** button inserts after selection (or appends) via InputBox; Play/Verify `Sleep(ms)` with no window gate / no Strict spots; ListBox `wait Nms`.
- **Tab 3 — key auto-repeat debounce** — identical consecutive `action:"key"` within ~200ms (`KeyRepeatDebounceMs`) coalesce to one step while recording; distinct rapid chords stay separate.
- **Tab 3 — key / chord** — `action:"key"` + `keys` (AHK Send form: `^s`, `{F5}`, `!{F4}`); Ctrl/Alt/Win chords and F/nav/special keys; flush pending type first; Esc still StopRecord; play via SetFocus + `Send("{Blind}" …)`; ListBox `key …`. Ordinary typing remains `action:"type"`.
- **Tab 3 — drag** — `action:"drag"` when LButton moves past ~10px before release; cancels pending click (no left-click emit); start+end UIA targets/`endScreen`; play via `UiaCore.InvokeDrag` / `SoftDragRelative`; ListBox shows `drag … → …`.
- **Tab 3 — rclick (right-click)** — `action:"rclick"` on RButton down edge (~180ms debounce); flush pending type/click/wheel; skip when host GUI focused; play/verify via `UiaCore.InvokeRightClick` / soft relative Right; ListBox shows `rclick …` (legacy `rightclick` still plays).
- **Tab 3 — dblclick + mouse wheel** — `action:"dblclick"` via `GetDoubleClickTime` pending-click coalesce; `action:"wheel"` with notches/delta + ~180ms same-direction batch; UiaCore double-click / Wheel helpers; ListBox summaries updated.
- **Tab 3 — Play/Verify ListBox highlight** — selects current step index while running; leaves failing step selected on hard-fail.
- **Tab 3 — keyboard typing capture** — `InputHook` batches into `action:"type"` + `text`; ~500ms idle / Enter commit; ranked UIA from focused element; playback SetValue→SendText.
- **Tab 3 — step list editor** — ListBox synced with JSON/ini; Delete / Up / Down / Wait / Clear all (confirm).
- **Tab 3 — Windows Desktop UIA** — Record/Stop/Play/Verify/Save; ranked targets; hard-fail wrong process/class; Copilot seed is AHK+UIA never Playwright; saves under `recordings/windows/`.
- **Tab2 visibility fix** — Default / Copy term / Clear term / Open repo / Filter label hidden on Tab 1.
- **ChipDrag harden** — cancel on focus loss / tab wipe / tray hide; tooltip debounce; longer click suppress for SlotEditor; ghost label truncate; `SetOwner`.
- **SlotEditor** — remember last OK values (session + `SlotMemory` ini); center on owner; light URL validation.
- **Tray** — Save now · Cancel busy jobs; dynamic icon tip (Copilot/Puzzle/Record busy).
- **Window clamp** — restore X/Y onto virtual screen if off-monitor.
- **Hotkeys** — `Ctrl+1` / `Ctrl+2` tab jump.
- **Record helpers** — Reload latest · Open recordings; persist `LastSavedSpec` for Run saved test across restarts.
- Chip filter status debounced.
- Status bar OK/err tone; canvas flash on drop/block; terminal auto-scroll during puzzle run.
- Record **Cancel** button; filter **Clear** (`Ctrl+L`); reload latest (`Ctrl+R`).
- Tray Exit confirms when jobs busy; block Send/Run during train wipe.
- Chip hover tooltips + right-click copies argv; click status bar to copy message.
- Stronger incomplete-slot heuristics (`--grep=""`, screenshot/pdf missing out).
- Minimize→tray; Ctrl+Z canvas undo; filter “No matching pieces”; tray Help + Edit latest.spec.js.
- Copy spec button; F6/F7 focus filter/canvas; chips disabled while puzzle runs; drag focus-loss grace.
- Strip UTF-8 BOM when reading latest.spec.js; HideToTray re-entry guard.

### PR #4 — `ahk/overnight-polish` (merged)
- **Chip→canvas drag-drop** — drag chips onto the canvas (ghost + drop target); click-to-add kept as fallback; Esc cancels drag; canvas highlights while hovered.
- **Dark Slot editor** — replaces `InputBox` for pieces with slots (grep, url, file, out); Browse… for file/out.
- **Tray + Ctrl+Alt+P** — close hides to tray; hotkey toggles show/focus; tray menu Exit / tab jump.
- **Ini persistence** — canvas + last terminal snippet (+ prompt, active tab, window size + position).
- **Run elapsed** — status bar shows live seconds while Copilot / puzzle jobs run.
- **InvestorDemo** — `Ctrl+Alt+0` launches overnight GUI.
- Save / Default canvas; dark confirms; Ctrl+S + 60s autosave; chip filter (persisted); copy terminal; open repo folder; tray tips on job finish.
- **Record → Copilot** — headed codegen to `recordings/latest.spec.js`, send to Copilot, Save as test + Run saved test.

### Earlier (PR #3 — merged)
- **Train wipe** — custom tabs + animated train banner on Tab1↔Tab2 (no raw Tab3 blink).
- **Use reply as next prompt** — one-click promote reply → prompt for Copilot cycle.
- **ApplyRoundedRegion** — wired on create/resize (SetWindowRgn); dark title bar retained.
- **Cancel running job** — Cancel (Copilot) + Cancel run (puzzle) kill PID and stop poll timers.
- Louder Copilot auth / login-required banner in reply pane.
- Hotkeys: Ctrl+Enter Send (Tab1), F5 Run (Tab2), Delete Backspace piece (Tab2).

## Ini keys (`PlaywrightAhkApp.ini` next to the script)

| Section | Key | Purpose |
|---------|-----|---------|
| Copilot | LastPrompt | Tab 1 prompt (`\n` escaped) |
| Copilot | LastReply | Tab 1 reply (capped ~48k) |
| Puzzle | Canvas | Command canvas text |
| Puzzle | LastTerminal | Last terminal mirror (capped ~48k) |
| Puzzle | ChipFilter | Piece filter substring |
| UI | ActiveTab | `1`, `2`, or `3` |
| UI | Width / Height / X / Y | Window geometry |
| Record | Url / Instruction | Codegen start URL + Copilot instruction |
| Record | LastSavedSpec | Absolute path of last Save as test (enables Run) |
| SlotMemory | `<label>_<slot>` | Last OK slot editor values (grep/url/file/out) |
| Desktop | Instruction / StepsJson / StrictSpots | Tab 3 instruction, steps JSON, spots toggle |

## Known limitations

- GUI is Windows-native AHK; not exercised on Linux CI.
- Tab 3 requires Windows UI Automation COM (`UIAutomationCore`); clicks are edge-polled with a `GetDoubleClickTime` pending window for dblclick; LButton move past ~10px before release records `action:"drag"` (not click); right-click uses RButton edge + ~180ms debounce (`action:"rclick"`); wheel uses `~WheelUp`/`~WheelDown` (batched ~180ms same-direction); typing uses visible `InputHook` batches into `action:"type"`; modifier chords and F/nav keys become discrete `action:"key"` Send strings (identical auto-repeats within ~200ms are debounced; Esc stops record and is never a key step); Tab3 **Wait** inserts `action:"wait"` timing steps (Play/Verify Sleep, no window gate); pointer dwell ~700ms within 6px (no buttons, stable UIA target) records `action:"hover"` (leave-target debounce; play is move-only).
- Drag-drop uses mouse capture polling (not OLE `IDropTarget`); drop target is the canvas Edit HWND; drag cancels if the app loses focus.
- Interactive Playwright UIs (`--ui`, codegen, show-report) may need a visible console for some workflows; capture mode redirects to the terminal mirror.
- Copilot multiline prompts go through a short PowerShell helper so quoting survives `cmd.exe`.
- Terminal ini snapshot is capped (~48k chars) to keep the ini modest.
