#Requires AutoHotkey v2.0
#SingleInstance Force
#Include Playwright.ahk

; Smoke: run pinned Playwright tests (playwright.dev Get started) from repo root.
; Setup once: npm install && npx playwright install

try {
    code := Playwright.Test()
    if code = 0
        MsgBox "Playwright tests passed (exit 0).", "playwright-ahk", "Iconi"
    else
        MsgBox "Playwright tests failed (exit " code ").", "playwright-ahk", "Iconx"
} catch as e {
    MsgBox e.Message, "playwright-ahk — setup error", "Iconx"
}
