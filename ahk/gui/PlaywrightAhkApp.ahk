; PlaywrightAhkApp.ahk — overnight AutoHotkey v2 GUI (Copilot studio + Playwright CLI puzzle)
; Double-click to run. Working directory for all Playwright runs = repo root (never ahk\gui alone).
#Requires AutoHotkey v2.0
#SingleInstance Force
#Warn

#Include Lib\Theme.ahk
#Include Lib\ShellExec.ahk
#Include Lib\Json.ahk
#Include Lib\PuzzlePieces.ahk
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
global LastWinW, LastWinH

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

RepoRoot := ShellExec.ResolveRepoRoot(A_ScriptFullPath)
IniPath := A_ScriptDir "\PlaywrightAhkApp.ini"
Catalog := PuzzlePieces.Load(RepoRoot)
Canvas := PuzzleCanvas(Catalog)

BuildGui()
Theme.ApplyDarkTitleBar(AppGui.Hwnd)
LoadIniPrompt()
Canvas.SeedDefault()
RefreshCanvasEdit()
ShowTab(1, false)
SetStatus("Ready — repo root: " RepoRoot)
AppGui.Show("w980 h720")
ApplyChrome(980, 720)
return

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
        "Train wipe on tab switch · Ctrl+Enter Send · F5 Run · Del Backspace piece")

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
        "Click chips to compose npx --no-install playwright ... from repo root. Empty/incomplete slots block Run. Multi-line stops on first nonzero.")
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
        chipCtrls.Push(btn)
        if Mod(idx, cols) = 0 {
            x := 24
            y += rowH
        } else
            x += colW
    }
    chipBottom := y + (Mod(Catalog.pieces.Length, cols) = 0 ? 0 : rowH) + 8

    t2CanvasLbl := AppGui.Add("Text", "x24 y" chipBottom " w400", "Command canvas (editable; one command per line)")
    EdCanvas := AppGui.Add("Edit", "x24 y" (chipBottom + 22) " w700 h120 Multi WantReturn VScroll", "")
    Theme.StyleEdit(EdCanvas)

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

    termTop := by + 150
    t2TermLbl := AppGui.Add("Text", "x24 y" termTop " w400", "Terminal mirror (live)")
    EdTerminal := AppGui.Add("Edit", "x24 y" (termTop + 22) " w920 h190 Multi ReadOnly VScroll", "")
    Theme.StyleEdit(EdTerminal)

    Tab2Ctrls := [t2Hint, t2PiecesLbl]
    for c in chipCtrls
        Tab2Ctrls.Push(c)
    Tab2Ctrls.Push(t2CanvasLbl, EdCanvas, BtnRun, BtnCancelPuzzle, BtnClear, BtnBksp, BtnCopy, t2TermLbl, EdTerminal)

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
    HotIf()
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
    OnCopilotCancel()
    OnPuzzleCancel()
    ExitApp()
}

OnEsc(*) {
    global AppGui, BtnTab1
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
    ; Strip loud auth banners if promoting a failed reply (keep body below banner)
    body := reply
    if InStr(body, "COPILOT AUTH / LOGIN REQUIRED") {
        ; Still allow promote — user may want to iterate on the text below
    }
    if Trim(body) = "" {
        SetStatus("Reply is empty — nothing to promote")
        return
    }
    EdPrompt.Value := body
    try EdPrompt.Focus()
    SaveIniPrompt()
    SetStatus("Reply promoted → prompt (ready to Send)")
}

OnSavePrompt(*) {
    SaveIniPrompt()
    SetStatus("Prompt saved to ini")
}

OnCopilotSend(*) {
    global EdPrompt, EdReply, RepoRoot, BusyCopilot, CopilotJob, BtnSend, BtnCancelCopilot, ActiveTab

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

    SaveIniPrompt()
    BusyCopilot := true
    try BtnSend.Enabled := false
    try BtnCancelCopilot.Enabled := true
    EdReply.Value := "Running copilot (async)…`n"
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
    global CopilotJob, EdReply, BusyCopilot, BtnSend, BtnCancelCopilot
    if !IsObject(CopilotJob) {
        SetTimer(PollCopilot, 0)
        return
    }
    if !CopilotJob.done && CopilotJob.partial != ""
        EdReply.Value := CopilotJob.partial

    if !CopilotJob.Poll()
        return

    SetTimer(PollCopilot, 0)
    EdReply.Value := CopilotJob.output
    code := CopilotJob.exitCode
    BusyCopilot := false
    try BtnSend.Enabled := true
    try BtnCancelCopilot.Enabled := false
    SetStatus(code = 0 ? "Copilot finished OK" : "Copilot finished exit " code)
    CopilotJob := ""
}

ChipClick(piece, *) {
    global Canvas, Catalog
    argv := Catalog.ResolvePieceArgv(piece, 0)
    if !(argv is Array) {
        SetStatus("Blocked — required slot empty or cancelled")
        return
    }
    Canvas.AddResolved(piece["label"], argv)
    RefreshCanvasEdit()
    SetStatus("Added piece: " piece["label"])
}

OnPuzzleClear(*) {
    global Canvas
    Canvas.Clear()
    RefreshCanvasEdit()
    SetStatus("Canvas cleared")
}

OnPuzzleBackspace(*) {
    global Canvas, ActiveTab
    if ActiveTab != 2
        return
    Canvas.Backspace()
    RefreshCanvasEdit()
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
    global BusyPuzzle, PuzzleJob, BtnRun, BtnCancelPuzzle, ActiveTab

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
}

PollPuzzle() {
    global PuzzleJob, EdTerminal, BusyPuzzle, RepoRoot, BtnRun, BtnCancelPuzzle
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

    if !PuzzleJob.Poll()
        return

    SetTimer(PollPuzzle, 0)
    EdTerminal.Value := "cwd: " RepoRoot "`n" PuzzleJob.output
    code := PuzzleJob.exitCode
    BusyPuzzle := false
    try BtnRun.Enabled := true
    try BtnCancelPuzzle.Enabled := false
    SetStatus(code = 0 ? "Puzzle run OK" : "Puzzle stopped — exit " code)
    PuzzleJob := ""
}

LoadIniPrompt() {
    global EdPrompt, IniPath
    if !FileExist(IniPath)
        return
    try {
        p := IniRead(IniPath, "Copilot", "LastPrompt", "")
        p := StrReplace(p, "\n", "`n")
        if p != ""
            EdPrompt.Value := p
    }
}

SaveIniPrompt() {
    global EdPrompt, IniPath
    p := EdPrompt.Value
    p := StrReplace(p, "`r`n", "`n")
    p := StrReplace(p, "`n", "\n")
    try IniWrite(p, IniPath, "Copilot", "LastPrompt")
}

SetStatus(msg) {
    global StatusBar
    try StatusBar.Value := " " msg
}
