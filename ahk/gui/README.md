# Playwright AHK — Overnight GUI

Two-tab AutoHotkey **v2** front-end around the official Playwright CLI (pinned **1.63.0**).  
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
- `F5` Run · `Delete` Backspace · `Ctrl+S` save · `Ctrl+1`/`Ctrl+2` tabs · `Ctrl+Shift+C` copy cmd · `Ctrl+Shift+T` copy terminal · autosave 60s.

Default first drop: piece flagged `defaultFirstDrop` → `test --project=chromium` (skipped when a saved canvas is restored from ini).

## UX polish

- **Text-train tab transition** — custom tab strip (not raw Tab3 blink); sliding train wipe banner when swapping Copilot ↔ puzzle.
- **Rounded chrome** — `Theme.ApplyRoundedRegion` + dark title bar on create/resize.
- **True chip→canvas drag-drop** — `ChipDrag.ahk` (WM_LBUTTONDOWN + threshold + ghost); click-to-add retained.
- **Dark slot editor** — `SlotEditor.ahk` modal for grep/url/file/out slots.
- **Tray + Ctrl+Alt+P** — hide to tray on close; global hotkey toggles show/focus; tray Save / Cancel busy / Exit; icon tip shows busy state.
- **Ini persistence** — prompt, canvas, last terminal snippet, active tab, window size/pos, slot memory, last saved recorded test.
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
ahk/InvestorDemo.ahk
ahk/Playwright.ahk             ← hardened wrappers (#Include)
scripts/puzzle-pieces.json     ← Tab 2 catalog (repo root)
```

## CHANGELOG (overnight polish)

### PR #6 — `ahk/overnight-polish-2`
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
| UI | ActiveTab | `1` or `2` |
| UI | Width / Height / X / Y | Window geometry |
| Record | Url / Instruction | Codegen start URL + Copilot instruction |
| Record | LastSavedSpec | Absolute path of last Save as test (enables Run) |
| SlotMemory | `<label>_<slot>` | Last OK slot editor values (grep/url/file/out) |

## Known limitations

- GUI is Windows-native AHK; not exercised on Linux CI.
- Drag-drop uses mouse capture polling (not OLE `IDropTarget`); drop target is the canvas Edit HWND; drag cancels if the app loses focus.
- Interactive Playwright UIs (`--ui`, codegen, show-report) may need a visible console for some workflows; capture mode redirects to the terminal mirror.
- Copilot multiline prompts go through a short PowerShell helper so quoting survives `cmd.exe`.
- Terminal ini snapshot is capped (~48k chars) to keep the ini modest.
