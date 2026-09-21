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
(`Ctrl+Alt+1` Test · `Ctrl+Alt+2` Codegen playwright.dev · `Ctrl+Alt+3` ShowReport).

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
- Missing `copilot` / auth failures fail **loud** in the reply pane.
- Last prompt saved to `PlaywrightAhkApp.ini` next to the script.
- `Ctrl+Enter` sends; `Esc` focuses the tab control.

## Tab 2 — Playwright CLI puzzle

- Loads **`scripts/puzzle-pieces.json`** (20 pieces).
- Click a chip to append tokens (required slots prompt; empty/cancel **blocks**).
- Canvas is editable; one command per line.
- **Run** executes from **repo root**; multi-line stops on first nonzero exit.
- Empty canvas / incomplete slots (e.g. `--grep=` with no value) **block Run**.
- Helpers: Clear · Backspace (last piece) · Copy command · live terminal mirror.

Default first drop: piece flagged `defaultFirstDrop` → `test --project=chromium`.

## Layout

```text
ahk/gui/PlaywrightAhkApp.ahk   ← main entry
ahk/gui/Lib/Theme.ahk
ahk/gui/Lib/ShellExec.ahk      ← async capture jobs
ahk/gui/Lib/Json.ahk
ahk/gui/Lib/PuzzlePieces.ahk
ahk/InvestorDemo.ahk
ahk/Playwright.ahk             ← hardened wrappers (#Include)
scripts/puzzle-pieces.json     ← Tab 2 catalog (repo root)
```

## Known limitations

- GUI is Windows-native AHK; not exercised on Linux CI.
- Drag-drop onto the canvas is click-primary (chips append on click).
- Interactive Playwright UIs (`--ui`, codegen, show-report) may need a visible console for some workflows; capture mode redirects to the terminal mirror.
- Copilot multiline prompts go through a short PowerShell helper so quoting survives `cmd.exe`.
