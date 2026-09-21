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

global AppGui, TabCtrl, StatusBar
global RepoRoot
global EdPrompt, EdReply, BtnSend
global EdCanvas, EdTerminal
global Catalog, Canvas
global CopilotJob, PuzzleJob
global IniPath
global BusyCopilot, BusyPuzzle

CopilotJob := ""
PuzzleJob := ""
BusyCopilot := false
BusyPuzzle := false

RepoRoot := ShellExec.ResolveRepoRoot(A_ScriptFullPath)
IniPath := A_ScriptDir "\PlaywrightAhkApp.ini"
Catalog := PuzzlePieces.Load(RepoRoot)
Canvas := PuzzleCanvas(Catalog)

BuildGui()
Theme.ApplyDarkTitleBar(AppGui.Hwnd)
LoadIniPrompt()
Canvas.SeedDefault()
RefreshCanvasEdit()
SetStatus("Ready — repo root: " RepoRoot)
AppGui.Show("w980 h720")
return

BuildGui() {
    global AppGui, TabCtrl, StatusBar
    global EdPrompt, EdReply, BtnSend
    global EdCanvas, EdTerminal
    global Catalog

    AppGui := Gui("+Resize +MinSize820x600", "Playwright AHK — Overnight GUI")
    Theme.StyleGui(AppGui)
    AppGui.OnEvent("Close", (*) => ExitApp())
    AppGui.OnEvent("Escape", OnEsc)
    AppGui.OnEvent("Size", OnResize)

    TabCtrl := AppGui.Add("Tab3", "x10 y10 w960 h660", ["Copilot prompt studio", "Playwright CLI puzzle"])
    try TabCtrl.Opt("Background" Theme.BgPanel " c" Theme.Fg)

    ; ----- Tab 1 -----
    TabCtrl.UseTab(1)
    AppGui.SetFont("s10 c" Theme.Fg, "Segoe UI")
    AppGui.Add("Text", "x24 y48 w900 c" Theme.FgDim,
        "Compose a prompt, Send via copilot -p ... --allow-all-tools (async — GUI stays responsive). Edit & re-Send to cycle.")

    AppGui.Add("Text", "x24 y78 w200", "Prompt")
    EdPrompt := AppGui.Add("Edit", "x24 y100 w920 h200 Multi WantReturn VScroll", "")
    Theme.StyleEdit(EdPrompt)

    BtnSend := AppGui.Add("Button", "x24 y310 w120 h32 Default", "Send")
    Theme.StyleButton(BtnSend, true)
    BtnSend.OnEvent("Click", OnCopilotSend)

    BtnClearReply := AppGui.Add("Button", "x156 y310 w120 h32", "Clear reply")
    Theme.StyleButton(BtnClearReply)
    BtnClearReply.OnEvent("Click", OnClearReply)

    BtnSavePrompt := AppGui.Add("Button", "x288 y310 w140 h32", "Save prompt")
    Theme.StyleButton(BtnSavePrompt)
    BtnSavePrompt.OnEvent("Click", OnSavePrompt)

    AppGui.Add("Text", "x24 y356 w200", "Response (editable)")
    EdReply := AppGui.Add("Edit", "x24 y378 w920 h260 Multi WantReturn VScroll", "")
    Theme.StyleEdit(EdReply)

    ; ----- Tab 2 -----
    TabCtrl.UseTab(2)
    AppGui.Add("Text", "x24 y48 w900 c" Theme.FgDim,
        "Click chips to compose npx --no-install playwright ... from repo root. Empty/incomplete slots block Run. Multi-line stops on first nonzero.")

    AppGui.Add("Text", "x24 y78 w500", "Pieces  (" Catalog.pieces.Length " from scripts/puzzle-pieces.json)")
    x := 24
    y := 100
    colW := 180
    rowH := 30
    cols := 5
    for idx, piece in Catalog.pieces {
        btn := AppGui.Add("Button", "x" x " y" y " w" (colW - 8) " h26", piece["label"])
        Theme.StyleChip(btn)
        btn.OnEvent("Click", ChipClick.Bind(piece))
        if Mod(idx, cols) = 0 {
            x := 24
            y += rowH
        } else
            x += colW
    }
    chipBottom := y + (Mod(Catalog.pieces.Length, cols) = 0 ? 0 : rowH) + 8

    AppGui.Add("Text", "x24 y" chipBottom " w400", "Command canvas (editable; one command per line)")
    EdCanvas := AppGui.Add("Edit", "x24 y" (chipBottom + 22) " w700 h120 Multi WantReturn VScroll", "")
    Theme.StyleEdit(EdCanvas)

    by := chipBottom + 22
    BtnRun := AppGui.Add("Button", "x740 y" by " w200 h36", "Run")
    Theme.StyleButton(BtnRun, true)
    BtnRun.OnEvent("Click", OnPuzzleRun)

    BtnClear := AppGui.Add("Button", "x740 y" (by + 44) " w96 h28", "Clear")
    Theme.StyleButton(BtnClear)
    BtnClear.OnEvent("Click", OnPuzzleClear)

    BtnBksp := AppGui.Add("Button", "x844 y" (by + 44) " w96 h28", "Backspace")
    Theme.StyleButton(BtnBksp)
    BtnBksp.OnEvent("Click", OnPuzzleBackspace)

    BtnCopy := AppGui.Add("Button", "x740 y" (by + 80) " w200 h28", "Copy command")
    Theme.StyleButton(BtnCopy)
    BtnCopy.OnEvent("Click", OnPuzzleCopy)

    termTop := by + 120
    AppGui.Add("Text", "x24 y" termTop " w400", "Terminal mirror (live)")
    EdTerminal := AppGui.Add("Edit", "x24 y" (termTop + 22) " w920 h220 Multi ReadOnly VScroll", "")
    Theme.StyleEdit(EdTerminal)

    TabCtrl.UseTab(0)
    StatusBar := AppGui.Add("Text", "x10 y675 w960 h24", " Ready")
    Theme.StyleStatus(StatusBar)

    HotIfWinActive("ahk_id " AppGui.Hwnd)
    Hotkey("^Enter", OnCopilotSend)
    HotIf()
}

OnEsc(*) {
    global AppGui, TabCtrl
    try TabCtrl.Focus()
}

OnResize(thisGui, minMax, width, height) {
    global TabCtrl, StatusBar
    if minMax = -1
        return
    try {
        TabCtrl.Move(10, 10, width - 20, height - 50)
        StatusBar.Move(10, height - 34, width - 20, 24)
    }
}

OnClearReply(*) {
    global EdReply
    EdReply.Value := ""
    SetStatus("Reply cleared")
}

OnSavePrompt(*) {
    SaveIniPrompt()
    SetStatus("Prompt saved to ini")
}

OnCopilotSend(*) {
    global EdPrompt, EdReply, RepoRoot, BusyCopilot, CopilotJob, BtnSend

    if BusyCopilot {
        SetStatus("Copilot already running…")
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
    EdReply.Value := "Running copilot (async)…`n"
    SetStatus("Copilot starting…")

    CopilotJob := ShellExec.StartCopilot(prompt, RepoRoot)
    if CopilotJob.done {
        EdReply.Value := CopilotJob.output
        BusyCopilot := false
        try BtnSend.Enabled := true
        SetStatus("Copilot failed immediately (exit " CopilotJob.exitCode ")")
        return
    }
    SetTimer(PollCopilot, 150)
}

PollCopilot() {
    global CopilotJob, EdReply, BusyCopilot, BtnSend
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
    global Canvas
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
    global BusyPuzzle, PuzzleJob

    if BusyPuzzle {
        SetStatus("Puzzle already running…")
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
    EdTerminal.Value := "cwd: " RepoRoot "`n--- async run (stop on first nonzero) ---`n"
    SetStatus("Running from repo root…")
    PuzzleJob := ShellExec.StartCaptureLines(lines, RepoRoot)
    if PuzzleJob.done && InStr(PuzzleJob.output, "empty slots") {
        EdTerminal.Value := PuzzleJob.output
        BusyPuzzle := false
        SetStatus("Run blocked")
        return
    }
    SetTimer(PollPuzzle, 150)
}

PollPuzzle() {
    global PuzzleJob, EdTerminal, BusyPuzzle, RepoRoot
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
