# AHK wrappers (Playwright wrap fork)

Thin AutoHotkey **v2** helpers that shell the official Playwright CLI pinned in the repo root (`@playwright/test@1.63.0`). This does **not** replace Playwright with UI automation.

## One-time setup (repo root)

```bat
npm install
npx playwright install
```

## Usage

```ahk
#Include Playwright.ahk

Playwright.Test()                          ; npm run test / npx playwright test
Playwright.Codegen("https://playwright.dev")
Playwright.Install()                       ; install browsers
Playwright.ShowReport()
Playwright.ShowTrace("trace.zip")
```

Or run `RunTests.ahk` next to this file.

All commands execute with working directory = **repo root** (parent of `ahk\`), using `npx --no-install` so you hit the pinned local install, not a global Playwright.

## Exit codes

Helpers return the process exit code (`0` = success). Missing Node / `npm install` / repo layout throw a clear `Error` instead of failing silently.

## Platform

Native **Windows** + Node >= 18. Wine is not part of this happy path.
