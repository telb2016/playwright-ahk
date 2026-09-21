; InvestorDemo.ahk — hotkeys for a quick Playwright demo (wrap fork only)
; Ctrl+Alt+1  Test
; Ctrl+Alt+2  Codegen https://playwright.dev
; Ctrl+Alt+3  ShowReport
; Ctrl+Alt+0  Launch overnight GUI (PlaywrightAhkApp.ahk)
; Note: Ctrl+Alt+P is reserved by the overnight GUI (show/focus / tray toggle).
#Requires AutoHotkey v2.0
#SingleInstance Force
#Include Playwright.ahk

A_IconTip := "InvestorDemo — Playwright wrap fork"
TrayTip("InvestorDemo", "Hotkeys armed:`nCtrl+Alt+1 Test`nCtrl+Alt+2 Codegen`nCtrl+Alt+3 ShowReport`nCtrl+Alt+0 Overnight GUI`n(Ctrl+Alt+P = GUI tray focus)", "Iconi")

^!1:: {
    try {
        SetWorkingDir(Playwright.RepoRoot)
        code := Playwright.Test()
        TrayTip("Playwright.Test", "Exit code " code "  (cwd " Playwright.RepoRoot ")", code = 0 ? "Iconi" : "Iconx")
    } catch as e {
        MsgBox(e.Message, "InvestorDemo — Test failed", "Iconx")
    }
}

^!2:: {
    try {
        SetWorkingDir(Playwright.RepoRoot)
        code := Playwright.Codegen("https://playwright.dev")
        TrayTip("Playwright.Codegen", "Exit code " code, "Iconi")
    } catch as e {
        MsgBox(e.Message, "InvestorDemo — Codegen failed", "Iconx")
    }
}

^!3:: {
    try {
        SetWorkingDir(Playwright.RepoRoot)
        code := Playwright.ShowReport()
        TrayTip("Playwright.ShowReport", "Exit code " code, "Iconi")
    } catch as e {
        MsgBox(e.Message, "InvestorDemo — ShowReport failed", "Iconx")
    }
}

^!0:: {
    guiScript := A_ScriptDir "\gui\PlaywrightAhkApp.ahk"
    if !FileExist(guiScript) {
        MsgBox("Missing: " guiScript, "InvestorDemo — GUI launch", "Iconx")
        return
    }
    ; SingleInstance on the GUI script will focus existing instance
    Run('"' A_AhkPath '" "' guiScript '"')
    TrayTip("Overnight GUI", "Launched PlaywrightAhkApp`nCtrl+Alt+P show/focus · close hides to tray", "Iconi")
}
