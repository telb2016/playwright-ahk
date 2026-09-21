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
#Include ..\Playwright.ahk

global AppGui, StatusBar
global RepoRoot
global EdPrompt, EdReply, BtnSend, BtnCancelCopilot, BtnUseReply
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
LastWinW := 980
LastWinH := 720
LastWinX := ""
LastWinY := ""
AppVisible := true
JobStartCopilot := 0
JobStartPuzzle := 0

RepoRoot := ShellExec.ResolveRepoRoot(A_ScriptFullPath)
IniPath := A_ScriptDir "\PlaywrightAhkApp.ini"
Catalog := PuzzlePieces.Load(RepoRoot)
Canvas := PuzzleCanvas(Catalog)

SetupTray()
BuildGui()
Theme.ApplyDarkTitleBar(AppGui.Hwnd)
LoadIniAll()
if Trim(EdCanvas.Value) = "" {
    Canvas.SeedDefault()
    RefreshCanvasEdit()
}
ShowTab(ActiveTab, true)
SetStatus("Ready — repo root: " RepoRoot)
showOpts := "w" LastWinW " h" LastWinH
if LastWinX != "" && LastWinY != ""
    showOpts .= " x" LastWinX " y" LastWinY
AppGui.Show(showOpts)
ApplyChrome(LastWinW, LastWinH)
; Global show/focus hotkey
Hotkey("^!p", ToggleShowFocus)
return

SetupTray() {
    A_IconTip := "Playwright AHK — Overnight GUI"
    try TraySetIcon(A_AhkPath, 1)
    A_TrayMenu.Delete()
    A_TrayMenu.Add("&Show / Focus`tCtrl+Alt+P", (*) => ToggleShowFocus())
    A_TrayMenu.Add()
    A_TrayMenu.Add("Copilot studio", (*) => (ShowAndFocus(), RequestTab(1)))
    A_TrayMenu.Add("CLI puzzle", (*) => (ShowAndFocus(), RequestTab(2)))
    A_TrayMenu.Add()
    A_TrayMenu.Add("E&xit", OnTrayExit)
    A_TrayMenu.Default := "&Show / Focus`tCtrl+Alt+P"
    A_TrayMenu.ClickCount := 1
}

OnTrayExit(*) {
    SaveIniAll()
    OnCopilotCancel()
    OnPuzzleCancel()
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
    try {
        showOpts := "w" LastWinW " h" LastWinH
        if LastWinX != "" && LastWinY != ""
            showOpts .= " x" LastWinX " y" LastWinY
        AppGui.Show(showOpts)
        WinActivate("ahk_id " AppGui.Hwnd)
        ApplyChrome(LastWinW, LastWinH)
    }
    SetStatus("Focused — Ctrl+Alt+P toggles tray")
}

HideToTray() {
    global AppGui, AppVisible
    SaveIniAll()
    AppVisible := false
    try AppGui.Hide()
    TrayTip("Playwright AHK", "Hidden to tray — Ctrl+Alt+P to restore", "Iconi")
}

BuildGui() {
    global AppGui, StatusBar
    global EdPrompt, EdReply, BtnSend, BtnCancelCopilot, BtnUseReply
    global EdCanvas, EdTerminal, BtnRun, BtnCancelPuzzle
    global Catalog, Tab1Ctrls, Tab2Ctrls
    global BtnTab1, BtnTab2, WipeGui, WipeLbl

    AppGui := Gui("+Resize +MinSize820x600", "Playwright AHK — Overnight GUI")
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
        "Drag chips → canvas · Ctrl+Alt+P tray · Ctrl+S save · Ctrl+Enter Send · F5 Run")

    ; ----- Tab 1 content -----
    t1Hint := AppGui.Add("Text", "x24 y56 w900 c" Theme.FgDim,
        "Compose a prompt, Send via copilot -p ... --allow-all-tools (async — GUI stays responsive). Edit & re-Send to cycle.")
    t1PromptLbl := AppGui.Add("Text", "x24 y86 w200", "Prompt")
    EdPrompt := AppGui.Add("Edit", "x24 y108 w920 h180 Multi WantReturn VScroll", "")
    Theme.StyleEdit(EdPrompt)

    BtnSend := AppGui.Add("Button", "x24 y300 w120 h32 Default", "Send")
    Theme.StyleButton(BtnSend, true)
    BtnSend.OnEvent("Click", OnCopilotSend)

    BtnCancelCopilot := AppGui.Add("Button", "x156 y300 w120 h32", "Cancel")
    Theme.StyleButton(BtnCancelCopilot)
    BtnCancelCopilot.Enabled := false
    BtnCancelCopilot.OnEvent("Click", OnCopilotCancel)

    BtnClearReply := AppGui.Add("Button", "x288 y300 w120 h32", "Clear reply")
    Theme.StyleButton(BtnClearReply)
    BtnClearReply.OnEvent("Click", OnClearReply)

    BtnUseReply := AppGui.Add("Button", "x420 y300 w200 h32", "Use reply as next prompt")
    Theme.StyleButton(BtnUseReply, true)
    BtnUseReply.OnEvent("Click", OnUseReplyAsPrompt)

    BtnSavePrompt := AppGui.Add("Button", "x632 y300 w140 h32", "Save prompt")
    Theme.StyleButton(BtnSavePrompt)
    BtnSavePrompt.OnEvent("Click", OnSavePrompt)

    t1ReplyLbl := AppGui.Add("Text", "x24 y346 w400", "Response (editable)")
    EdReply := AppGui.Add("Edit", "x24 y368 w920 h270 Multi WantReturn VScroll", "")
    Theme.StyleEdit(EdReply)

    Tab1Ctrls := [t1Hint, t1PromptLbl, EdPrompt, BtnSend, BtnCancelCopilot, BtnClearReply
        , BtnUseReply, BtnSavePrompt, t1ReplyLbl, EdReply]

    ; ----- Tab 2 content -----
    t2Hint := AppGui.Add("Text", "x24 y56 w900 c" Theme.FgDim,
        "Drag chips onto the canvas (or click to add). Slots open a dark editor. Empty/incomplete slots block Run.")
    t2PiecesLbl := AppGui.Add("Text", "x24 y86 w500", "Pieces  (" Catalog.pieces.Length " from scripts/puzzle-pieces.json)")

    chipCtrls := []
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
    t2TermLbl := AppGui.Add("Text", "x24 y" termTop " w400", "Terminal mirror (live · persisted)")
    EdTerminal := AppGui.Add("Edit", "x24 y" (termTop + 22) " w920 h160 Multi ReadOnly VScroll", "")
    Theme.StyleEdit(EdTerminal)

    Tab2Ctrls := [t2Hint, t2PiecesLbl]
    for c in chipCtrls
        Tab2Ctrls.Push(c)
    Tab2Ctrls.Push(t2CanvasLbl, EdCanvas, BtnRun, BtnCancelPuzzle, BtnClear, BtnBksp, BtnCopy
        , BtnSaveCanvas, t2TermLbl, EdTerminal)

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
    if minMax = -1
        return
    try {
        StatusBar.Move(10, height - 34, width - 20, 24)
        ; Stretch primary edits with window
        contentW := width - 48
        if contentW > 200 {
            EdPrompt.Move(24, 108, contentW, 180)
            EdReply.Move(24, 368, contentW, Max(height - 430, 120))
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
    try BtnSend.Enabled := false
    try BtnCancelCopilot.Enabled := true
    EdReply.Value := "Running copilot (async)…`n"
    JobStartCopilot := A_TickCount
    SetStatus("Copilot starting…")

    CopilotJob := ShellExec.StartCopilot(prompt, RepoRoot)
    if CopilotJob.done {
        EdReply.Value := CopilotJob.output
        BusyCopilot := false
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
    try BtnSend.Enabled := true
    try BtnCancelCopilot.Enabled := false
    SetStatus("Copilot cancelled")
    CopilotJob := ""
}

PollCopilot() {
    global CopilotJob, EdReply, BusyCopilot, BtnSend, BtnCancelCopilot, JobStartCopilot
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
    try BtnSend.Enabled := true
    try BtnCancelCopilot.Enabled := false
    elapsed := Round((A_TickCount - JobStartCopilot) / 1000)
    SetStatus((code = 0 ? "Copilot finished OK" : "Copilot finished exit " code) "  (" elapsed "s)")
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
    global ActiveTab
    return ActiveTab = 2
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
    if Canvas.Backspace() {
        RefreshCanvasEdit()
    } else {
        ; Rows empty (e.g. restored from ini) — trim last line of edit text
        EdCanvas.Value := Canvas.BackspaceText(EdCanvas.Value)
    }
    SaveIniAll()
    SetStatus("Removed last piece")
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
    try BtnRun.Enabled := true
    try BtnCancelPuzzle.Enabled := false
    elapsed := Round((A_TickCount - JobStartPuzzle) / 1000)
    SetStatus((code = 0 ? "Puzzle run OK" : "Puzzle stopped — exit " code) "  (" elapsed "s)")
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
    global EdPrompt, EdCanvas, EdTerminal, IniPath, ActiveTab, LastWinW, LastWinH, LastWinX, LastWinY, Canvas
    if !FileExist(IniPath)
        return
    try {
        p := IniRead(IniPath, "Copilot", "LastPrompt", "")
        p := IniUnescape(p)
        if p != ""
            EdPrompt.Value := p
    }
    try {
        c := IniRead(IniPath, "Puzzle", "Canvas", "")
        c := IniUnescape(c)
        if Trim(c) != "" {
            Canvas.Clear()
            EdCanvas.Value := c
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
        xs := IniRead(IniPath, "UI", "X", "")
        ys := IniRead(IniPath, "UI", "Y", "")
        if xs != "" && ys != "" {
            LastWinX := Integer(xs)
            LastWinY := Integer(ys)
        }
    }
}

SaveIniAll() {
    global EdPrompt, EdCanvas, EdTerminal, IniPath, ActiveTab, LastWinW, LastWinH, LastWinX, LastWinY, AppGui
    try {
        IniWrite(IniEscape(EdPrompt.Value), IniPath, "Copilot", "LastPrompt")
        IniWrite(IniEscape(EdCanvas.Value), IniPath, "Puzzle", "Canvas")
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

SetStatus(msg) {
    global StatusBar
    try StatusBar.Value := " " msg
}
