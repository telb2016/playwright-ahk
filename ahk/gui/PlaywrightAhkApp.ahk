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
#Include ..\Playwright.ahk

global AppGui, StatusBar
global RepoRoot
global EdPrompt, EdReply, BtnSend, BtnCancelCopilot, BtnUseReply
global EdRecording, EdRecordUrl, EdRecordInstr, BtnRecord, BtnSendRecording
global BtnSaveAsTest, BtnRunSavedTest, LblRecording
global BtnReloadLatest, BtnOpenRec
global RecordJob, BusyRecord, LastSavedSpec
global EdCanvas, EdTerminal, BtnRun, BtnCancelPuzzle
global Catalog, Canvas
global CopilotJob, PuzzleJob
global IniPath
global BusyCopilot, BusyPuzzle
global ActiveTab, BtnTab1, BtnTab2
global Tab1Ctrls, Tab2Ctrls
global WipeGui, WipeLbl, WipeActive, WipeDir, WipeStep, WipeTarget
global LastWinW, LastWinH, LastWinX, LastWinY
global AppVisible
global ChipBtns, EdChipFilter
global JobStartCopilot, JobStartPuzzle

CopilotJob := ""
PuzzleJob := ""
BusyCopilot := false
BusyPuzzle := false
ActiveTab := 1
Tab1Ctrls := []
Tab2Ctrls := []
WipeActive := false
WipeDir := 1
WipeStep := 0
WipeTarget := 1
LastWinW := 1180
LastWinH := 720
LastWinX := ""
LastWinY := ""
AppVisible := true
ChipBtns := []
JobStartCopilot := 0
JobStartPuzzle := 0
RecordJob := ""
BusyRecord := false
LastSavedSpec := ""

RepoRoot := ShellExec.ResolveRepoRoot(A_ScriptFullPath)
try RecordSession.EnsureDirs(RepoRoot)
IniPath := A_ScriptDir "\PlaywrightAhkApp.ini"
Catalog := PuzzlePieces.Load(RepoRoot)
Canvas := PuzzleCanvas(Catalog)

SetupTray()
BuildGui()
Theme.ApplyDarkTitleBar(AppGui.Hwnd)
ChipDrag.SetOwner(AppGui.Hwnd)
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
    A_TrayMenu.Add()
    A_TrayMenu.Add("Save now`tCtrl+S", (*) => (SaveIniAll(), TrayTip("Saved", "Prompt/canvas/terminal persisted", "Iconi")))
    A_TrayMenu.Add("Cancel busy jobs", OnTrayCancelJobs)
    A_TrayMenu.Add()
    A_TrayMenu.Add("E&xit", OnTrayExit)
    A_TrayMenu.Default := "&Show / Focus`tCtrl+Alt+P"
    A_TrayMenu.ClickCount := 1
}

OnTrayCancelJobs(*) {
    global BusyCopilot, BusyPuzzle, BusyRecord
    any := BusyCopilot || BusyPuzzle || BusyRecord
    OnCopilotCancel()
    OnPuzzleCancel()
    OnRecordCancel()
    UpdateTrayTip()
    TrayTip("Playwright AHK", any ? "Busy jobs cancelled" : "No busy jobs", "Iconi")
}

UpdateTrayTip() {
    global BusyCopilot, BusyPuzzle, BusyRecord, AppVisible
    bits := []
    if BusyCopilot
        bits.Push("Copilot…")
    if BusyPuzzle
        bits.Push("Puzzle…")
    if BusyRecord
        bits.Push("Record…")
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
    SaveIniAll()
    OnCopilotCancel()
    OnPuzzleCancel()
    OnRecordCancel()
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
    global AppGui, AppVisible
    ChipDrag.Cancel()
    SaveIniAll()
    AppVisible := false
    try AppGui.Hide()
    UpdateTrayTip()
    TrayTip("Playwright AHK", "Hidden to tray — Ctrl+Alt+P to restore", "Iconi")
}

BuildGui() {
    global AppGui, StatusBar
    global EdPrompt, EdReply, BtnSend, BtnCancelCopilot, BtnUseReply
    global EdRecording, EdRecordUrl, EdRecordInstr, BtnRecord, BtnSendRecording
    global BtnSaveAsTest, BtnRunSavedTest, LblRecording
    global BtnReloadLatest, BtnOpenRec
    global RecordJob, BusyRecord, LastSavedSpec
    global EdCanvas, EdTerminal, BtnRun, BtnCancelPuzzle
    global Catalog, Tab1Ctrls, Tab2Ctrls, ChipBtns, EdChipFilter
    global BtnTab1, BtnTab2, WipeGui, WipeLbl

    AppGui := Gui("+Resize +MinSize1000x640", "Playwright AHK — Overnight GUI")
    Theme.StyleGui(AppGui)
    AppGui.OnEvent("Close", OnAppClose)
    AppGui.OnEvent("Escape", OnEsc)
    AppGui.OnEvent("Size", OnResize)

    ; Custom tab strip (replaces raw Tab3 blink — train wipe on switch)
    BtnTab1 := AppGui.Add("Button", "x10 y10 w230 h34", "Copilot prompt studio")
    Theme.StyleTabBtn(BtnTab1, true)
    BtnTab1.OnEvent("Click", (*) => RequestTab(1))

    BtnTab2 := AppGui.Add("Button", "x250 y10 w230 h34", "Playwright CLI puzzle")
    Theme.StyleTabBtn(BtnTab2, false)
    BtnTab2.OnEvent("Click", (*) => RequestTab(2))

    AppGui.Add("Text", "x490 y18 w470 c" Theme.FgDim,
        "Ctrl+1/2 tabs · Ctrl+Alt+P tray · Ctrl+S save · Ctrl+Enter Send · F5 Run")

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

    BtnRecord := AppGui.Add("Button", "x" rightX " y138 w" rightW " h32", "Record (headed codegen)")
    Theme.StyleButton(BtnRecord, true)
    BtnRecord.OnEvent("Click", OnRecordStart)

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

    BtnReloadLatest := AppGui.Add("Button", "x" rightX " y566 w" (rightW // 2 - 4) " h26", "Reload latest")
    Theme.StyleButton(BtnReloadLatest)
    BtnReloadLatest.OnEvent("Click", OnReloadLatestSpec)
    BtnOpenRec := AppGui.Add("Button", "x" (rightX + rightW // 2 + 4) " y566 w" (rightW // 2 - 4) " h26", "Open recordings")
    Theme.StyleButton(BtnOpenRec)
    BtnOpenRec.OnEvent("Click", OnOpenRecordingsFolder)

    Tab1Ctrls := [t1Hint, t1PromptLbl, EdPrompt, BtnSend, BtnCancelCopilot, BtnClearReply
        , BtnUseReply, BtnSavePrompt, t1ReplyLbl, EdReply
        , LblRecording, t1RecHint, t1UrlLbl, EdRecordUrl, BtnRecord, t1SpecLbl, EdRecording
        , t1InstrLbl, EdRecordInstr, BtnSendRecording, BtnSaveAsTest, BtnRunSavedTest
        , BtnReloadLatest, BtnOpenRec]

    ; ----- Tab 2 content -----
    t2Hint := AppGui.Add("Text", "x24 y56 w900 c" Theme.FgDim,
        "Drag chips onto the canvas (or click to add). Slots open a dark editor. Empty/incomplete slots block Run.")
    t2PiecesLbl := AppGui.Add("Text", "x24 y86 w280", "Pieces  (" Catalog.pieces.Length " from scripts/puzzle-pieces.json)")
    t2FilterLbl := AppGui.Add("Text", "x520 y86 w40 c" Theme.FgDim, "Filter")
    EdChipFilter := AppGui.Add("Edit", "x565 y82 w200 h26", "")
    Theme.StyleEdit(EdChipFilter)
    EdChipFilter.OnEvent("Change", OnChipFilterChange)

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

    Tab2Ctrls := [t2Hint, t2PiecesLbl, t2FilterLbl, EdChipFilter]
    for c in chipCtrls
        Tab2Ctrls.Push(c)
    Tab2Ctrls.Push(t2CanvasLbl, EdCanvas, BtnRun, BtnCancelPuzzle, BtnClear, BtnBksp, BtnCopy
        , BtnSaveCanvas, BtnSeed, t2TermLbl, BtnCopyTerm, BtnClearTerm, BtnOpenRepo, EdTerminal)

    StatusBar := AppGui.Add("Text", "x10 y675 w960 h24", " Ready")
    Theme.StyleStatus(StatusBar)

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
    global WipeGui, WipeLbl, AppGui, LastWinW, LastWinH, BtnTab1, BtnTab2

    ChipDrag.Cancel()
    WipeTarget := target
    WipeDir := (target > ActiveTab) ? 1 : -1
    WipeStep := 0
    WipeActive := true

    label := target = 1
        ? "◀══════  COPILOT PROMPT STUDIO  ══════◀"
        : "══════▶  PLAYWRIGHT CLI PUZZLE  ▶══════"
    WipeLbl.Value := label
    Theme.StyleTabBtn(BtnTab1, target = 1)
    Theme.StyleTabBtn(BtnTab2, target = 2)

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
        SetStatus(WipeTarget = 1 ? "Copilot prompt studio" : "Playwright CLI puzzle")
    }
}

ShowTab(n, updateButtons := true) {
    global ActiveTab, Tab1Ctrls, Tab2Ctrls, BtnTab1, BtnTab2

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
    if updateButtons {
        Theme.StyleTabBtn(BtnTab1, n = 1)
        Theme.StyleTabBtn(BtnTab2, n = 2)
    }
    ; Re-apply chip filter after bulk Visible toggles
    if n = 2
        OnChipFilterChange()
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
    global AppGui, BtnTab1
    if ChipDrag.Cancel() {
        SetStatus("Drag cancelled")
        return
    }
    try BtnTab1.Focus()
}

OnResize(thisGui, minMax, width, height) {
    global StatusBar, EdPrompt, EdReply, EdCanvas, EdTerminal
    global EdRecording, EdRecordUrl, EdRecordInstr, BtnRecord, BtnSendRecording
    global BtnSaveAsTest, BtnRunSavedTest, LblRecording
    global BtnReloadLatest, BtnOpenRec
    if minMax = -1
        return
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
            try BtnRecord.Move(rightX, 138, rightW, 32)
            try EdRecording.Move(rightX, 198, rightW, recH)
            instrY := 198 + recH + 8
            try EdRecordInstr.Move(rightX, instrY + 20, rightW, 60)
            try BtnSendRecording.Move(rightX, instrY + 90, rightW, 30)
            try BtnSaveAsTest.Move(rightX, instrY + 126, rightW // 2 - 4, 28)
            try BtnRunSavedTest.Move(rightX + rightW // 2 + 4, instrY + 126, rightW // 2 - 4, 28)
            try BtnReloadLatest.Move(rightX, instrY + 160, rightW // 2 - 4, 26)
            try BtnOpenRec.Move(rightX + rightW // 2 + 4, instrY + 160, rightW // 2 - 4, 26)
            EdCanvas.Move(24, , Min(contentW - 220, 700), )
            EdTerminal.Move(24, , contentW, )
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
    global EdPrompt, EdReply, RepoRoot, BusyCopilot, CopilotJob, BtnSend, BtnCancelCopilot, ActiveTab, JobStartCopilot

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
    SetStatus((code = 0 ? "Copilot finished OK" : "Copilot finished exit " code) "  (" elapsed "s)")
    try TrayTip("Copilot", (code = 0 ? "Finished OK" : "Exit " code) " (" elapsed "s)", code = 0 ? "Iconi" : "Iconx")
    try BtnSaveAsTest.Enabled := (Trim(EdReply.Value) != "")
    CopilotJob := ""
    SaveIniAll()
}

; ---------- Puzzle chips / canvas ----------

AddPieceToCanvas(piece) {
    global Canvas, Catalog, AppGui
    argv := Catalog.ResolvePieceArgv(piece, AppGui.Hwnd)
    if !(argv is Array) {
        SetStatus("Blocked — required slot empty or cancelled")
        return false
    }
    Canvas.AddResolved(piece["label"], argv)
    RefreshCanvasEdit()
    SaveIniAll()
    SetStatus("Added piece: " piece["label"])
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
    global ActiveTab, BusyPuzzle
    return ActiveTab = 2 && !BusyPuzzle
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
    global BusyPuzzle, PuzzleJob, BtnRun, BtnCancelPuzzle, ActiveTab, JobStartPuzzle

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
    try BtnRun.Enabled := false
    try BtnCancelPuzzle.Enabled := true
    EdTerminal.Value := "cwd: " RepoRoot "`n--- async run (stop on first nonzero) ---`n"
    JobStartPuzzle := A_TickCount
    SetStatus("Running from repo root…")
    PuzzleJob := ShellExec.StartCaptureLines(lines, RepoRoot)
    if PuzzleJob.done && InStr(PuzzleJob.output, "empty slots") {
        EdTerminal.Value := PuzzleJob.output
        BusyPuzzle := false
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
    if !PuzzleJob.done {
        elapsed := Round((A_TickCount - JobStartPuzzle) / 1000)
        SetStatus("Puzzle running… " elapsed "s  (Cancel run to abort)")
    }

    if !PuzzleJob.Poll()
        return

    SetTimer(PollPuzzle, 0)
    EdTerminal.Value := "cwd: " RepoRoot "`n" PuzzleJob.output
    code := PuzzleJob.exitCode
    BusyPuzzle := false
    UpdateTrayTip()
    try BtnRun.Enabled := true
    try BtnCancelPuzzle.Enabled := false
    elapsed := Round((A_TickCount - JobStartPuzzle) / 1000)
    SetStatus((code = 0 ? "Puzzle run OK" : "Puzzle stopped — exit " code) "  (" elapsed "s)")
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
    global EdPrompt, EdCanvas, EdTerminal, EdChipFilter, EdRecordInstr, EdRecordUrl, EdRecording, IniPath, ActiveTab, LastWinW, LastWinH, LastWinX, LastWinY, Canvas, RepoRoot, LastSavedSpec, BtnRunSavedTest
    if !FileExist(IniPath)
        return
    try {
        p := IniRead(IniPath, "Copilot", "LastPrompt", "")
        p := IniUnescape(p)
        if p != ""
            EdPrompt.Value := p
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
        if tab = 1 || tab = 2
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
}

SaveIniAll() {
    global EdPrompt, EdCanvas, EdTerminal, EdChipFilter, EdRecordInstr, EdRecordUrl, IniPath, ActiveTab, LastWinW, LastWinH, LastWinX, LastWinY, AppGui, LastSavedSpec
    try {
        IniWrite(IniEscape(EdPrompt.Value), IniPath, "Copilot", "LastPrompt")
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
    }
}

OnChipFilterChange(*) {
    global ChipBtns, EdChipFilter, ActiveTab
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
    global RepoRoot, EdRecordUrl, BusyRecord, RecordJob, BtnRecord, EdRecording, ActiveTab, BusyCopilot
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
    archMsg := RecordJob.archived != "" ? " (archived prior latest)" : ""
    via := RecordJob.usedNpm ? "npm run codegen:record" : "npx playwright codegen"
    EdRecording.Value := "; Recording in progress via " via "…`n; Close the Playwright Inspector / codegen window when done.`n; Waiting for process EXIT (no mid-session poll)."
    SetStatus("Recording started" archMsg " — close codegen when done…")
    try TrayTip("Record", "Headed codegen started — close the window when finished", "Iconi")
    SetTimer(PollRecordExit, 500)
}

OnRecordCancel(*) {
    global RecordJob, BusyRecord, BtnRecord
    SetTimer(PollRecordExit, 0)
    if IsObject(RecordJob) && RecordJob.HasProp("pid") && RecordJob.pid {
        try ProcessClose(RecordJob.pid)
    }
    BusyRecord := false
    RecordJob := ""
    try BtnRecord.Enabled := true
    UpdateTrayTip()
}

PollRecordExit() {
    global RecordJob, BusyRecord, BtnRecord, EdRecording, RepoRoot
    if !IsObject(RecordJob) {
        SetTimer(PollRecordExit, 0)
        BusyRecord := false
        try BtnRecord.Enabled := true
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


SetStatus(msg) {
    global StatusBar
    try StatusBar.Value := " " msg
}
