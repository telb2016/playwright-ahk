# playwright-ahk

AutoHotkey front-end for [Playwright](https://playwright.dev) **stable `1.63.0`** (npm + [microsoft/playwright `v1.63.0`](https://github.com/microsoft/playwright/releases/tag/v1.63.0)).

## Approach

AHK shells the same official CLI as `npx playwright …` (wrap fork). Node/`npx` stay; AHK replaces the typing/driving UX, not Playwright itself.

## Setup

```bash
npm install
npx playwright install chromium
```

## Verify the wrapper target

Run the smoke test directly through npm:

```bash
npm run test
```

Or call the same pinned local Playwright CLI that the AHK wrapper uses:

```bash
npx --no-install playwright test
```

The sample opens `https://playwright.dev` in Chromium and checks the accessible `Get started` link.

## AHK

See `ahk/` — wrappers call `npx playwright` with the pinned local install.
