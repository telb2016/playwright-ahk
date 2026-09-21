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

- Dark multi-line prompt + editable response pane.
- **Send** runs asynchronously: `copilot -p "<prompt>" --allow-all-tools` (stdout+stderr streamed into the reply pane; GUI does not freeze on `RunWait`).
- **Cancel** aborts an in-flight Copilot job (process kill + timer stop).
- **Use reply as next prompt** one-click promotes the reply pane into the prompt (cycle edits).
- Missing `copilot` / auth failures fail **loud** in the reply pane (banner when login/auth strings detected).
- Last prompt saved to `PlaywrightAhkApp.ini` next to the script.
- `Ctrl+Enter` sends (Tab 1); `Esc` focuses the tab strip (or cancels an in-progress chip drag).

## Tab 2 — Playwright CLI puzzle

- Loads **`scripts/puzzle-pieces.json`** (20 pieces).
- **Drag** a chip onto the command canvas to append (ghost follows cursor; release over canvas to drop). **Click** still adds (fallback).
- Pieces with slots open a **dark Slot editor** dialog (not `InputBox`); cancel / empty required slots block the drop.
- Canvas is editable; one command per line.
- **Run** executes from **repo root**; multi-line stops on first nonzero exit.
- **Cancel run** aborts the in-flight puzzle job.
- Empty canvas / incomplete slots (e.g. `--grep=` with no value) **block Run**.
- Helpers: Clear · Default · Backspace · Copy command · Save · Copy terminal · Open repo folder.
- Piece **Filter** box hides non-matching chips.
- `F5` Run · `Delete` Backspace · `Ctrl+S` save all · autosave every 60s.

Default first drop: piece flagged `defaultFirstDrop` → `test --project=chromium` (skipped when a saved canvas is restored from ini).

## UX polish

- **Text-train tab transition** — custom tab strip (not raw Tab3 blink); sliding train wipe banner when swapping Copilot ↔ puzzle.
- **Rounded chrome** — `Theme.ApplyRoundedRegion` + dark title bar on create/resize.
- **True chip→canvas drag-drop** — `ChipDrag.ahk` (WM_LBUTTONDOWN + threshold + ghost); click-to-add retained.
- **Dark slot editor** — `SlotEditor.ahk` modal for grep/url/file/out slots.
- **Tray + Ctrl+Alt+P** — hide to tray on close; global hotkey toggles show/focus; tray Exit quits.
- **Ini persistence** — prompt, canvas, last terminal snippet, active tab, window size in `PlaywrightAhkApp.ini`.
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
ahk/InvestorDemo.ahk
ahk/Playwright.ahk             ← hardened wrappers (#Include)
scripts/puzzle-pieces.json     ← Tab 2 catalog (repo root)
```

## CHANGELOG (overnight polish)

### PR #4 — `ahk/overnight-polish`
- **Chip→canvas drag-drop** — drag chips onto the canvas (ghost + drop target); click-to-add kept as fallback; Esc cancels drag; canvas highlights while hovered.
- **Dark Slot editor** — replaces `InputBox` for pieces with slots (grep, url, file, out); Browse… for file/out.
- **Tray + Ctrl+Alt+P** — close hides to tray; hotkey toggles show/focus; tray menu Exit / tab jump.
- **Ini persistence** — canvas + last terminal snippet (+ prompt, active tab, window size + position).
- **Run elapsed** — status bar shows live seconds while Copilot / puzzle jobs run.
- **InvestorDemo** — `Ctrl+Alt+0` launches overnight GUI.
- Save / Default canvas; dark confirms; Ctrl+S + 60s autosave; chip filter (persisted); copy terminal; open repo folder; tray tips on job finish.

### Earlier (PR #3 — merged)
- **Train wipe** — custom tabs + animated train banner on Tab1↔Tab2 (no raw Tab3 blink).
- **Use reply as next prompt** — one-click promote reply → prompt for Copilot cycle.
- **ApplyRoundedRegion** — wired on create/resize (SetWindowRgn); dark title bar retained.
- **Cancel running job** — Cancel (Copilot) + Cancel run (puzzle) kill PID and stop poll timers.
- Louder Copilot auth / login-required banner in reply pane.
- Hotkeys: Ctrl+Enter Send (Tab1), F5 Run (Tab2), Delete Backspace piece (Tab2).

## Known limitations

- GUI is Windows-native AHK; not exercised on Linux CI.
- Drag-drop uses mouse capture polling (not OLE `IDropTarget`); drop target is the canvas Edit HWND.
- Interactive Playwright UIs (`--ui`, codegen, show-report) may need a visible console for some workflows; capture mode redirects to the terminal mirror.
- Copilot multiline prompts go through a short PowerShell helper so quoting survives `cmd.exe`.
- Terminal ini snapshot is capped (~48k chars) to keep the ini modest.
