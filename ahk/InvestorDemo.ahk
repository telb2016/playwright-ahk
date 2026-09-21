; InvestorDemo.ahk — hotkeys for a quick Playwright demo (wrap fork only)
; Ctrl+Alt+1  Test
; Ctrl+Alt+2  Codegen https://playwright.dev
; Ctrl+Alt+3  ShowReport
#Requires AutoHotkey v2.0
#SingleInstance Force
#Include Playwright.ahk

TrayTip("InvestorDemo", "Hotkeys armed:`nCtrl+Alt+1 Test`nCtrl+Alt+2 Codegen`nCtrl+Alt+3 ShowReport", "Iconi")

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
