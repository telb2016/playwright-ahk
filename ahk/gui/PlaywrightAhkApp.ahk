; PlaywrightAhkApp.ahk — overnight AutoHotkey v2 GUI (Copilot studio + Playwright CLI puzzle)
; Double-click to run. Working directory for all Playwright runs = repo root (never ahk\gui alone).
#Requires AutoHotkey v2.0
#SingleInstance Force
#Warn
Persistent

#Include Lib\Theme.ahk
#Include Lib\ShellExec.ahk
#Include Lib\Json.ahk
#Include Lib\PuzzlePieces.ahk
#Include Lib\SlotEditor.ahk
#Include Lib\ChipDrag.ahk
#Include Lib\RecordSession.ahk
#Include Lib\DesktopRecord.ahk
#Include ..\Playwright.ahk

global AppGui, StatusBar
global RepoRoot
global EdPrompt, EdReply, BtnSend, BtnCancelCopilot, BtnUseReply
global EdRecording, EdRecordUrl, EdRecordInstr, BtnRecord, BtnSendRecording
global BtnSaveAsTest, BtnRunSavedTest, LblRecording
global BtnReloadLatest, BtnCopyRec, BtnOpenRec, BtnCancelRecord
global RecordJob, BusyRecord, LastSavedSpec
global EdCanvas, EdTerminal, BtnRun, BtnCancelPuzzle
global Catalog, Canvas
global CopilotJob, PuzzleJob
global IniPath
global BusyCopilot, BusyPuzzle
global ActiveTab, BtnTab1, BtnTab2, BtnTab3
global Tab1Ctrls, Tab2Ctrls, Tab3Ctrls
global WipeGui, WipeLbl, WipeActive, WipeDir, WipeStep, WipeTarget
global LastWinW, LastWinH, LastWinX, LastWinY
global AppVisible, HidingToTray
global ChipBtns, EdChipFilter, LblNoChipMatch
global JobStartCopilot, JobStartPuzzle

global Desktop, EdDesktopJson, EdDesktopLog, EdDesktopInstr, ChkStrictSpots, LbDesktopSteps, BtnStepDel, BtnStepUp, BtnStepDown, BtnStepDup, BtnStepWait
global BtnDeskRecord, BtnDeskStop, BtnDeskPlay, BtnDeskVerify, BtnDeskSave, BtnDeskSend, BtnDeskClear
global BusyDesktop

CopilotJob := ""
PuzzleJob := ""
BusyCopilot := false
BusyPuzzle := false
ActiveTab := 1
Tab1Ctrls := []
Tab2Ctrls := []
Tab3Ctrls := []
WipeActive := false
WipeDir := 1
WipeStep := 0
WipeTarget := 1
LastWinW := 1180
LastWinH := 720
LastWinX := ""
LastWinY := ""
AppVisible := true
HidingToTray := false
ChipBtns := []
JobStartCopilot := 0
JobStartPuzzle := 0
RecordJob := ""
BusyRecord := false
LastSavedSpec := ""
BusyDesktop := false
Desktop := ""

RepoRoot := ShellExec.ResolveRepoRoot(A_ScriptFullPath)
try RecordSession.EnsureDirs(RepoRoot)
IniPath := A_ScriptDir "\PlaywrightAhkApp.ini"
Catalog := PuzzlePieces.Load(RepoRoot)
Canvas := PuzzleCanvas(Catalog)
Desktop := DesktopRecord(RepoRoot)

SetupTray()
BuildGui()
Theme.ApplyDarkTitleBar(AppGui.Hwnd)
ChipDrag.SetOwner(AppGui.Hwnd)

Desktop.onStatus := DesktopStatusCb
Desktop.onStep := OnDesktopStepCaptured
Desktop.onPlayIndex := OnDesktopPlayIndex
try Desktop.ignoreHwnd := AppGui.Hwnd
SlotEditor.SetIniPath(IniPath)
LoadIniAll()
if Trim(EdCanvas.Value) = "" {
    Canvas.SeedDefault()
    RefreshCanvasEdit()
}
ShowTab(ActiveTab, true)
try OnChipFilterChange()
SetStatus("Ready — repo root: " RepoRoot)
ClampWindowPos()
showOpts := "w" LastWinW " h" LastWinH
if LastWinX != "" && LastWinY != ""
    showOpts .= " x" LastWinX " y" LastWinY
AppGui.Show(showOpts)
ApplyChrome(LastWinW, LastWinH)
UpdateTrayTip()
; Global show/focus hotkey
Hotkey("^!p", ToggleShowFocus)
return

SetupTray() {
    A_IconTip := "Playwright AHK — Overnight GUI · Ctrl+Alt+P"
    try TraySetIcon(A_AhkPath, 1)
    A_TrayMenu.Delete()
    A_TrayMenu.Add("&Show / Focus`tCtrl+Alt+P", (*) => ToggleShowFocus())
    A_TrayMenu.Add()
    A_TrayMenu.Add("Copilot studio`tCtrl+1", (*) => (ShowAndFocus(), RequestTab(1)))
    A_TrayMenu.Add("CLI puzzle`tCtrl+2", (*) => (ShowAndFocus(), RequestTab(2)))
    A_TrayMenu.Add("Desktop UIA`tCtrl+3", (*) => (ShowAndFocus(), RequestTab(3)))
    A_TrayMenu.Add()
    A_TrayMenu.Add("Save now`tCtrl+S", (*) => (SaveIniAll(), TrayTip("Saved", "Prompt/canvas/terminal persisted", "Iconi")))
    A_TrayMenu.Add("Cancel busy jobs", OnTrayCancelJobs)
    A_TrayMenu.Add()
    A_TrayMenu.Add("Open recordings folder", (*) => (ShowAndFocus(), OnOpenRecordingsFolder()))
    A_TrayMenu.Add("Edit latest.spec.js", (*) => OnEditLatestSpec())
    A_TrayMenu.Add("Load latest desktop UIA JSON", (*) => (ShowAndFocus(), RequestTab(3), OnDesktopLoadLatest()))
    A_TrayMenu.Add("Open repo folder", (*) => (ShowAndFocus(), OnOpenRepoFolder()))
    A_TrayMenu.Add("&Hotkeys / help", OnTrayHelp)
    A_TrayMenu.Add()
    A_TrayMenu.Add("E&xit", OnTrayExit)
    A_TrayMenu.Default := "&Show / Focus`tCtrl+Alt+P"
    A_TrayMenu.ClickCount := 1
}

OnTrayHelp(*) {
    global AppGui
    msg := "Ctrl+Alt+P tray · Ctrl+1/2/3 tabs · Ctrl+Enter Send · F5 puzzle Run`n"
        . "Ctrl+S save · Ctrl+Z undo canvas · Ctrl+L clear filter · Ctrl+R reload latest`n"
        . "Ctrl+Shift+C/T copy cmd/terminal · Ctrl+Shift+J copy desktop JSON · Esc cancel`n"
        . "Tab3 = Windows Desktop UIA + Strict spots (NOT Playwright). Close/minimize → tray."
    ; One-button dark info
    Theme.InfoDark(msg, "Hotkeys / help", AppGui.Hwnd)
}

OnTrayCancelJobs(*) {
    global BusyCopilot, BusyPuzzle, BusyRecord, BusyDesktop
    any := BusyCopilot || BusyPuzzle || BusyRecord || BusyDesktop
    OnCopilotCancel()
    OnPuzzleCancel()
    OnRecordCancel()
    try OnDesktopStop()
    UpdateTrayTip()
    TrayTip("Playwright AHK", any ? "Busy jobs cancelled" : "No busy jobs", "Iconi")
}

UpdateTrayTip() {
    global BusyCopilot, BusyPuzzle, BusyRecord, BusyDesktop, AppVisible
    bits := []
    if BusyCopilot
        bits.Push("Copilot…")
    if BusyPuzzle
        bits.Push("Puzzle…")
    if BusyRecord
        bits.Push("BrowserRec…")
    if BusyDesktop
        bits.Push("DesktopUIA…")
    base := "Playwright AHK — Overnight GUI · Ctrl+Alt+P"
    if bits.Length
        A_IconTip := base "`nBusy: " StrJoin(bits, " · ")
    else
        A_IconTip := base (AppVisible ? "" : "`n(hidden in tray)")
}

StrJoin(arr, sep) {
    out := ""
    for i, v in arr
        out .= (i > 1 ? sep : "") v
    return out
}

OnTrayExit(*) {
    global BusyCopilot, BusyPuzzle, BusyRecord, AppGui
    if BusyCopilot || BusyPuzzle || BusyRecord {
        if !Theme.ConfirmDark("Jobs are still running. Exit anyway?", "Exit Playwright AHK", AppGui.Hwnd)
            return
    }
    SaveIniAll()
    OnCopilotCancel()
    OnPuzzleCancel()
    OnRecordCancel()
    try OnDesktopStop()
    ExitApp()
}

ToggleShowFocus(*) {
    global AppGui, AppVisible
    if !AppVisible || !WinExist("ahk_id " AppGui.Hwnd) {
        ShowAndFocus()
        return
    }
    if WinActive("ahk_id " AppGui.Hwnd) {
        HideToTray()
    } else {
        ShowAndFocus()
    }
}

ShowAndFocus() {
    global AppGui, AppVisible, LastWinW, LastWinH, LastWinX, LastWinY
    AppVisible := true
    ClampWindowPos()
    try {
        showOpts := "w" LastWinW " h" LastWinH
        if LastWinX != "" && LastWinY != ""
            showOpts .= " x" LastWinX " y" LastWinY
        AppGui.Show(showOpts)
        WinActivate("ahk_id " AppGui.Hwnd)
        ApplyChrome(LastWinW, LastWinH)
    }
    UpdateTrayTip()
    SetStatus("Focused — Ctrl+Alt+P toggles tray")
}

; Keep restored X/Y on a visible monitor (multi-monitor unplug / laptop dock).
ClampWindowPos() {
    global LastWinX, LastWinY, LastWinW, LastWinH
    if LastWinX = "" || LastWinY = ""
        return
    try {
        ; Virtual screen
        vx := SysGet(76)  ; SM_XVIRTUALSCREEN
        vy := SysGet(77)
        vw := SysGet(78)
        vh := SysGet(79)
        w := LastWinW
        h := LastWinH
        ; Require at least 80x40 of the title area on-screen
        if LastWinX + w < vx + 80 || LastWinY + 40 < vy + 8
            || LastWinX > vx + vw - 80 || LastWinY > vy + vh - 40 {
            LastWinX := vx + Max(Round((vw - w) / 2), 0)
            LastWinY := vy + Max(Round((vh - h) / 3), 40)
        }
    }
}

HideToTray() {
    global AppGui, AppVisible, HidingToTray
    if HidingToTray
        return
    HidingToTray := true
    ChipDrag.Cancel()
    try OnDesktopStop()
    SaveIniAll()
    AppVisible := false
    try AppGui.Hide()
    UpdateTrayTip()
    TrayTip("Playwright AHK", "Hidden to tray — Ctrl+Alt+P to restore", "Iconi")
    HidingToTray := false
}

BuildGui() {
    global AppGui, StatusBar
    global EdPrompt, EdReply, BtnSend, BtnCancelCopilot, BtnUseReply
    global EdRecording, EdRecordUrl, EdRecordInstr, BtnRecord, BtnSendRecording
    global BtnSaveAsTest, BtnRunSavedTest, LblRecording
    global BtnReloadLatest, BtnCopyRec, BtnOpenRec, BtnCancelRecord
    global RecordJob, BusyRecord, LastSavedSpec
    global EdCanvas, EdTerminal, BtnRun, BtnCancelPuzzle
    global Catalog, Tab1Ctrls, Tab2Ctrls, Tab3Ctrls, ChipBtns, EdChipFilter, LblNoChipMatch
    global BtnTab1, BtnTab2, BtnTab3, WipeGui, WipeLbl
    global Desktop, EdDesktopJson, EdDesktopLog, EdDesktopInstr, LbDesktopSteps, BtnStepDel, BtnStepUp, BtnStepDown, BtnStepDup, BtnStepWait
    global BtnDeskRecord, BtnDeskStop, BtnDeskPlay, BtnDeskVerify, BtnDeskSave, BtnDeskOpenDir, BtnDeskLoad, BtnDeskSend, BtnDeskClear, BtnDeskProbe

    AppGui := Gui("+Resize +MinSize1000x640", "Playwright AHK — Overnight GUI")
    Theme.StyleGui(AppGui)
    AppGui.OnEvent("Close", OnAppClose)
    AppGui.OnEvent("Escape", OnEsc)
    AppGui.OnEvent("Size", OnResize)

    ; Custom tab strip (replaces raw Tab3 blink — train wipe on switch)
    BtnTab1 := AppGui.Add("Button", "x10 y10 w200 h34", "Copilot studio")
    Theme.StyleTabBtn(BtnTab1, true)
    BtnTab1.OnEvent("Click", (*) => RequestTab(1))

    BtnTab2 := AppGui.Add("Button", "x218 y10 w200 h34", "CLI puzzle")
    Theme.StyleTabBtn(BtnTab2, false)
    BtnTab2.OnEvent("Click", (*) => RequestTab(2))

    BtnTab3 := AppGui.Add("Button", "x426 y10 w220 h34", "Desktop UIA (Windows)")
    Theme.StyleTabBtn(BtnTab3, false)
    BtnTab3.OnEvent("Click", (*) => RequestTab(3))

    AppGui.Add("Text", "x660 y18 w300 c" Theme.FgDim,
        "Ctrl+1/2/3 · Ctrl+Alt+P tray · Ctrl+S · F5 puzzle")

    ; ----- Tab 1 content (left: Copilot · right: Recording) -----
    leftW := 560
    rightX := 600
    rightW := 360

    t1Hint := AppGui.Add("Text", "x24 y56 w" leftW " c" Theme.FgDim,
        "Compose a prompt, Send via copilot (async). Right pane: Record → file → Copilot.")
    t1PromptLbl := AppGui.Add("Text", "x24 y86 w200", "Prompt")
    EdPrompt := AppGui.Add("Edit", "x24 y108 w" leftW " h150 Multi WantReturn VScroll", "")
    Theme.StyleEdit(EdPrompt)

    BtnSend := AppGui.Add("Button", "x24 y268 w100 h30 Default", "Send")
    Theme.StyleButton(BtnSend, true)
    BtnSend.OnEvent("Click", OnCopilotSend)

    BtnCancelCopilot := AppGui.Add("Button", "x132 y268 w90 h30", "Cancel")
    Theme.StyleButton(BtnCancelCopilot)
    BtnCancelCopilot.Enabled := false
    BtnCancelCopilot.OnEvent("Click", OnCopilotCancel)

    BtnClearReply := AppGui.Add("Button", "x230 y268 w90 h30", "Clear reply")
    Theme.StyleButton(BtnClearReply)
    BtnClearReply.OnEvent("Click", OnClearReply)

    BtnUseReply := AppGui.Add("Button", "x328 y268 w150 h30", "Use reply as prompt")
    Theme.StyleButton(BtnUseReply, true)
    BtnUseReply.OnEvent("Click", OnUseReplyAsPrompt)

    BtnSavePrompt := AppGui.Add("Button", "x486 y268 w98 h30", "Save")
    Theme.StyleButton(BtnSavePrompt)
    BtnSavePrompt.OnEvent("Click", OnSavePrompt)

    t1ReplyLbl := AppGui.Add("Text", "x24 y308 w" leftW, "Response (editable)")
    EdReply := AppGui.Add("Edit", "x24 y330 w" leftW " h290 Multi WantReturn VScroll", "")
    Theme.StyleEdit(EdReply)

    ; --- Right: Recording pane ---
    LblRecording := AppGui.Add("Text", "x" rightX " y56 w" rightW, "Recording → Copilot")
    try LblRecording.SetFont("s10 Bold c" Theme.Fg, "Segoe UI")
    t1RecHint := AppGui.Add("Text", "x" rightX " y78 w" rightW " c" Theme.FgDim,
        "Headed codegen writes recordings\latest.spec.js (wait for EXIT).")
    t1UrlLbl := AppGui.Add("Text", "x" rightX " y108 w40 c" Theme.FgDim, "URL")
    EdRecordUrl := AppGui.Add("Edit", "x" (rightX + 40) " y104 w" (rightW - 40) " h26", "https://playwright.dev")
    Theme.StyleEdit(EdRecordUrl)

    BtnRecord := AppGui.Add("Button", "x" rightX " y138 w" (rightW - 100) " h32", "Record (headed codegen)")
    Theme.StyleButton(BtnRecord, true)
    BtnRecord.OnEvent("Click", OnRecordStart)
    BtnCancelRecord := AppGui.Add("Button", "x" (rightX + rightW - 96) " y138 w96 h32", "Cancel")
    Theme.StyleButton(BtnCancelRecord)
    BtnCancelRecord.Enabled := false
    BtnCancelRecord.OnEvent("Click", OnRecordCancelClick)

    t1SpecLbl := AppGui.Add("Text", "x" rightX " y178 w" rightW, "latest.spec.js")
    EdRecording := AppGui.Add("Edit", "x" rightX " y198 w" rightW " h200 Multi ReadOnly VScroll", "")
    Theme.StyleEdit(EdRecording)

    t1InstrLbl := AppGui.Add("Text", "x" rightX " y406 w" rightW, "Your instruction (sent last)")
    EdRecordInstr := AppGui.Add("Edit", "x" rightX " y426 w" rightW " h60 Multi WantReturn VScroll",
        "Turn this recording into a clean, stable Playwright test.")
    Theme.StyleEdit(EdRecordInstr)

    BtnSendRecording := AppGui.Add("Button", "x" rightX " y496 w" rightW " h30", "Send recording to Copilot")
    Theme.StyleButton(BtnSendRecording, true)
    BtnSendRecording.OnEvent("Click", OnSendRecordingToCopilot)

    BtnSaveAsTest := AppGui.Add("Button", "x" rightX " y532 w" (rightW // 2 - 4) " h28", "Save as test")
    Theme.StyleButton(BtnSaveAsTest)
    BtnSaveAsTest.Enabled := false
    BtnSaveAsTest.OnEvent("Click", OnSaveAsTest)

    BtnRunSavedTest := AppGui.Add("Button", "x" (rightX + rightW // 2 + 4) " y532 w" (rightW // 2 - 4) " h28", "Run saved test")
    Theme.StyleButton(BtnRunSavedTest)
    BtnRunSavedTest.Enabled := false
    BtnRunSavedTest.OnEvent("Click", OnRunSavedTest)

    BtnReloadLatest := AppGui.Add("Button", "x" rightX " y566 w" (rightW // 3 - 4) " h26", "Reload")
    Theme.StyleButton(BtnReloadLatest)
    BtnReloadLatest.OnEvent("Click", OnReloadLatestSpec)
    BtnCopyRec := AppGui.Add("Button", "x" (rightX + rightW // 3) " y566 w" (rightW // 3 - 4) " h26", "Copy spec")
    Theme.StyleButton(BtnCopyRec)
    BtnCopyRec.OnEvent("Click", OnCopyRecording)
    BtnOpenRec := AppGui.Add("Button", "x" (rightX + 2 * rightW // 3) " y566 w" (rightW // 3) " h26", "Recordings")
    Theme.StyleButton(BtnOpenRec)
    BtnOpenRec.OnEvent("Click", OnOpenRecordingsFolder)

    Tab1Ctrls := [t1Hint, t1PromptLbl, EdPrompt, BtnSend, BtnCancelCopilot, BtnClearReply
        , BtnUseReply, BtnSavePrompt, t1ReplyLbl, EdReply
        , LblRecording, t1RecHint, t1UrlLbl, EdRecordUrl, BtnRecord, BtnCancelRecord, t1SpecLbl, EdRecording
        , t1InstrLbl, EdRecordInstr, BtnSendRecording, BtnSaveAsTest, BtnRunSavedTest
        , BtnReloadLatest, BtnCopyRec, BtnOpenRec]

    ; ----- Tab 2 content -----
    t2Hint := AppGui.Add("Text", "x24 y56 w900 c" Theme.FgDim,
        "Drag chips onto the canvas (or click to add). Slots open a dark editor. Empty/incomplete slots block Run.")
    t2PiecesLbl := AppGui.Add("Text", "x24 y86 w280", "Pieces  (" Catalog.pieces.Length " from scripts/puzzle-pieces.json)")
    t2FilterLbl := AppGui.Add("Text", "x520 y86 w40 c" Theme.FgDim, "Filter")
    EdChipFilter := AppGui.Add("Edit", "x565 y82 w170 h26", "")
    Theme.StyleEdit(EdChipFilter)
    EdChipFilter.OnEvent("Change", OnChipFilterChange)
    BtnClearFilter := AppGui.Add("Button", "x740 y82 w50 h26", "Clear")
    Theme.StyleButton(BtnClearFilter)
    BtnClearFilter.OnEvent("Click", OnClearChipFilter)
    LblNoChipMatch := AppGui.Add("Text", "x800 y86 w160 c" Theme.FgDim, "")
    try LblNoChipMatch.SetFont("s9 c" Theme.FgDim, "Segoe UI")

    chipCtrls := []
    ChipBtns := []
    x := 24
    y := 108
    colW := 180
    rowH := 30
    cols := 5
    for idx, piece in Catalog.pieces {
        btn := AppGui.Add("Button", "x" x " y" y " w" (colW - 8) " h26", piece["label"])
        Theme.StyleChip(btn)
        btn.OnEvent("Click", ChipClick.Bind(piece))
        tip := ChipTooltipFor(piece)
        try btn.ToolTip := tip
        btn.OnEvent("ContextMenu", ChipContextMenu.Bind(piece))
        ChipDrag.RegisterChip(btn.Hwnd, piece)
        chipCtrls.Push(btn)
        ChipBtns.Push({ btn: btn, piece: piece, label: piece["label"], x: x, y: y })
        if Mod(idx, cols) = 0 {
            x := 24
            y += rowH
        } else
            x += colW
    }
    chipBottom := y + (Mod(Catalog.pieces.Length, cols) = 0 ? 0 : rowH) + 8

    t2CanvasLbl := AppGui.Add("Text", "x24 y" chipBottom " w400", "Command canvas (drop target · editable · one command per line)")
    EdCanvas := AppGui.Add("Edit", "x24 y" (chipBottom + 22) " w700 h120 Multi WantReturn VScroll", "")
    Theme.StyleEdit(EdCanvas)
    ChipDrag.SetCanvas(EdCanvas.Hwnd)
    ChipDrag.Install(OnChipDrop, OnChipDragHover, ChipDragCanStart)

    by := chipBottom + 22
    BtnRun := AppGui.Add("Button", "x740 y" by " w200 h36", "Run")
    Theme.StyleButton(BtnRun, true)
    BtnRun.OnEvent("Click", OnPuzzleRun)

    BtnCancelPuzzle := AppGui.Add("Button", "x740 y" (by + 42) " w200 h28", "Cancel run")
    Theme.StyleButton(BtnCancelPuzzle)
    BtnCancelPuzzle.Enabled := false
    BtnCancelPuzzle.OnEvent("Click", OnPuzzleCancel)

    BtnClear := AppGui.Add("Button", "x740 y" (by + 78) " w96 h28", "Clear")
    Theme.StyleButton(BtnClear)
    BtnClear.OnEvent("Click", OnPuzzleClear)

    BtnBksp := AppGui.Add("Button", "x844 y" (by + 78) " w96 h28", "Backspace")
    Theme.StyleButton(BtnBksp)
    BtnBksp.OnEvent("Click", OnPuzzleBackspace)

    BtnCopy := AppGui.Add("Button", "x740 y" (by + 114) " w200 h28", "Copy command")
    Theme.StyleButton(BtnCopy)
    BtnCopy.OnEvent("Click", OnPuzzleCopy)

    BtnSaveCanvas := AppGui.Add("Button", "x740 y" (by + 150) " w96 h28", "Save")
    Theme.StyleButton(BtnSaveCanvas)
    BtnSaveCanvas.OnEvent("Click", OnSaveCanvas)

    BtnSeed := AppGui.Add("Button", "x844 y" (by + 150) " w96 h28", "Default")
    Theme.StyleButton(BtnSeed)
    BtnSeed.OnEvent("Click", OnPuzzleSeedDefault)

    termTop := by + 186
    t2TermLbl := AppGui.Add("Text", "x24 y" termTop " w300", "Terminal mirror (live · persisted)")
    BtnCopyTerm := AppGui.Add("Button", "x520 y" (termTop - 2) " w110 h26", "Copy term")
    Theme.StyleButton(BtnCopyTerm)
    BtnCopyTerm.OnEvent("Click", OnCopyTerminal)
    BtnClearTerm := AppGui.Add("Button", "x638 y" (termTop - 2) " w110 h26", "Clear term")
    Theme.StyleButton(BtnClearTerm)
    BtnClearTerm.OnEvent("Click", OnClearTerminal)
    BtnOpenRepo := AppGui.Add("Button", "x756 y" (termTop - 2) " w184 h26", "Open repo folder")
    Theme.StyleButton(BtnOpenRepo)
    BtnOpenRepo.OnEvent("Click", OnOpenRepoFolder)
    EdTerminal := AppGui.Add("Edit", "x24 y" (termTop + 22) " w920 h160 Multi ReadOnly VScroll", "")
    Theme.StyleEdit(EdTerminal)

    Tab2Ctrls := [t2Hint, t2PiecesLbl, t2FilterLbl, EdChipFilter, BtnClearFilter, LblNoChipMatch]
    for c in chipCtrls
        Tab2Ctrls.Push(c)
    Tab2Ctrls.Push(t2CanvasLbl, EdCanvas, BtnRun, BtnCancelPuzzle, BtnClear, BtnBksp, BtnCopy
        , BtnSaveCanvas, BtnSeed, t2TermLbl, BtnCopyTerm, BtnClearTerm, BtnOpenRepo, EdTerminal)


    ; ----- Tab 3 content — Windows desktop UIA (NOT Playwright) -----
    t3Banner := AppGui.Add("Text", "x24 y56 w920 c" Theme.Err,
        "WINDOWS DESKTOP UIA RECORDER — AutoHotkey + UI Automation only. Never Playwright / npx / @playwright/test.")
    try t3Banner.SetFont("s10 Bold c" Theme.Err, "Segoe UI")
    t3Hint := AppGui.Add("Text", "x24 y78 w700 c" Theme.FgDim,
        "UIA ranked targets · click/dblclick/rclick/drag/wheel/hover/type/key/wait. Strict spots = client-% checksums. Play highlights the current ListBox step.")

    ChkStrictSpots := AppGui.Add("CheckBox", "x740 y76 w200 c" Theme.Fg, "Strict fullscreen spots")
    try ChkStrictSpots.Value := 1
    Theme.StyleCheck(ChkStrictSpots)
    ChkStrictSpots.OnEvent("Click", OnStrictSpotsToggle)

    t3ListLbl := AppGui.Add("Text", "x24 y108 w250", "Steps (index · action · target)")
    LbDesktopSteps := AppGui.Add("ListBox", "x24 y128 w250 h250")
    try LbDesktopSteps.Opt("Background" Theme.BgInput " c" Theme.Fg)
    try LbDesktopSteps.SetFont("s9 c" Theme.Fg, "Consolas")
    LbDesktopSteps.OnEvent("DoubleClick", OnDesktopStepDelete)

    BtnStepDel := AppGui.Add("Button", "x24 y384 w50 h26", "Delete")
    Theme.StyleButton(BtnStepDel)
    BtnStepDel.OnEvent("Click", OnDesktopStepDelete)
    BtnStepUp := AppGui.Add("Button", "x78 y384 w36 h26", "Up")
    Theme.StyleButton(BtnStepUp)
    BtnStepUp.OnEvent("Click", OnDesktopStepUp)
    BtnStepDown := AppGui.Add("Button", "x118 y384 w44 h26", "Down")
    Theme.StyleButton(BtnStepDown)
    BtnStepDown.OnEvent("Click", OnDesktopStepDown)
    BtnStepDup := AppGui.Add("Button", "x166 y384 w40 h26", "Dup")
    Theme.StyleButton(BtnStepDup)
    BtnStepDup.OnEvent("Click", OnDesktopStepDup)
    BtnStepWait := AppGui.Add("Button", "x210 y384 w60 h26", "Wait")
    Theme.StyleButton(BtnStepWait)
    BtnStepWait.OnEvent("Click", OnDesktopStepWait)

    t3StepsLbl := AppGui.Add("Text", "x286 y108 w430", "Steps JSON (kind: windows-uia)")
    EdDesktopJson := AppGui.Add("Edit", "x286 y128 w438 h280 Multi WantReturn VScroll", "")
    Theme.StyleEdit(EdDesktopJson)

    bx := 740
    BtnDeskRecord := AppGui.Add("Button", "x" bx " y128 w200 h36", "Record")
    Theme.StyleButton(BtnDeskRecord, true)
    BtnDeskRecord.OnEvent("Click", OnDesktopRecord)
    BtnDeskStop := AppGui.Add("Button", "x" bx " y170 w200 h28", "Stop")
    Theme.StyleButton(BtnDeskStop)
    BtnDeskStop.Enabled := false
    BtnDeskStop.OnEvent("Click", OnDesktopStop)
    BtnDeskPlay := AppGui.Add("Button", "x" bx " y210 w96 h28", "Play")
    Theme.StyleButton(BtnDeskPlay, true)
    BtnDeskPlay.OnEvent("Click", OnDesktopPlay)
    BtnDeskVerify := AppGui.Add("Button", "x" (bx + 104) " y210 w96 h28", "Verify")
    Theme.StyleButton(BtnDeskVerify)
    BtnDeskVerify.OnEvent("Click", OnDesktopVerify)
    BtnDeskSave := AppGui.Add("Button", "x" bx " y248 w96 h28", "Save JSON")
    Theme.StyleButton(BtnDeskSave)
    BtnDeskSave.OnEvent("Click", OnDesktopSave)
    BtnDeskOpenDir := AppGui.Add("Button", "x" (bx + 104) " y248 w96 h28", "Folder")
    Theme.StyleButton(BtnDeskOpenDir)
    BtnDeskOpenDir.OnEvent("Click", OnDesktopOpenFolder)
    BtnDeskLoad := AppGui.Add("Button", "x" bx " y286 w96 h28", "Load latest")
    Theme.StyleButton(BtnDeskLoad)
    BtnDeskLoad.OnEvent("Click", OnDesktopLoadLatest)
    BtnDeskClear := AppGui.Add("Button", "x" (bx + 104) " y286 w96 h28", "Clear all")
    Theme.StyleButton(BtnDeskClear)
    BtnDeskClear.OnEvent("Click", OnDesktopClear)
    BtnDeskProbe := AppGui.Add("Button", "x" bx " y320 w200 h26", "Probe under cursor")
    Theme.StyleButton(BtnDeskProbe)
    BtnDeskProbe.OnEvent("Click", OnDesktopProbe)

    t3InstrLbl := AppGui.Add("Text", "x" bx " y352 w200", "Copilot instruction")
    EdDesktopInstr := AppGui.Add("Edit", "x" bx " y372 w200 h50 Multi WantReturn VScroll",
        "Refactor these UIA steps for stability; keep AutomationId-first targeting.")
    Theme.StyleEdit(EdDesktopInstr)
    BtnDeskSend := AppGui.Add("Button", "x" bx " y430 w200 h36", "Send desktop → Copilot")
    Theme.StyleButton(BtnDeskSend, true)
    BtnDeskSend.OnEvent("Click", OnDesktopSendToCopilot)

    t3LogLbl := AppGui.Add("Text", "x24 y420 w400", "Play / Verify log (desktop UIA only)")
    EdDesktopLog := AppGui.Add("Edit", "x24 y440 w700 h160 Multi ReadOnly VScroll", "")
    Theme.StyleEdit(EdDesktopLog)

    Tab3Ctrls := [t3Banner, t3Hint, ChkStrictSpots, t3ListLbl, LbDesktopSteps, BtnStepDel, BtnStepUp, BtnStepDown, BtnStepDup, BtnStepWait
        , t3StepsLbl, EdDesktopJson
        , BtnDeskRecord, BtnDeskStop, BtnDeskPlay, BtnDeskVerify, BtnDeskSave, BtnDeskOpenDir, BtnDeskLoad, BtnDeskClear, BtnDeskProbe
        , t3InstrLbl, EdDesktopInstr, BtnDeskSend, t3LogLbl, EdDesktopLog]

    StatusBar := AppGui.Add("Text", "x10 y675 w960 h24 +0x100", " Ready")  ; SS_NOTIFY for click
    Theme.StyleStatus(StatusBar)
    StatusBar.OnEvent("Click", OnStatusBarClick)
    StatusBar.OnEvent("DoubleClick", OnStatusBarClick)

    ; Train-wipe overlay (child of main GUI; hidden until tab switch)
    WipeGui := Gui("+Parent" AppGui.Hwnd " -Caption +ToolWindow -Border")
    WipeGui.BackColor := Theme.Train
    WipeGui.MarginX := 0
    WipeGui.MarginY := 0
    WipeLbl := WipeGui.Add("Text", "x0 y18 w960 h40 Center Background" Theme.Train " cFFFFFF"
        , "══════▶  PLAYWRIGHT CLI PUZZLE  ▶══════")
    try WipeLbl.SetFont("s14 Bold cFFFFFF", "Segoe UI")
    WipeGui.Hide()

    ; Hotkeys when app focused
    HotIfWinActive("ahk_id " AppGui.Hwnd)
    Hotkey("^Enter", OnCopilotSend)
    Hotkey("F5", OnPuzzleRun)
    Hotkey("Delete", OnPuzzleBackspace)
    Hotkey("Esc", OnEscDragOrFocus)
    Hotkey("^s", OnSaveAllHotkey)
    Hotkey("^+c", OnPuzzleCopy)
    Hotkey("^+t", OnCopyTerminal)
    Hotkey("^1", (*) => RequestTab(1))
    Hotkey("^2", (*) => RequestTab(2))
    Hotkey("^3", (*) => RequestTab(3))
    Hotkey("^l", OnClearChipFilter)
    Hotkey("^r", OnReloadLatestSpec)
    Hotkey("^z", OnCanvasUndo)
    Hotkey("F6", OnFocusChipFilter)
    Hotkey("F7", OnFocusCanvas)
    Hotkey("^+j", OnDesktopCopyJson)
    HotIf()

    ; Autosave prompt/canvas/terminal every 60s while running
    SetTimer(SaveIniAll, 60000)
}

; ---------- Tab train wipe ----------

RequestTab(n) {
    global ActiveTab, WipeActive
    if n = ActiveTab || WipeActive
        return
    StartTrainWipe(n)
}

StartTrainWipe(target) {
    global ActiveTab, WipeActive, WipeDir, WipeStep, WipeTarget
    global WipeGui, WipeLbl, AppGui, LastWinW, LastWinH, BtnTab1, BtnTab2, BtnTab3

    ChipDrag.Cancel()
    try OnDesktopStop()
    WipeTarget := target
    WipeDir := (target > ActiveTab) ? 1 : -1
    WipeStep := 0
    WipeActive := true

    if target = 1
        label := "◀══════  COPILOT PROMPT STUDIO  ══════◀"
    else if target = 2
        label := "══════▶  PLAYWRIGHT CLI PUZZLE  ▶══════"
    else
        label := "══════▶  WINDOWS DESKTOP UIA  ▶══════"
    WipeLbl.Value := label
    Theme.StyleTabBtn(BtnTab1, target = 1)
    Theme.StyleTabBtn(BtnTab2, target = 2)
    Theme.StyleTabBtn(BtnTab3, target = 3)

    ; Cover content area below tab strip
    w := Max(LastWinW - 20, 800)
    h := 72
    y := 48
    ; Start off-screen on the incoming side
    startX := WipeDir = 1 ? -w : LastWinW
    try {
        WipeGui.Show("x" startX " y" y " w" w " h" h " NoActivate")
    }
    SetTimer(AnimateTrainWipe, 16)
    SetStatus(WipeDir = 1 ? "Train → puzzle…" : "Train → copilot…")
}

AnimateTrainWipe() {
    global WipeActive, WipeDir, WipeStep, WipeTarget, WipeGui, LastWinW

    if !WipeActive {
        SetTimer(AnimateTrainWipe, 0)
        return
    }

    WipeStep += 1
    total := 18
    w := Max(LastWinW - 20, 800)
    y := 48
    h := 72

    ; Ease across: off-screen → cover → off-screen other side
    ; Midpoint (~step 9): swap tab content underneath
    progress := WipeStep / total
    if WipeDir = 1
        x := Round(-w + progress * (LastWinW + w))
    else
        x := Round(LastWinW - progress * (LastWinW + w))

    try WipeGui.Show("x" x " y" y " w" w " h" h " NoActivate")

    if WipeStep = 9
        ShowTab(WipeTarget, false)

    if WipeStep >= total {
        SetTimer(AnimateTrainWipe, 0)
        WipeActive := false
        try WipeGui.Hide()
        ShowTab(WipeTarget, true)
        SaveIniAll()
        SetStatus(WipeTarget = 1 ? "Copilot prompt studio" : (WipeTarget = 2 ? "Playwright CLI puzzle" : "Desktop UIA (Windows)"))
    }
}

ShowTab(n, updateButtons := true) {
    global ActiveTab, Tab1Ctrls, Tab2Ctrls, Tab3Ctrls, BtnTab1, BtnTab2, BtnTab3

    ActiveTab := n
    for c in Tab1Ctrls {
        try {
            if n = 1
                c.Visible := true
            else
                c.Visible := false
        }
    }
    for c in Tab2Ctrls {
        try {
            if n = 2
                c.Visible := true
            else
                c.Visible := false
        }
    }
    for c in Tab3Ctrls {
        try {
            if n = 3
                c.Visible := true
            else
                c.Visible := false
        }
    }
    if updateButtons {
        Theme.StyleTabBtn(BtnTab1, n = 1)
        Theme.StyleTabBtn(BtnTab2, n = 2)
        Theme.StyleTabBtn(BtnTab3, n = 3)
    }
    ; Re-apply chip filter after bulk Visible toggles
    if n = 2
        OnChipFilterChange()
    if n = 3
        EnsureDesktopJsonTemplate()
}

EnsureDesktopJsonTemplate() {
    global EdDesktopJson, Desktop
    if Trim(EdDesktopJson.Value) != ""
        return
    ; Empty starter so kind boundary is obvious in the editor
    EdDesktopJson.Value := '{ "version": 1, "kind": "windows-uia", "steps": [] }'
    try Desktop.LoadJson(EdDesktopJson.Value)
    RefreshDesktopStepList()
}

ApplyChrome(w, h) {
    global AppGui, LastWinW, LastWinH
    LastWinW := w
    LastWinH := h
    Theme.ApplyDarkTitleBar(AppGui.Hwnd)
    Theme.ApplyRoundedRegion(AppGui.Hwnd, w, h, 14)
}

OnAppClose(*) {
    ; Hide to tray instead of exit — Exit lives on the tray menu
    HideToTray()
}

OnEsc(*) {
    OnEscDragOrFocus()
}

OnEscDragOrFocus(*) {
    global AppGui, BtnTab1, Desktop, BusyDesktop, ActiveTab
    if ChipDrag.Cancel() {
        SetStatus("Drag cancelled")
        return
    }
    if BusyDesktop || (IsObject(Desktop) && Desktop.recording) {
        OnDesktopStop()
        SetStatus("Desktop UIA recording stopped (Esc)", "ok")
        return
    }
    try BtnTab1.Focus()
}

OnResize(thisGui, minMax, width, height) {
    global StatusBar, EdPrompt, EdReply, EdCanvas, EdTerminal
    global EdRecording, EdRecordUrl, EdRecordInstr, BtnRecord, BtnSendRecording
    global BtnSaveAsTest, BtnRunSavedTest, LblRecording
    global BtnReloadLatest, BtnCopyRec, BtnOpenRec, BtnCancelRecord
    global EdDesktopJson, EdDesktopLog, LbDesktopSteps, BtnStepDel, BtnStepUp, BtnStepDown, BtnStepDup, BtnStepWait
    if minMax = -1 {
        ; Minimize → tray (same as Close)
        HideToTray()
        return
    }
    try {
        StatusBar.Move(10, height - 34, width - 20, 24)
        contentW := width - 48
        ; Tab1 split: ~58% left Copilot / ~38% right Recording
        leftW := Max(Round(contentW * 0.55), 420)
        gap := 16
        rightX := 24 + leftW + gap
        rightW := Max(contentW - leftW - gap, 280)
        replyH := Max(height - 400, 140)
        recH := Max(height - 480, 120)
        if contentW > 200 {
            EdPrompt.Move(24, 108, leftW, 150)
            EdReply.Move(24, 330, leftW, replyH)
            try LblRecording.Move(rightX, 56, rightW, )
            try EdRecordUrl.Move(rightX + 40, 104, rightW - 40, 26)
            try BtnRecord.Move(rightX, 138, rightW - 100, 32)
            try BtnCancelRecord.Move(rightX + rightW - 96, 138, 96, 32)
            try EdRecording.Move(rightX, 198, rightW, recH)
            instrY := 198 + recH + 8
            try EdRecordInstr.Move(rightX, instrY + 20, rightW, 60)
            try BtnSendRecording.Move(rightX, instrY + 90, rightW, 30)
            try BtnSaveAsTest.Move(rightX, instrY + 126, rightW // 2 - 4, 28)
            try BtnRunSavedTest.Move(rightX + rightW // 2 + 4, instrY + 126, rightW // 2 - 4, 28)
            try BtnReloadLatest.Move(rightX, instrY + 160, rightW // 3 - 4, 26)
            try BtnCopyRec.Move(rightX + rightW // 3, instrY + 160, rightW // 3 - 4, 26)
            try BtnOpenRec.Move(rightX + 2 * rightW // 3, instrY + 160, rightW // 3, 26)
            EdCanvas.Move(24, , Min(contentW - 220, 700), )
            EdTerminal.Move(24, , contentW, )
            jsonW := Min(contentW - 220 - 262, 438)
            if jsonW < 280
                jsonW := Max(contentW - 480, 200)
            try LbDesktopSteps.Move(24, 128, 250, Max(height - 470, 180))
            try BtnStepDel.Move(24, Max(height - 336, 384), 50, 26)
            try BtnStepUp.Move(78, Max(height - 336, 384), 36, 26)
            try BtnStepDown.Move(118, Max(height - 336, 384), 44, 26)
            try BtnStepDup.Move(166, Max(height - 336, 384), 40, 26)
            try BtnStepWait.Move(210, Max(height - 336, 384), 60, 26)
            try EdDesktopJson.Move(286, 128, jsonW, Max(height - 420, 180))
            try EdDesktopLog.Move(24, , Min(contentW - 220, 700), )
        }
        ApplyChrome(width, height)
    }
}

OnClearReply(*) {
    global EdReply
    EdReply.Value := ""
    SetStatus("Reply cleared")
}

OnUseReplyAsPrompt(*) {
    global EdPrompt, EdReply
    reply := EdReply.Value
    body := reply
    if Trim(body) = "" {
        SetStatus("Reply is empty — nothing to promote")
        return
    }
    EdPrompt.Value := body
    try EdPrompt.Focus()
    SaveIniAll()
    SetStatus("Reply promoted → prompt (ready to Send)")
}

OnSavePrompt(*) {
    SaveIniAll()
    SetStatus("Saved prompt + canvas + terminal to ini")
}

OnSaveCanvas(*) {
    SaveIniAll()
    SetStatus("Canvas + terminal saved to ini")
}

OnSaveAllHotkey(*) {
    SaveIniAll()
    SetStatus("Saved (Ctrl+S) — prompt, canvas, terminal, window")
}

OnPuzzleSeedDefault(*) {
    global Canvas, EdCanvas, ActiveTab, AppGui
    if ActiveTab != 2 {
        RequestTab(2)
        return
    }
    if Trim(EdCanvas.Value) != "" {
        if !Theme.ConfirmDark("Replace canvas with default test --project=chromium?", "Reset canvas", AppGui.Hwnd)
            return
    }
    Canvas.SeedDefault()
    RefreshCanvasEdit()
    SaveIniAll()
    SetStatus("Canvas reset to defaultFirstDrop")
}

OnCopilotSend(*) {
    global EdPrompt, EdReply, RepoRoot, BusyCopilot, CopilotJob, BtnSend, BtnCancelCopilot, ActiveTab, JobStartCopilot, WipeActive

    if WipeActive {
        SetStatus("Wait for tab transition…")
        return
    }
    ; Ctrl+Enter is Tab1-only; button Click still works from tab 1
    if ActiveTab != 1 {
        RequestTab(1)
        SetStatus("Switched to Copilot — press Send / Ctrl+Enter")
        return
    }

    if BusyCopilot {
        SetStatus("Copilot already running… (Cancel to abort)")
        return
    }
    prompt := EdPrompt.Value
    if Trim(prompt) = "" {
        EdReply.Value := "ERROR: prompt is empty."
        SetStatus("Send blocked — empty prompt")
        return
    }

    SaveIniAll()
    BusyCopilot := true
    UpdateTrayTip()
    try BtnSend.Enabled := false
    try BtnCancelCopilot.Enabled := true
    EdReply.Value := "Running copilot (async)…`n"
    JobStartCopilot := A_TickCount
    SetStatus("Copilot starting…")

    CopilotJob := ShellExec.StartCopilot(prompt, RepoRoot)
    if CopilotJob.done {
        EdReply.Value := CopilotJob.output
        BusyCopilot := false
        UpdateTrayTip()
        try BtnSend.Enabled := true
        try BtnCancelCopilot.Enabled := false
        SetStatus("Copilot failed immediately (exit " CopilotJob.exitCode ")")
        return
    }
    SetTimer(PollCopilot, 150)
}

OnCopilotCancel(*) {
    global CopilotJob, EdReply, BusyCopilot, BtnSend, BtnCancelCopilot
    if !BusyCopilot || !IsObject(CopilotJob) {
        BusyCopilot := false
        try BtnSend.Enabled := true
        try BtnCancelCopilot.Enabled := false
        return
    }
    SetTimer(PollCopilot, 0)
    CopilotJob.Cancel("CANCELLED — Copilot job stopped by user.")
    EdReply.Value := CopilotJob.output
    BusyCopilot := false
    UpdateTrayTip()
    try BtnSend.Enabled := true
    try BtnCancelCopilot.Enabled := false
    SetStatus("Copilot cancelled")
    CopilotJob := ""
}

PollCopilot() {
    global CopilotJob, EdReply, BusyCopilot, BtnSend, BtnCancelCopilot, JobStartCopilot, BtnSaveAsTest
    if !IsObject(CopilotJob) {
        SetTimer(PollCopilot, 0)
        return
    }
    if !CopilotJob.done && CopilotJob.partial != ""
        EdReply.Value := CopilotJob.partial
    if !CopilotJob.done {
        elapsed := Round((A_TickCount - JobStartCopilot) / 1000)
        SetStatus("Copilot running… " elapsed "s  (Cancel to abort)")
    }

    if !CopilotJob.Poll()
        return

    SetTimer(PollCopilot, 0)
    EdReply.Value := CopilotJob.output
    code := CopilotJob.exitCode
    BusyCopilot := false
    UpdateTrayTip()
    try BtnSend.Enabled := true
    try BtnCancelCopilot.Enabled := false
    elapsed := Round((A_TickCount - JobStartCopilot) / 1000)
    SetStatus((code = 0 ? "Copilot finished OK" : "Copilot finished exit " code) "  (" elapsed "s)", code = 0 ? "ok" : "err")
    try TrayTip("Copilot", (code = 0 ? "Finished OK" : "Exit " code) " (" elapsed "s)", code = 0 ? "Iconi" : "Iconx")
    try BtnSaveAsTest.Enabled := (Trim(EdReply.Value) != "")
    CopilotJob := ""
    SaveIniAll()
}

; ---------- Puzzle chips / canvas ----------

SetChipButtonsEnabled(enabled) {
    global ChipBtns
    for item in ChipBtns {
        try item.btn.Enabled := enabled
    }
}

AddPieceToCanvas(piece) {
    global Canvas, Catalog, AppGui, EdCanvas
    argv := Catalog.ResolvePieceArgv(piece, AppGui.Hwnd)
    if !(argv is Array) {
        try Theme.FlashEdit(EdCanvas, false, 280)
        SetStatus("Blocked — required slot empty or cancelled", "err")
        return false
    }
    Canvas.AddResolved(piece["label"], argv)
    RefreshCanvasEdit()
    try Theme.FlashEdit(EdCanvas, true, 220)
    SaveIniAll()
    SetStatus("Added piece: " piece["label"], "ok")
    return true
}

ChipClick(piece, *) {
    if ChipDrag.ConsumeClick()
        return
    AddPieceToCanvas(piece)
}

OnChipDrop(piece) {
    global ActiveTab
    if ActiveTab != 2 {
        RequestTab(2)
    }
    if AddPieceToCanvas(piece)
        SetStatus("Dropped piece: " piece["label"])
}

OnChipDragHover(over) {
    global EdCanvas
    Theme.HighlightDropTarget(EdCanvas, over)
}

ChipDragCanStart() {
    global ActiveTab, BusyPuzzle, WipeActive
    return ActiveTab = 2 && !BusyPuzzle && !WipeActive
}

OnPuzzleClear(*) {
    global Canvas, EdCanvas, AppGui
    if Trim(EdCanvas.Value) != "" {
        if !Theme.ConfirmDark("Clear the command canvas?", "Clear canvas", AppGui.Hwnd)
            return
    }
    Canvas.Clear()
    EdCanvas.Value := ""
    RefreshCanvasEdit()
    SaveIniAll()
    SetStatus("Canvas cleared")
}

OnCanvasUndo(*) {
    global ActiveTab, Canvas, EdCanvas
    if ActiveTab != 2 {
        RequestTab(2)
        return
    }
    ; Prefer model backspace; fall back to text line pop
    lines := Canvas.LinesFromText(EdCanvas.Value)
    if Canvas.Count() != lines.Length
        Canvas.RebuildFromText(EdCanvas.Value)
    if Canvas.Backspace() {
        RefreshCanvasEdit()
        SaveIniAll()
        SetStatus("Undo — removed last canvas piece", "ok")
        return
    }
    if Trim(EdCanvas.Value) = "" {
        SetStatus("Canvas already empty")
        return
    }
    EdCanvas.Value := Canvas.BackspaceText(EdCanvas.Value)
    Canvas.RebuildFromText(EdCanvas.Value)
    SaveIniAll()
    SetStatus("Undo — removed last canvas line", "ok")
}

OnPuzzleBackspace(*) {
    global Canvas, ActiveTab, EdCanvas
    if ActiveTab != 2
        return
    ; Keep rows aligned with edit text (user may have typed)
    lines := Canvas.LinesFromText(EdCanvas.Value)
    if Canvas.Count() != lines.Length
        Canvas.RebuildFromText(EdCanvas.Value)
    if Canvas.Backspace() {
        RefreshCanvasEdit()
    } else {
        EdCanvas.Value := Canvas.BackspaceText(EdCanvas.Value)
    }
    SaveIniAll()
    SetStatus("Removed last piece / line")
}

OnPuzzleCopy(*) {
    global EdCanvas
    A_Clipboard := EdCanvas.Value
    SetStatus("Command copied to clipboard")
}

RefreshCanvasEdit() {
    global EdCanvas, Canvas
    EdCanvas.Value := Canvas.ToText()
}

OnPuzzleRun(*) {
    global EdCanvas, EdTerminal, Canvas, Catalog, RepoRoot
    global BusyPuzzle, PuzzleJob, BtnRun, BtnCancelPuzzle, ActiveTab, JobStartPuzzle, WipeActive

    if WipeActive {
        SetStatus("Wait for tab transition…")
        return
    }
    ; F5 is Tab2-only
    if ActiveTab != 2 {
        RequestTab(2)
        SetStatus("Switched to puzzle — press Run / F5")
        return
    }

    if BusyPuzzle {
        SetStatus("Puzzle already running… (Cancel run to abort)")
        return
    }

    text := EdCanvas.Value
    lines := Canvas.LinesFromText(text)
    if lines.Length = 0 {
        EdTerminal.Value := "ERROR: empty slots — drop a piece or type a command before Run.`n"
            . "Default: npx --no-install playwright test --project=chromium"
        SetStatus("Run blocked — empty canvas")
        return
    }

    if Catalog.BlockIncomplete() && Canvas.HasEmptySlotsInText(text) {
        EdTerminal.Value := "ERROR: incomplete slots detected (e.g. --grep= with no value, or codegen/open/screenshot/pdf/show-trace without required args).`n"
            . "Fill slots via chips or edit the canvas, then Run again."
        SetStatus("Run blocked — incomplete slots")
        return
    }

    if !FileExist(RepoRoot "\package.json") {
        EdTerminal.Value := "ERROR: package.json not found at repo root:`n" RepoRoot
        SetStatus("Run blocked — bad repo root")
        return
    }

    BusyPuzzle := true
    UpdateTrayTip()
    SetChipButtonsEnabled(false)
    try BtnRun.Enabled := false
    try BtnCancelPuzzle.Enabled := true
    EdTerminal.Value := "cwd: " RepoRoot "`n--- async run (stop on first nonzero) ---`n"
    JobStartPuzzle := A_TickCount
    SetStatus("Running from repo root…")
    PuzzleJob := ShellExec.StartCaptureLines(lines, RepoRoot)
    if PuzzleJob.done && InStr(PuzzleJob.output, "empty slots") {
        EdTerminal.Value := PuzzleJob.output
        BusyPuzzle := false
        SetChipButtonsEnabled(true)
        try BtnRun.Enabled := true
        try BtnCancelPuzzle.Enabled := false
        SetStatus("Run blocked")
        return
    }
    SetTimer(PollPuzzle, 150)
}

OnPuzzleCancel(*) {
    global PuzzleJob, EdTerminal, BusyPuzzle, BtnRun, BtnCancelPuzzle, RepoRoot
    if !BusyPuzzle || !IsObject(PuzzleJob) {
        BusyPuzzle := false
        try BtnRun.Enabled := true
        try BtnCancelPuzzle.Enabled := false
        return
    }
    SetTimer(PollPuzzle, 0)
    PuzzleJob.Cancel("CANCELLED — puzzle run stopped by user.")
    EdTerminal.Value := "cwd: " RepoRoot "`n" PuzzleJob.output
    BusyPuzzle := false
    UpdateTrayTip()
    SetChipButtonsEnabled(true)
    try BtnRun.Enabled := true
    try BtnCancelPuzzle.Enabled := false
    SetStatus("Puzzle run cancelled")
    PuzzleJob := ""
    SaveIniAll()
}

PollPuzzle() {
    global PuzzleJob, EdTerminal, BusyPuzzle, RepoRoot, BtnRun, BtnCancelPuzzle, JobStartPuzzle
    if !IsObject(PuzzleJob) {
        SetTimer(PollPuzzle, 0)
        return
    }
    live := "cwd: " RepoRoot "`n--- async run (stop on first nonzero) ---`n"
    if PuzzleJob.combined != ""
        live .= PuzzleJob.combined "`n`n"
    if !PuzzleJob.done
        live .= ">>> " PuzzleJob.cmd "`n" PuzzleJob.partial
    EdTerminal.Value := live
    ScrollEditToEnd(EdTerminal)
    if !PuzzleJob.done {
        elapsed := Round((A_TickCount - JobStartPuzzle) / 1000)
        SetStatus("Puzzle running… " elapsed "s  (Cancel run to abort)")
    }

    if !PuzzleJob.Poll()
        return

    SetTimer(PollPuzzle, 0)
    EdTerminal.Value := "cwd: " RepoRoot "`n" PuzzleJob.output
    ScrollEditToEnd(EdTerminal)
    code := PuzzleJob.exitCode
    BusyPuzzle := false
    UpdateTrayTip()
    SetChipButtonsEnabled(true)
    try BtnRun.Enabled := true
    try BtnCancelPuzzle.Enabled := false
    elapsed := Round((A_TickCount - JobStartPuzzle) / 1000)
    SetStatus((code = 0 ? "Puzzle run OK" : "Puzzle stopped — exit " code) "  (" elapsed "s)", code = 0 ? "ok" : "err")
    try TrayTip("Puzzle run", (code = 0 ? "OK" : "Stopped exit " code) " (" elapsed "s)", code = 0 ? "Iconi" : "Iconx")
    PuzzleJob := ""
    SaveIniAll()
}

; ---------- Ini persistence ----------

IniEscape(s) {
    s := StrReplace(s, "`r`n", "`n")
    s := StrReplace(s, "`r", "`n")
    ; literal backslash-n in text becomes double-escaped so real newlines can use \n
    s := StrReplace(s, "\n", "\\n")
    s := StrReplace(s, "`n", "\n")
    return s
}

IniUnescape(s) {
    ph := Chr(1)
    s := StrReplace(s, "\\n", ph)
    s := StrReplace(s, "\n", "`n")
    s := StrReplace(s, ph, "\n")
    return s
}

LoadIniAll() {
    global EdPrompt, EdReply, EdCanvas, EdTerminal, EdChipFilter, EdRecordInstr, EdRecordUrl, EdRecording, IniPath, ActiveTab, LastWinW, LastWinH, LastWinX, LastWinY, Canvas, RepoRoot, LastSavedSpec, BtnRunSavedTest
    if !FileExist(IniPath)
        return
    try {
        p := IniRead(IniPath, "Copilot", "LastPrompt", "")
        p := IniUnescape(p)
        if p != ""
            EdPrompt.Value := p
    }
    try {
        r := IniRead(IniPath, "Copilot", "LastReply", "")
        r := IniUnescape(r)
        if r != ""
            EdReply.Value := r
    }
    try {
        ri := IniRead(IniPath, "Record", "Instruction", "")
        ri := IniUnescape(ri)
        if ri != ""
            EdRecordInstr.Value := ri
        ru := IniRead(IniPath, "Record", "Url", "")
        if ru != ""
            EdRecordUrl.Value := ru
    }
    try {
        ; Prefill recording pane from disk if present
        spec := RecordSession.ReadLatest(RepoRoot)
        if spec != ""
            EdRecording.Value := spec
    }
    try {
        c := IniRead(IniPath, "Puzzle", "Canvas", "")
        c := IniUnescape(c)
        if Trim(c) != "" {
            EdCanvas.Value := c
            Canvas.RebuildFromText(c)
        }
    }
    try {
        t := IniRead(IniPath, "Puzzle", "LastTerminal", "")
        t := IniUnescape(t)
        if t != ""
            EdTerminal.Value := t
    }
    try {
        tab := Integer(IniRead(IniPath, "UI", "ActiveTab", "1"))
        if tab = 1 || tab = 2 || tab = 3
            ActiveTab := tab
    }
    try {
        w := Integer(IniRead(IniPath, "UI", "Width", "980"))
        h := Integer(IniRead(IniPath, "UI", "Height", "720"))
        if w >= 820 && h >= 600 {
            LastWinW := w
            LastWinH := h
        }
    }
    try {
        filt := IniRead(IniPath, "Puzzle", "ChipFilter", "")
        if filt != "" {
            EdChipFilter.Value := filt
        }
    }
    try {
        xs := IniRead(IniPath, "UI", "X", "")
        ys := IniRead(IniPath, "UI", "Y", "")
        if xs != "" && ys != "" {
            LastWinX := Integer(xs)
            LastWinY := Integer(ys)
        }
    }
    try {
        global LastSavedSpec, BtnRunSavedTest
        ls := IniRead(IniPath, "Record", "LastSavedSpec", "")
        if ls != "" && FileExist(ls) {
            LastSavedSpec := ls
            try BtnRunSavedTest.Enabled := true
        }
    }
    try {
        global EdDesktopInstr, EdDesktopJson, ChkStrictSpots, Desktop
        di := IniRead(IniPath, "Desktop", "Instruction", "")
        di := IniUnescape(di)
        if di != ""
            EdDesktopInstr.Value := di
        ss := IniRead(IniPath, "Desktop", "StrictSpots", "1")
        try ChkStrictSpots.Value := (ss = "0") ? 0 : 1
        try Desktop.strictSpots := !!ChkStrictSpots.Value
        sj := IniRead(IniPath, "Desktop", "StepsJson", "")
        sj := IniUnescape(sj)
        if Trim(sj) != "" {
            EdDesktopJson.Value := sj
            try Desktop.LoadJson(sj)
            RefreshDesktopStepList()
        }
    }
}

SaveIniAll() {
    global EdPrompt, EdReply, EdCanvas, EdTerminal, EdChipFilter, EdRecordInstr, EdRecordUrl, IniPath, ActiveTab, LastWinW, LastWinH, LastWinX, LastWinY, AppGui, LastSavedSpec
    try {
        IniWrite(IniEscape(EdPrompt.Value), IniPath, "Copilot", "LastPrompt")
        try {
            reply := EdReply.Value
            if StrLen(reply) > 48000
                reply := SubStr(reply, -47999)
            IniWrite(IniEscape(reply), IniPath, "Copilot", "LastReply")
        }
        try IniWrite(IniEscape(EdRecordInstr.Value), IniPath, "Record", "Instruction")
        try IniWrite(EdRecordUrl.Value, IniPath, "Record", "Url")
        try {
            if LastSavedSpec != ""
                IniWrite(LastSavedSpec, IniPath, "Record", "LastSavedSpec")
        }
        IniWrite(IniEscape(EdCanvas.Value), IniPath, "Puzzle", "Canvas")
        try IniWrite(EdChipFilter.Value, IniPath, "Puzzle", "ChipFilter")
        ; Cap terminal snippet so ini stays modest (~48 KB chars)
        term := EdTerminal.Value
        if StrLen(term) > 48000
            term := SubStr(term, -47999)
        IniWrite(IniEscape(term), IniPath, "Puzzle", "LastTerminal")
        IniWrite(ActiveTab, IniPath, "UI", "ActiveTab")
        IniWrite(LastWinW, IniPath, "UI", "Width")
        IniWrite(LastWinH, IniPath, "UI", "Height")
        try {
            WinGetPos(&wx, &wy, , , "ahk_id " AppGui.Hwnd)
            if wx != "" {
                LastWinX := wx
                LastWinY := wy
                IniWrite(wx, IniPath, "UI", "X")
                IniWrite(wy, IniPath, "UI", "Y")
            }
        }
        try {
            global EdDesktopInstr, EdDesktopJson, ChkStrictSpots
            IniWrite(IniEscape(EdDesktopInstr.Value), IniPath, "Desktop", "Instruction")
            IniWrite(ChkStrictSpots.Value ? "1" : "0", IniPath, "Desktop", "StrictSpots")
            sj := EdDesktopJson.Value
            if StrLen(sj) > 48000
                sj := SubStr(sj, 1, 48000)
            IniWrite(IniEscape(sj), IniPath, "Desktop", "StepsJson")
        }
    }
}

OnFocusChipFilter(*) {
    global ActiveTab, EdChipFilter
    if ActiveTab != 2
        RequestTab(2)
    try EdChipFilter.Focus()
    SetStatus("Filter focused (F6)")
}

OnFocusCanvas(*) {
    global ActiveTab, EdCanvas
    if ActiveTab != 2
        RequestTab(2)
    try EdCanvas.Focus()
    SetStatus("Canvas focused (F7)")
}

OnClearChipFilter(*) {
    global EdChipFilter, ActiveTab
    if ActiveTab != 2 {
        RequestTab(2)
    }
    EdChipFilter.Value := ""
    OnChipFilterChange()
    SetStatus("Pieces filter cleared", "ok")
}

OnChipFilterChange(*) {
    global ChipBtns, EdChipFilter, ActiveTab, LblNoChipMatch
    if ActiveTab != 2
        return
    q := StrLower(Trim(EdChipFilter.Value))
    shown := 0
    for item in ChipBtns {
        match := (q = "") || InStr(StrLower(item.label), q)
        try item.btn.Visible := match
        if match
            shown += 1
    }
    try {
        if q != "" && shown = 0
            LblNoChipMatch.Value := "No matching pieces"
        else
            LblNoChipMatch.Value := ""
    }
    ; Debounce status spam while typing
    global ChipFilterShown
    ChipFilterShown := shown
    SetTimer(ChipFilterStatusTick, -280)
}

ChipFilterStatusTick() {
    global EdChipFilter, ChipFilterShown
    q := StrLower(Trim(EdChipFilter.Value))
    SetStatus(q = "" ? "Pieces filter cleared" : "Filter '" q "' — " ChipFilterShown " visible")
}

OnCopyTerminal(*) {
    global EdTerminal
    A_Clipboard := EdTerminal.Value
    SetStatus("Terminal output copied to clipboard")
}

OnClearTerminal(*) {
    global EdTerminal
    EdTerminal.Value := ""
    SaveIniAll()
    SetStatus("Terminal cleared")
}

OnOpenRepoFolder(*) {
    global RepoRoot
    if !DirExist(RepoRoot) {
        SetStatus("Repo root missing: " RepoRoot)
        return
    }
    Run('explorer.exe "' RepoRoot '"')
    SetStatus("Opened repo folder")
}


; ---------- Record → file → Copilot ----------

OnRecordStart(*) {
    global RepoRoot, EdRecordUrl, BusyRecord, RecordJob, BtnRecord, BtnCancelRecord, EdRecording, ActiveTab, BusyCopilot
    if ActiveTab != 1 {
        RequestTab(1)
    }
    if BusyRecord {
        SetStatus("Recording already in progress… (close codegen to finish)")
        return
    }
    if BusyCopilot {
        SetStatus("Copilot is busy — finish or Cancel before recording")
        return
    }
    url := Trim(EdRecordUrl.Value)
    try {
        RecordJob := RecordSession.StartRecord(RepoRoot, url)
    } catch as e {
        SetStatus("Record failed to start: " e.Message)
        try TrayTip("Record", e.Message, "Iconx")
        return
    }
    BusyRecord := true
    UpdateTrayTip()
    try BtnRecord.Enabled := false
    try BtnCancelRecord.Enabled := true
    archMsg := RecordJob.archived != "" ? " (archived prior latest)" : ""
    via := RecordJob.usedNpm ? "npm run codegen:record" : "npx playwright codegen"
    EdRecording.Value := "; Recording in progress via " via "…`n; Close the Playwright Inspector / codegen window when done.`n; Waiting for process EXIT (no mid-session poll)."
    SetStatus("Recording started" archMsg " — close codegen when done…")
    try TrayTip("Record", "Headed codegen started — close the window when finished", "Iconi")
    SetTimer(PollRecordExit, 500)
}

OnRecordCancel(*) {
    global RecordJob, BusyRecord, BtnRecord, BtnCancelRecord
    SetTimer(PollRecordExit, 0)
    if IsObject(RecordJob) && RecordJob.HasProp("pid") && RecordJob.pid {
        try ProcessClose(RecordJob.pid)
    }
    BusyRecord := false
    RecordJob := ""
    try BtnRecord.Enabled := true
    try BtnCancelRecord.Enabled := false
    UpdateTrayTip()
}

OnRecordCancelClick(*) {
    global BusyRecord, EdRecording
    if !BusyRecord {
        SetStatus("No recording in progress")
        return
    }
    OnRecordCancel()
    EdRecording.Value := "; Recording cancelled — codegen process closed."
    SetStatus("Recording cancelled", "err")
    try TrayTip("Record", "Cancelled", "Iconx")
}

PollRecordExit() {
    global RecordJob, BusyRecord, BtnRecord, BtnCancelRecord, EdRecording, RepoRoot
    if !IsObject(RecordJob) {
        SetTimer(PollRecordExit, 0)
        BusyRecord := false
        try BtnRecord.Enabled := true
        try BtnCancelRecord.Enabled := false
        return
    }
    ; Wait for EXIT only — do not read codegen stdout mid-session
    if ProcessExist(RecordJob.pid) {
        SetStatus("Recording… waiting for codegen EXIT (pid " RecordJob.pid ")")
        return
    }
    SetTimer(PollRecordExit, 0)
    BusyRecord := false
    try BtnRecord.Enabled := true
    try BtnCancelRecord.Enabled := false
    UpdateTrayTip()
    spec := RecordSession.ReadLatest(RepoRoot)
    if spec = "" {
        EdRecording.Value := "; codegen exited but recordings\\latest.spec.js is missing or empty."
        SetStatus("Record finished — no latest.spec.js (aborted?)")
        try TrayTip("Record", "No latest.spec.js — recording aborted?", "Iconx")
    } else {
        EdRecording.Value := spec
        sz := 0
        try sz := FileGetSize(RecordSession.LatestPath(RepoRoot))
        SetStatus("Record finished — loaded latest.spec.js (" sz " bytes)")
        try TrayTip("Record", "Loaded latest.spec.js (" sz " bytes)", "Iconi")
    }
    RecordJob := ""
    SaveIniAll()
}

OnSendRecordingToCopilot(*) {
    global RepoRoot, EdRecording, EdRecordInstr, EdPrompt, EdReply, ActiveTab
    global BusyCopilot, BusyRecord, BtnSaveAsTest
    if BusyRecord {
        SetStatus("Still recording — wait for codegen EXIT first")
        return
    }
    if BusyCopilot {
        SetStatus("Copilot already running…")
        return
    }
    if !RecordSession.LatestIsSendable(RepoRoot) {
        msg := "Send blocked — recordings\\latest.spec.js missing or under ~20 bytes (aborted recorder)."
        SetStatus(msg)
        try TrayTip("Send recording", "not sendable — missing/tiny latest.spec.js", "Iconx")
        return
    }
    ; Refresh pane from disk (source of truth)
    spec := RecordSession.ReadLatest(RepoRoot)
    if Trim(spec) = "" {
        SetStatus("Send blocked — latest.spec.js empty")
        try TrayTip("Send recording", "latest.spec.js empty", "Iconx")
        return
    }
    EdRecording.Value := spec
    prompt := RecordSession.BuildCopilotPrompt(spec, EdRecordInstr.Value)
    EdPrompt.Value := prompt
    try BtnSaveAsTest.Enabled := false
    ; Force Tab 1 immediately (avoid train-wipe race before Send)
    ShowTab(1, true)
    SaveIniAll()
    SetStatus("Recording prompt loaded — sending to Copilot…")
    OnCopilotSend()
}

OnSaveAsTest(*) {
    global RepoRoot, EdReply, BtnRunSavedTest, LastSavedSpec
    raw := EdReply.Value
    ; Boundary: never treat Tab3 desktop UIA / AHK seed as a Playwright test
    if InStr(raw, '"kind": "windows-uia"') || InStr(raw, "windows-uia") || InStr(raw, "UI Automation desktop steps") {
        SetStatus("Save as test blocked — desktop UIA is not Playwright", "err")
        try TrayTip("Save as test", "desktop UIA / AHK seed — not a Playwright test", "Iconx")
        return
    }
    body := RecordSession.StripMarkdownFences(raw)
    if !RecordSession.LooksLikePlaywrightTest(body) {
        SetStatus("not a runnable test")
        try TrayTip("Save as test", "not a runnable test — need test( + @playwright/test import", "Iconx")
        return
    }
    path := RecordSession.SaveAsTest(RepoRoot, raw)
    if path = "" {
        SetStatus("not a runnable test")
        try TrayTip("Save as test", "not a runnable test", "Iconx")
        return
    }
    LastSavedSpec := path
    try BtnRunSavedTest.Enabled := true
    ; Show stripped body in reply for clarity
    EdReply.Value := body
    SetStatus("Saved test: " path)
    try TrayTip("Save as test", path, "Iconi")
}

OnRunSavedTest(*) {
    global RepoRoot, LastSavedSpec, ActiveTab, EdCanvas, Canvas, BusyPuzzle
    if LastSavedSpec = "" || !FileExist(LastSavedSpec) {
        SetStatus("No saved recorded test to run")
        try TrayTip("Run saved test", "Save as test first", "Iconx")
        return
    }
    if BusyPuzzle {
        SetStatus("Puzzle already running…")
        return
    }
    cmd := RecordSession.BuildTestCommand(LastSavedSpec, RepoRoot)
    ; Put on canvas and run via existing puzzle pipeline
    Canvas.Clear()
    Canvas.RebuildFromText(cmd)
    EdCanvas.Value := cmd
    if ActiveTab != 2
        RequestTab(2)
    SaveIniAll()
    SetStatus("Running saved recorded test…")
    OnPuzzleRun()
}



OnEditLatestSpec(*) {
    global RepoRoot
    latest := RecordSession.LatestPath(RepoRoot)
    if !FileExist(latest) {
        SetStatus("No latest.spec.js to edit", "err")
        try TrayTip("Edit latest", "missing recordings\latest.spec.js", "Iconx")
        return
    }
    try Run('notepad.exe "' latest '"')
    catch {
        Run('"' latest '"')
    }
    SetStatus("Opened latest.spec.js in editor")
}

OnCopyRecording(*) {
    global EdRecording
    A_Clipboard := EdRecording.Value
    SetStatus("Recording spec copied to clipboard", "ok")
}

OnReloadLatestSpec(*) {
    global RepoRoot, EdRecording, BusyRecord
    if BusyRecord {
        SetStatus("Still recording — wait for codegen EXIT")
        return
    }
    spec := RecordSession.ReadLatest(RepoRoot)
    if spec = "" {
        EdRecording.Value := "; recordings\latest.spec.js missing or empty."
        SetStatus("Reload — no latest.spec.js")
        try TrayTip("Reload latest", "missing or empty", "Iconx")
        return
    }
    EdRecording.Value := spec
    sz := 0
    try sz := FileGetSize(RecordSession.LatestPath(RepoRoot))
    SetStatus("Reloaded latest.spec.js (" sz " bytes)")
}

OnOpenRecordingsFolder(*) {
    global RepoRoot
    dir := RepoRoot "\recordings"
    try RecordSession.EnsureDirs(RepoRoot)
    if !DirExist(dir) {
        SetStatus("recordings folder missing")
        return
    }
    Run('explorer.exe "' dir '"')
    SetStatus("Opened recordings folder")
}


OnStatusBarClick(*) {
    global StatusBar
    try {
        msg := Trim(StatusBar.Value)
        if msg = ""
            return
        A_Clipboard := msg
        ; brief acknowledge without clobbering for long
        ToolTip("Status copied")
        SetTimer(() => ToolTip(), -900)
    }
}

ScrollEditToEnd(ctrl) {
    if !IsObject(ctrl)
        return
    try {
        ; EM_SETSEL = 0xB1 — move caret to end; EM_SCROLLCARET = 0xB7
        SendMessage(0xB1, -1, -1, ctrl)
        SendMessage(0xB7, 0, 0, ctrl)
    }
}


; ---------- Tab 3 — Windows Desktop UIA (NOT Playwright) ----------

OnStrictSpotsToggle(*) {
    global Desktop, ChkStrictSpots
    Desktop.strictSpots := !!ChkStrictSpots.Value
    SaveIniAll()
    SetStatus(Desktop.strictSpots ? "Strict fullscreen spots ON (client-% checksums)" : "Strict fullscreen spots OFF", "ok")
}


DesktopStatusCb(msg, tone := "") {
    SetStatus(msg, tone)
}

OnDesktopStepCaptured(step) {
    global Desktop, EdDesktopJson
    try EdDesktopJson.Value := Desktop.ToJson()
    RefreshDesktopStepList()
}

; Select step index in Tab3 ListBox during Play/Verify (and leave fail selected).
OnDesktopPlayIndex(index) {
    global LbDesktopSteps, Desktop
    if !IsObject(LbDesktopSteps)
        return
    try {
        idx := Integer(index)
        if idx >= 1 && idx <= Desktop.steps.Length
            LbDesktopSteps.Choose(idx)
    }
}

HighlightDesktopStep(failedAt, ok := true) {
    global LbDesktopSteps, Desktop
    if !IsObject(LbDesktopSteps)
        return
    try {
        if !ok && Integer(failedAt) >= 1
            LbDesktopSteps.Choose(Integer(failedAt))
        else if ok && Desktop.steps.Length
            LbDesktopSteps.Choose(Desktop.steps.Length)
    }
}

OnDesktopRecord(*) {
    global Desktop, ActiveTab, BtnDeskRecord, BtnDeskStop, BusyDesktop, WipeActive, BusyRecord, BusyPuzzle, ChkStrictSpots
    if WipeActive
        return
    if ActiveTab != 3
        RequestTab(3)
    if BusyRecord {
        SetStatus("Browser Record busy — finish Tab1 codegen first", "err")
        return
    }
    try Desktop.strictSpots := !!ChkStrictSpots.Value
    if !Desktop.StartRecord()
        return
    BusyDesktop := true
    try BtnDeskRecord.Enabled := false
    try BtnDeskStop.Enabled := true
    UpdateTrayTip()
}

OnDesktopStop(*) {
    global Desktop, BtnDeskRecord, BtnDeskStop, BusyDesktop, EdDesktopJson, EdDesktopLog
    Desktop.StopRecord()
    BusyDesktop := false
    try BtnDeskRecord.Enabled := true
    try BtnDeskStop.Enabled := false
    try EdDesktopJson.Value := Desktop.ToJson()
    RefreshDesktopStepList()
    ; Summarize ranked strategies captured
    try {
        summary := "Recorded " Desktop.Count() " steps:`n"
        for i, step in Desktop.steps {
            summary .= "#" i " " Desktop.StepLabel(step)
            if step.Has("targets") {
                summary .= " ["
                for j, tg in step["targets"] {
                    if j > 1
                        summary .= ", "
                    summary .= (tg.Has("strategy") ? tg["strategy"] : "?")
                }
                summary .= "]"
            }
            summary .= "`n"
        }
        EdDesktopLog.Value := summary
    }
    UpdateTrayTip()
    SaveIniAll()
}

OnDesktopPlay(*) {
    global Desktop, EdDesktopJson, EdDesktopLog, ActiveTab, BusyDesktop, ChkStrictSpots
    if ActiveTab != 3
        RequestTab(3)
    if BusyDesktop || Desktop.recording {
        SetStatus("Stop desktop recording before Play", "err")
        return
    }
    try Desktop.strictSpots := !!ChkStrictSpots.Value
    if !Desktop.LoadFromEdit(EdDesktopJson.Value)
        return
    RefreshDesktopStepList()
    ; Keep UI toggle authoritative for this run
    try Desktop.strictSpots := !!ChkStrictSpots.Value
    res := Desktop.Play(false)
    EdDesktopLog.Value := res.log
    ScrollEditToEnd(EdDesktopLog)
    HighlightDesktopStep(res.HasProp("failedAt") ? res.failedAt : 0, res.ok)
}

OnDesktopVerify(*) {
    global Desktop, EdDesktopJson, EdDesktopLog, ActiveTab, BusyDesktop, ChkStrictSpots
    if ActiveTab != 3
        RequestTab(3)
    if BusyDesktop || Desktop.recording {
        SetStatus("Stop desktop recording before Verify", "err")
        return
    }
    try Desktop.strictSpots := !!ChkStrictSpots.Value
    if !Desktop.LoadFromEdit(EdDesktopJson.Value)
        return
    RefreshDesktopStepList()
    try Desktop.strictSpots := !!ChkStrictSpots.Value
    res := Desktop.Verify()
    EdDesktopLog.Value := res.log
    ScrollEditToEnd(EdDesktopLog)
    HighlightDesktopStep(res.HasProp("failedAt") ? res.failedAt : 0, res.ok)
}

OnDesktopSave(*) {
    global Desktop, EdDesktopJson, RepoRoot
    if Trim(EdDesktopJson.Value) != ""
        Desktop.LoadFromEdit(EdDesktopJson.Value)
    path := Desktop.Save(RepoRoot)
    if path != ""
        try TrayTip("Desktop UIA", "Saved`n" path, "Iconi")
}

OnDesktopCopyJson(*) {
    global EdDesktopJson, ActiveTab, Desktop
    if ActiveTab != 3
        RequestTab(3)
    try {
        if Trim(EdDesktopJson.Value) = "" && Desktop.Count()
            EdDesktopJson.Value := Desktop.ToJson()
        A_Clipboard := EdDesktopJson.Value
        SetStatus("Desktop UIA JSON copied (Ctrl+Shift+J)", "ok")
    }
}

OnDesktopOpenFolder(*) {
    global RepoRoot
    dir := DesktopRecord.Dir(RepoRoot)
    DesktopRecord.EnsureDirs(RepoRoot)
    Run('explorer.exe "' dir '"')
    SetStatus("Opened recordings\windows")
}

OnDesktopLoadLatest(*) {
    global Desktop, EdDesktopJson, RepoRoot, ActiveTab
    if ActiveTab != 3
        RequestTab(3)
    path := Desktop.LoadLatest(RepoRoot)
    if path = "" {
        SetStatus("No desktop-*.json in recordings\windows", "err")
        return
    }
    EdDesktopJson.Value := Desktop.ToJson()
    try ChkStrictSpots.Value := Desktop.strictSpots ? 1 : 0
    RefreshDesktopStepList()
    SetStatus("Loaded " path, "ok")
}

OnDesktopProbe(*) {
    global Desktop, EdDesktopLog, ChkStrictSpots
    desc := Desktop.ProbeUnderCursor()
    if desc = ""
        return
    ; Show ranked targets in log for QC
    try {
        lines := "PROBE ranked targets:`n"
        if desc.Has("Targets") {
            for t in desc["Targets"] {
                strat := t.Has("strategy") ? t["strategy"] : "?"
                lines .= "  rank " (t.Has("rank") ? t["rank"] : "?") " — " strat
                if t.Has("AutomationId")
                    lines .= " id=" t["AutomationId"]
                if t.Has("Name")
                    lines .= " name=" t["Name"]
                lines .= "`n"
            }
        }
        win := desc.Has("Window") ? desc["Window"] : Map()
        lines .= "window class=" (win.Has("Class") ? win["Class"] : "") " proc=" (win.Has("ProcessName") ? win["ProcessName"] : "") "`n"
        ; Optional Strict spots preview (client-% only)
        hwnd := win.Has("Hwnd") ? Integer(win["Hwnd"]) : 0
        if hwnd && (!IsObject(ChkStrictSpots) || ChkStrictSpots.Value) {
            pack := ScreenSpots.CapturePack(hwnd, ScreenSpots.IsProbablyFullscreen(hwnd))
            lines .= "display " pack["display"]["screenW"] "x" pack["display"]["screenH"] " dpi=" pack["display"]["dpi"] " mons=" pack["display"]["monitors"] "`n"
            lines .= "spots settle=" (pack.Has("settleOk") && pack["settleOk"] ? "ok" : "FAIL") " count=" pack["spots"].Length " (client-%)`n"
            for i, s in pack["spots"] {
                if i > 3
                    break
                lines .= "  #" i " (" Round(s["rx"]*100) "%," Round(s["ry"]*100) "%) rgb=" s["rgb"] "`n"
            }
        }
        EdDesktopLog.Value := lines
    }
}

OnDesktopClear(*) {
    global Desktop, EdDesktopJson, EdDesktopLog, AppGui
    if Desktop.Count() || Trim(EdDesktopJson.Value) != "" {
        if !Theme.ConfirmDark("Clear all desktop UIA steps?", "Clear desktop steps", AppGui.Hwnd)
            return
    }
    Desktop.Clear()
    EdDesktopJson.Value := ""
    EdDesktopLog.Value := ""
    RefreshDesktopStepList()
    SaveIniAll()
    SetStatus("Desktop steps cleared", "ok")
}

OnDesktopSendToCopilot(*) {
    global Desktop, EdDesktopJson, EdDesktopInstr, EdPrompt, ActiveTab, BusyCopilot, BusyDesktop
    ; Boundary: desktop → Copilot only. NEVER Playwright seed / Save as test path.
    if BusyDesktop || Desktop.recording {
        SetStatus("Stop desktop recording before Send", "err")
        return
    }
    if BusyCopilot {
        SetStatus("Copilot already running…", "err")
        return
    }
    if Trim(EdDesktopJson.Value) != "" {
        if !Desktop.LoadFromEdit(EdDesktopJson.Value)
            return
    }
    if Desktop.Count() = 0 {
        SetStatus("No desktop UIA steps to send", "err")
        return
    }
    prompt := Desktop.BuildCopilotPrompt(EdDesktopInstr.Value)
    EdPrompt.Value := prompt
    ShowTab(1, true)
    SaveIniAll()
    SetStatus("Desktop UIA prompt loaded (AHK seed — not Playwright) — sending…", "ok")
    OnCopilotSend()
}



RefreshDesktopStepList() {
    global Desktop, LbDesktopSteps
    if !IsObject(LbDesktopSteps)
        return
    try {
        sel := LbDesktopSteps.Value
        LbDesktopSteps.Delete()
        for i, step in Desktop.steps {
            LbDesktopSteps.Add([Desktop.StepListLine(i, step)])
        }
        if sel != "" && sel >= 1 && sel <= Desktop.steps.Length
            LbDesktopSteps.Choose(sel)
        else if Desktop.steps.Length
            LbDesktopSteps.Choose(Desktop.steps.Length)
    }
}

SyncDesktopFromJsonOrList() {
    global Desktop, EdDesktopJson
    if Trim(EdDesktopJson.Value) != ""
        Desktop.LoadFromEdit(EdDesktopJson.Value)
}

OnDesktopStepDelete(*) {
    global Desktop, EdDesktopJson, LbDesktopSteps
    if Desktop.recording {
        SetStatus("Stop recording before editing steps", "err")
        return
    }
    SyncDesktopFromJsonOrList()
    sel := 0
    try sel := Integer(LbDesktopSteps.Value)
    if sel < 1 || sel > Desktop.steps.Length {
        SetStatus("Select a step to delete", "err")
        return
    }
    if !Desktop.DeleteStep(sel) {
        SetStatus("Delete failed", "err")
        return
    }
    EdDesktopJson.Value := Desktop.ToJson()
    RefreshDesktopStepList()
    SaveIniAll()
    SetStatus("Deleted step #" sel, "ok")
}

OnDesktopStepUp(*) {
    global Desktop, EdDesktopJson, LbDesktopSteps
    if Desktop.recording {
        SetStatus("Stop recording before editing steps", "err")
        return
    }
    SyncDesktopFromJsonOrList()
    sel := 0
    try sel := Integer(LbDesktopSteps.Value)
    if sel < 2 {
        SetStatus("Cannot move further up", "err")
        return
    }
    if !Desktop.MoveStep(sel, -1)
        return
    EdDesktopJson.Value := Desktop.ToJson()
    RefreshDesktopStepList()
    try LbDesktopSteps.Choose(sel - 1)
    SaveIniAll()
    SetStatus("Moved step #" sel " up", "ok")
}

OnDesktopStepDown(*) {
    global Desktop, EdDesktopJson, LbDesktopSteps
    if Desktop.recording {
        SetStatus("Stop recording before editing steps", "err")
        return
    }
    SyncDesktopFromJsonOrList()
    sel := 0
    try sel := Integer(LbDesktopSteps.Value)
    if sel < 1 || sel >= Desktop.steps.Length {
        SetStatus("Cannot move further down", "err")
        return
    }
    if !Desktop.MoveStep(sel, 1)
        return
    EdDesktopJson.Value := Desktop.ToJson()
    RefreshDesktopStepList()
    try LbDesktopSteps.Choose(sel + 1)
    SaveIniAll()
    SetStatus("Moved step #" sel " down", "ok")
}

OnDesktopStepDup(*) {
    global Desktop, EdDesktopJson, LbDesktopSteps
    if Desktop.recording {
        SetStatus("Stop recording before editing steps", "err")
        return
    }
    SyncDesktopFromJsonOrList()
    sel := 0
    try sel := Integer(LbDesktopSteps.Value)
    if sel < 1 || sel > Desktop.steps.Length {
        SetStatus("Select a step to duplicate", "err")
        return
    }
    newIdx := Desktop.DuplicateStep(sel)
    if newIdx < 1 {
        SetStatus("Duplicate failed", "err")
        return
    }
    EdDesktopJson.Value := Desktop.ToJson()
    RefreshDesktopStepList()
    try LbDesktopSteps.Choose(newIdx)
    SaveIniAll()
    SetStatus("Duplicated step #" sel " → #" newIdx, "ok")
}

OnDesktopStepWait(*) {
    global Desktop, EdDesktopJson, LbDesktopSteps
    if Desktop.recording {
        SetStatus("Stop recording before inserting wait", "err")
        return
    }
    SyncDesktopFromJsonOrList()
    sel := 0
    try sel := Integer(LbDesktopSteps.Value)
    ms := DesktopRecord.DefaultWaitMs
    try {
        ib := InputBox("Wait duration in milliseconds (0–60000). Inserts after the selected step, or appends if none selected.", "Insert wait step", "w420 h160", String(ms))
        if ib.Result = "Cancel"
            return
        ms := Integer(Trim(ib.Value))
    } catch {
        ; keep default
    }
    newIdx := Desktop.InsertWait(ms, sel)
    if newIdx < 1 {
        SetStatus("Wait insert failed", "err")
        return
    }
    EdDesktopJson.Value := Desktop.ToJson()
    RefreshDesktopStepList()
    try LbDesktopSteps.Choose(newIdx)
    SaveIniAll()
    SetStatus("Inserted wait " ms "ms as step #" newIdx, "ok")
}

SetStatus(msg, tone := "") {
    global StatusBar
    try {
        StatusBar.Value := " " msg
        Theme.StyleStatusTone(StatusBar, tone)
        if tone != ""
            SetTimer(() => Theme.StyleStatusTone(StatusBar, ""), -3500)
    }
}
