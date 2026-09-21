; DesktopRecord.ahk — Tab 3 Windows UIA desktop recorder / playback / verify
; Kind: windows-uia. NEVER feeds Playwright / @playwright/test.
#Requires AutoHotkey v2.0
#Include UiaCore.ahk
#Include ScreenSpots.ahk
; Json.ahk must be included by the host script before this file.

class DesktopRecord {
    static Kind := "windows-uia"
    static Version := 1
    static Seed := "These are AutoHotkey v2 + UI Automation desktop steps for Windows — keep IUIAutomation targets (AutomationId / Name+ControlType / LocalizedType+index). Do NOT convert to @playwright/test or browser codegen."

    static RelDir := "recordings\windows"
    static MinPollMs := 30
    static ClickDebounceMs := 180
    static TypeIdleMs := 500
    static WheelBatchMs := 180          ; coalesce rapid same-direction notches
    static DblClickSlopPx := 6          ; max movement between clicks of a dblclick
    static WheelDeltaPerNotch := 120    ; Win32 WHEEL_DELTA convention

    steps := []          ; array of Maps
    recording := false
    playing := false
    lastBtn := false
    lastRBtn := false
    lastClickTick := 0
    repoRoot := ""
    onStep := ""         ; callback(stepMap)
    onStatus := ""       ; callback(msg, tone:="")
    lastPath := ""
    strictSpots := true          ; Strict fullscreen spots (hybrid verifier) — UI toggle
    sessionDisplay := ""         ; display profile captured at record start / first step
    noteFullscreen := false      ; set when a recorded window looks fullscreen
    typeHook := ""               ; InputHook while recording (visible; does not swallow keys)
    typeBuf := ""                ; pending typed characters for current batch
    typeLastTick := 0
    ignoreHwnd := 0              ; host GUI hwnd — skip typing while our app is focused
    onPlayIndex := ""            ; callback(index) — highlight step during Play/Verify
    pendingClick := ""           ; Map draft step awaiting dblclick window, or ""
    pendingWheel := ""           ; Map {notches, tick, ...} coalescing wheel batch
    dblClickMs := 500            ; refreshed from GetDoubleClickTime at record start
    wheelHotkeysOn := false

    __New(repoRoot) {
        this.repoRoot := repoRoot
        this.strictSpots := true
        DesktopRecord.EnsureDirs(repoRoot)
    }

    static EnsureDirs(repoRoot) {
        DirCreate(repoRoot "\" DesktopRecord.RelDir)
    }

    static Dir(repoRoot) => repoRoot "\" DesktopRecord.RelDir

    Clear() {
        this.steps := []
        this.lastPath := ""
        this.sessionDisplay := ""
        this.noteFullscreen := false
        this.typeBuf := ""
        this.typeLastTick := 0
        this.pendingClick := ""
        this.pendingWheel := ""
    }

    Count() => this.steps.Length

    ToMap() {
        m := Map(
            "version", DesktopRecord.Version,
            "kind", DesktopRecord.Kind,
            "created", FormatTime(, "yyyy-MM-dd'T'HH:mm:ss"),
            "strictSpots", !!this.strictSpots,
            "noteFullscreen", !!this.noteFullscreen,
            "steps", this.steps
        )
        if IsObject(this.sessionDisplay)
            m["display"] := this.sessionDisplay
        return m
    }

    ToJson() {
        try {
            return Json.Stringify(this.ToMap())
        } catch {
            return DesktopRecord.MapToJson(this.ToMap())
        }
    }

    ; Lightweight JSON serializer for our Maps/Arrays (Utf-8 text).
    static MapToJson(val, indent := 0) {
        pad := ""
        loop indent
            pad .= "  "
        pad2 := pad "  "
        if val is Map {
            if val.Count = 0
                return "{}"
            parts := []
            for k, v in val {
                parts.Push(pad2 DesktopRecord.JsonStr(k) ": " DesktopRecord.MapToJson(v, indent + 1))
            }
            out := "{`n"
            for i, p in parts
                out .= p (i < parts.Length ? ",`n" : "`n")
            return out pad "}"
        }
        if val is Array {
            if val.Length = 0
                return "[]"
            out := "[`n"
            for i, v in val {
                out .= pad2 DesktopRecord.MapToJson(v, indent + 1)
                out .= (i < val.Length ? ",`n" : "`n")
            }
            return out pad "]"
        }
        if Type(val) = "String"
            return DesktopRecord.JsonStr(val)
        if Type(val) = "Integer" || Type(val) = "Float"
            return String(val)
        if Type(val) = "Number"
            return String(val)
        if val = true || val = false || Type(val) = "String" && (val = "0" || val = "1")
            return val ? "true" : "false"
        if IsObject(val) {
            ; plain object → Map-like
            try {
                m := Map()
                for k, v in val.OwnProps()
                    m[k] := v
                return DesktopRecord.MapToJson(m, indent)
            }
        }
        return '""'
    }

    static JsonStr(s) {
        s := StrReplace(s, "\", "\\")
        s := StrReplace(s, '"', '\"')
        s := StrReplace(s, "`n", "\n")
        s := StrReplace(s, "`r", "\r")
        s := StrReplace(s, "`t", "\t")
        return '"' s '"'
    }

    LoadJson(text) {
        text := Trim(text)
        if text = "" {
            this.steps := []
            return true
        }
        try {
            data := Json.Parse(text)
        } catch as e {
            this._Status("JSON parse failed: " e.Message, "err")
            return false
        }
        if !(data is Map) {
            this._Status("Invalid desktop recording root", "err")
            return false
        }
        kind := data.Has("kind") ? data["kind"] : ""
        if kind != "" && kind != DesktopRecord.Kind {
            this._Status("Refusing load — kind is '" kind "' (want windows-uia)", "err")
            return false
        }
        steps := data.Has("steps") ? data["steps"] : []
        if !(steps is Array) {
            this._Status("Missing steps array", "err")
            return false
        }
        this.steps := steps
        if data.Has("strictSpots")
            this.strictSpots := !!data["strictSpots"]
        if data.Has("noteFullscreen")
            this.noteFullscreen := !!data["noteFullscreen"]
        if data.Has("display") && data["display"] is Map
            this.sessionDisplay := data["display"]
        this._Status("Loaded " this.steps.Length " desktop UIA steps", "ok")
        return true
    }

    LoadFromEdit(text) => this.LoadJson(text)

    StartRecord() {
        if this.recording
            return false
        if !UiaCore.Ensure() {
            this._Status(UiaCore.LastError != "" ? UiaCore.LastError : "UI Automation unavailable", "err")
            return false
        }
        this.recording := true
        this.lastBtn := GetKeyState("LButton", "P")
        this.lastRBtn := GetKeyState("RButton", "P")
        this.lastClickTick := 0
        this.typeBuf := ""
        this.typeLastTick := 0
        this.pendingClick := ""
        this.pendingWheel := ""
        this.dblClickMs := DesktopRecord.GetDoubleClickTimeMs()
        this.sessionDisplay := ScreenSpots.CaptureDisplayProfile()
        this.noteFullscreen := false
        this._StartTypeHook()
        this._StartWheelHotkeys()
        SetTimer(this._Poll.Bind(this), DesktopRecord.MinPollMs)
        spotsNote := this.strictSpots ? " · Strict spots ON" : " · Strict spots OFF"
        this._Status("Desktop UIA recording… click/dblclick/rclick/wheel/type (Esc/Stop)" spotsNote, "ok")
        return true
    }

    StopRecord() {
        if !this.recording
            return
        this.recording := false
        SetTimer(this._Poll.Bind(this), 0)
        SetTimer(this._FlushTypeIdle.Bind(this), 0)
        SetTimer(this._FlushPendingClick.Bind(this), 0)
        SetTimer(this._FlushWheelBatch.Bind(this), 0)
        this._FlushTypeBatch("stop")
        this._FlushPendingClick()
        this._FlushWheelBatch("stop")
        this._StopTypeHook()
        this._StopWheelHotkeys()
        this._Status("Recording stopped — " this.steps.Length " steps", "ok")
    }

    static GetDoubleClickTimeMs() {
        try {
            ms := Integer(DllCall("user32\GetDoubleClickTime"))
            if ms > 0
                return ms
        }
        return 500
    }

    _StartWheelHotkeys() {
        this._StopWheelHotkeys()
        ; Rapid notches must not trip AHK's hotkey flood dialog
        try A_MaxHotkeysPerInterval := 400
        try A_HotkeyInterval := 1000
        try {
            Hotkey("~WheelUp", this._OnWheelUp.Bind(this), "On")
            Hotkey("~WheelDown", this._OnWheelDown.Bind(this), "On")
            this.wheelHotkeysOn := true
        } catch as e {
            this.wheelHotkeysOn := false
            this._Status("Wheel hotkeys failed: " e.Message, "err")
        }
    }

    _StopWheelHotkeys() {
        if !this.wheelHotkeysOn
            return
        this.wheelHotkeysOn := false
        try Hotkey("~WheelUp", "Off")
        try Hotkey("~WheelDown", "Off")
    }

    _OnWheelUp(*) {
        this._AccumulateWheel(1)
    }

    _OnWheelDown(*) {
        this._AccumulateWheel(-1)
    }

    _AccumulateWheel(dir) {
        if !this.recording
            return
        if this._ShouldSkipTyping()
            return
        dir := Integer(dir)
        if dir = 0
            return
        ; Finish pending type / click so order stays chronological
        SetTimer(this._FlushTypeIdle.Bind(this), 0)
        this._FlushTypeBatch("before-wheel")
        this._FlushPendingClick()
        now := A_TickCount
        if this.pendingWheel is Map {
            prev := Integer(this.pendingWheel.Has("notches") ? this.pendingWheel["notches"] : 0)
            sameDir := (prev = 0) || ((prev > 0) = (dir > 0))
            fresh := (now - Integer(this.pendingWheel["tick"])) <= DesktopRecord.WheelBatchMs
            if sameDir && fresh {
                this.pendingWheel["notches"] := prev + dir
                this.pendingWheel["tick"] := now
                SetTimer(this._FlushWheelBatch.Bind(this), -DesktopRecord.WheelBatchMs)
                return
            }
            this._FlushWheelBatch("direction-change")
        }
        MouseGetPos(&sx, &sy, &hwndUnder)
        desc := UiaCore.ElementFromScreenPoint(sx, sy)
        if desc = "" || !(desc is Map) {
            win := Map()
            if hwndUnder {
                try {
                    win["Hwnd"] := hwndUnder
                    win["Title"] := WinGetTitle("ahk_id " hwndUnder)
                    win["Class"] := WinGetClass("ahk_id " hwndUnder)
                    win["ProcessName"] := StrLower(WinGetProcessName("ahk_id " hwndUnder))
                    win["ProcessId"] := WinGetPID("ahk_id " hwndUnder)
                    WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " hwndUnder)
                    win["X"] := wx, win["Y"] := wy, win["W"] := ww, win["H"] := wh
                }
            }
            desc := Map(
                "AutomationId", "",
                "Name", "",
                "ControlType", 0,
                "ControlTypeName", "",
                "LocalizedControlType", "",
                "ClassName", "",
                "Window", win,
                "ParentIndex", 0,
                "Targets", [],
                "ClickX", sx,
                "ClickY", sy
            )
            if win.Has("W") && win["W"] > 0 {
                desc["Targets"] := [Map(
                    "rank", 99,
                    "strategy", "WindowRelativeSoft",
                    "relX", (sx - win["X"]) / win["W"],
                    "relY", (sy - win["Y"]) / win["H"],
                    "soft", true
                )]
            }
        }
        this.pendingWheel := Map(
            "notches", dir,
            "tick", now,
            "desc", desc,
            "sx", sx,
            "sy", sy,
            "hwndUnder", hwndUnder ? hwndUnder : 0
        )
        SetTimer(this._FlushWheelBatch.Bind(this), -DesktopRecord.WheelBatchMs)
    }

    _FlushWheelBatch(reason := "idle") {
        pw := this.pendingWheel
        this.pendingWheel := ""
        SetTimer(this._FlushWheelBatch.Bind(this), 0)
        if !(pw is Map)
            return
        notches := Integer(pw.Has("notches") ? pw["notches"] : 0)
        if notches = 0
            return
        desc := pw["desc"]
        sx := pw["sx"], sy := pw["sy"]
        hwndUnder := pw.Has("hwndUnder") ? pw["hwndUnder"] : 0
        step := Map(
            "action", "wheel",
            "notches", notches,
            "delta", notches * DesktopRecord.WheelDeltaPerNotch,
            "timeoutMs", 4000,
            "window", desc.Has("Window") ? desc["Window"] : Map(),
            "targets", desc.Has("Targets") ? desc["Targets"] : [],
            "captured", Map(
                "AutomationId", desc.Has("AutomationId") ? desc["AutomationId"] : "",
                "Name", desc.Has("Name") ? desc["Name"] : "",
                "ControlType", desc.Has("ControlType") ? desc["ControlType"] : 0,
                "ControlTypeName", desc.Has("ControlTypeName") ? desc["ControlTypeName"] : "",
                "LocalizedControlType", desc.Has("LocalizedControlType") ? desc["LocalizedControlType"] : "",
                "ClassName", desc.Has("ClassName") ? desc["ClassName"] : "",
                "ParentIndex", desc.Has("ParentIndex") ? desc["ParentIndex"] : 0
            ),
            "screen", Map("x", sx, "y", sy),
            "wheelReason", reason
        )
        if this.strictSpots {
            hwndSpot := 0
            if step["window"].Has("Hwnd")
                hwndSpot := Integer(step["window"]["Hwnd"])
            if !hwndSpot
                hwndSpot := hwndUnder
            fs := ScreenSpots.IsProbablyFullscreen(hwndSpot)
            if fs
                this.noteFullscreen := true
            pack := ScreenSpots.CapturePack(hwndSpot, fs)
            step["spots"] := pack
            if !IsObject(this.sessionDisplay) && pack.Has("display")
                this.sessionDisplay := pack["display"]
        }
        this.steps.Push(step)
        this._Emit(step)
        this._Status("Recorded #" this.steps.Length ": " this.StepLabel(step), "ok")
    }

    _StartTypeHook() {
        this._StopTypeHook()
        ; V = visible (do not swallow keys); L0 = no Input buffer (OnChar only)
        ih := InputHook("V L0")
        ih.KeyOpt("{All}", "N")  ; notify OnKeyDown for all keys
        ih.OnChar := this._OnTypeChar.Bind(this)
        ih.OnKeyDown := this._OnTypeKeyDown.Bind(this)
        this.typeHook := ih
        try ih.Start()
        catch as e {
            this.typeHook := ""
            this._Status("InputHook start failed: " e.Message, "err")
        }
    }

    _StopTypeHook() {
        ih := this.typeHook
        this.typeHook := ""
        if IsObject(ih) {
            try ih.Stop()
        }
    }

    _OnTypeChar(ih, ch) {
        if !this.recording
            return
        if this._ShouldSkipTyping()
            return
        if ch = "" || ch = Chr(0)
            return
        ; Filter pure control chars except tab / newline (Enter handled in OnKeyDown)
        code := Ord(ch)
        if code < 32 && ch != "`t" && ch != "`n" && ch != "`r"
            return
        this.typeBuf .= ch
        this.typeLastTick := A_TickCount
        SetTimer(this._FlushTypeIdle.Bind(this), -DesktopRecord.TypeIdleMs)
    }

    _OnTypeKeyDown(ih, vk, sc) {
        if !this.recording
            return
        if this._ShouldSkipTyping()
            return
        ; Escape → stop (also polled); do not put into type buffer
        if vk = 27 {  ; VK_ESCAPE
            this.StopRecord()
            return
        }
        ; Backspace within current batch
        if vk = 8 {  ; VK_BACK
            if this.typeBuf != "" {
                this.typeBuf := SubStr(this.typeBuf, 1, -1)
                this.typeLastTick := A_TickCount
                SetTimer(this._FlushTypeIdle.Bind(this), -DesktopRecord.TypeIdleMs)
            }
            return
        }
        ; Enter commits current type batch (optional early end of debounce)
        if vk = 13 {  ; VK_RETURN
            ; Append newline so playback reproduces the Enter keystroke
            if this.typeBuf = "" || SubStr(this.typeBuf, -1) != "`n"
                this.typeBuf .= "`n"
            SetTimer(this._FlushTypeIdle.Bind(this), 0)
            this._FlushTypeBatch("enter")
            return
        }
        ; Pure modifiers — ignore (no OnChar)
        ; VK: Shift 16, Ctrl 17, Alt 18, LWin/RWin 91/92, Caps 20
        if vk = 16 || vk = 17 || vk = 18 || vk = 91 || vk = 92 || vk = 20
            return
    }

    _ShouldSkipTyping() {
        ; Skip while our host GUI is the foreground window (edit boxes / buttons)
        if this.ignoreHwnd {
            try {
                fg := WinExist("A")
                if fg && Integer(fg) = Integer(this.ignoreHwnd)
                    return true
            }
        }
        return false
    }

    _FlushTypeIdle() {
        if !this.recording
            return
        if this.typeBuf = ""
            return
        if (A_TickCount - this.typeLastTick) < DesktopRecord.TypeIdleMs - 20
            return
        this._FlushTypeBatch("idle")
    }

    _FlushTypeBatch(reason := "idle") {
        text := this.typeBuf
        this.typeBuf := ""
        this.typeLastTick := 0
        SetTimer(this._FlushTypeIdle.Bind(this), 0)
        if text = ""
            return
        ; Drop batches that are only whitespace/newlines with no other content? keep single Enter
        this._CaptureType(text, reason)
    }

    _CaptureType(text, reason := "idle") {
        desc := UiaCore.GetFocusedDescribe()
        sx := 0, sy := 0, hwndUnder := 0
        if desc is Map && desc.Has("ClickX") {
            sx := desc["ClickX"], sy := desc["ClickY"]
        } else {
            try MouseGetPos(&sx, &sy, &hwndUnder)
        }
        if desc = "" || !(desc is Map) {
            win := Map()
            if !hwndUnder {
                try hwndUnder := WinExist("A")
            }
            if hwndUnder {
                try {
                    win["Hwnd"] := hwndUnder
                    win["Title"] := WinGetTitle("ahk_id " hwndUnder)
                    win["Class"] := WinGetClass("ahk_id " hwndUnder)
                    win["ProcessName"] := StrLower(WinGetProcessName("ahk_id " hwndUnder))
                    win["ProcessId"] := WinGetPID("ahk_id " hwndUnder)
                    WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " hwndUnder)
                    win["X"] := wx, win["Y"] := wy, win["W"] := ww, win["H"] := wh
                }
            }
            desc := Map(
                "AutomationId", "",
                "Name", "",
                "ControlType", 0,
                "ControlTypeName", "",
                "LocalizedControlType", "",
                "ClassName", "",
                "Window", win,
                "ParentIndex", 0,
                "Targets", [],
                "ClickX", sx,
                "ClickY", sy
            )
            this._Status("UIA miss @ type — stored window hard-keys only", "err")
        }
        preview := text
        if StrLen(preview) > 40
            preview := SubStr(preview, 1, 37) "…"
        preview := StrReplace(StrReplace(preview, "`n", "\\n"), "`r", "")
        step := Map(
            "action", "type",
            "text", text,
            "timeoutMs", 4000,
            "window", desc.Has("Window") ? desc["Window"] : Map(),
            "targets", desc.Has("Targets") ? desc["Targets"] : [],
            "captured", Map(
                "AutomationId", desc.Has("AutomationId") ? desc["AutomationId"] : "",
                "Name", desc.Has("Name") ? desc["Name"] : "",
                "ControlType", desc.Has("ControlType") ? desc["ControlType"] : 0,
                "ControlTypeName", desc.Has("ControlTypeName") ? desc["ControlTypeName"] : "",
                "LocalizedControlType", desc.Has("LocalizedControlType") ? desc["LocalizedControlType"] : "",
                "ClassName", desc.Has("ClassName") ? desc["ClassName"] : "",
                "ParentIndex", desc.Has("ParentIndex") ? desc["ParentIndex"] : 0
            ),
            "screen", Map("x", sx, "y", sy),
            "typeReason", reason
        )
        if this.strictSpots {
            hwndSpot := 0
            if step["window"].Has("Hwnd")
                hwndSpot := Integer(step["window"]["Hwnd"])
            if !hwndSpot
                hwndSpot := hwndUnder ? hwndUnder : (WinExist("A") || 0)
            fs := ScreenSpots.IsProbablyFullscreen(hwndSpot)
            if fs
                this.noteFullscreen := true
            pack := ScreenSpots.CapturePack(hwndSpot, fs)
            step["spots"] := pack
            if !IsObject(this.sessionDisplay) && pack.Has("display")
                this.sessionDisplay := pack["display"]
        }
        this.steps.Push(step)
        this._Emit(step)
        this._Status("Recorded #" this.steps.Length ": type '" preview "'", "ok")
    }

    _Poll() {
        if !this.recording {
            SetTimer(this._Poll.Bind(this), 0)
            return
        }
        down := GetKeyState("LButton", "P")
        if down && !this.lastBtn {
            if !this._ShouldSkipTyping() {
                SetTimer(this._FlushTypeIdle.Bind(this), 0)
                this._FlushTypeBatch("before-click")
                this._FlushWheelBatch("before-click")
                this._OnLeftClickEdge()
            }
        }
        this.lastBtn := down
        rdown := GetKeyState("RButton", "P")
        if rdown && !this.lastRBtn {
            ; Right-button down edge — mirror left-click debounce (~180ms); never emit left-click
            if !this._ShouldSkipTyping() && (A_TickCount - this.lastClickTick) >= DesktopRecord.ClickDebounceMs {
                this.lastClickTick := A_TickCount
                SetTimer(this._FlushTypeIdle.Bind(this), 0)
                this._FlushTypeBatch("before-rclick")
                this._FlushWheelBatch("before-rclick")
                this._FlushPendingClick()  ; commit pending left before rclick
                this._CaptureClick("rclick")
            }
        }
        this.lastRBtn := rdown
        ; Esc stops (also handled in type hook)
        if GetKeyState("Escape", "P") {
            this.StopRecord()
        }
    }

    ; Left-button edge: defer commit for GetDoubleClickTime so a true dblclick is one step.
    _OnLeftClickEdge() {
        MouseGetPos(&sx, &sy)
        now := A_TickCount
        slop := DesktopRecord.DblClickSlopPx
        if this.pendingClick is Map {
            dt := now - Integer(this.pendingClick["tick"])
            dx := Abs(sx - Integer(this.pendingClick["x"]))
            dy := Abs(sy - Integer(this.pendingClick["y"]))
            if dt <= this.dblClickMs && dx <= slop && dy <= slop {
                SetTimer(this._FlushPendingClick.Bind(this), 0)
                this.pendingClick := ""
                this.lastClickTick := now
                this._CaptureClick("dblclick")
                return
            }
            ; Stale / moved — commit prior as single click first
            this._FlushPendingClick()
        }
        this.pendingClick := Map("tick", now, "x", sx, "y", sy)
        SetTimer(this._FlushPendingClick.Bind(this), -this.dblClickMs)
    }

    _FlushPendingClick(*) {
        pc := this.pendingClick
        this.pendingClick := ""
        SetTimer(this._FlushPendingClick.Bind(this), 0)
        if !(pc is Map)
            return
        this.lastClickTick := A_TickCount
        this._CaptureClick("click")
    }

    _CaptureClick(action := "click") {
        MouseGetPos(&sx, &sy, &hwndUnder)
        desc := UiaCore.ElementFromScreenPoint(sx, sy)
        if desc = "" || !(desc is Map) {
            ; Soft: still record window-relative click with empty hard targets
            win := Map()
            if hwndUnder {
                try {
                    win["Hwnd"] := hwndUnder
                    win["Title"] := WinGetTitle("ahk_id " hwndUnder)
                    win["Class"] := WinGetClass("ahk_id " hwndUnder)
                    win["ProcessName"] := StrLower(WinGetProcessName("ahk_id " hwndUnder))
                    win["ProcessId"] := WinGetPID("ahk_id " hwndUnder)
                    WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " hwndUnder)
                    win["X"] := wx, win["Y"] := wy, win["W"] := ww, win["H"] := wh
                }
            }
            desc := Map(
                "AutomationId", "",
                "Name", "",
                "ControlType", 0,
                "ControlTypeName", "",
                "LocalizedControlType", "",
                "ClassName", "",
                "Window", win,
                "ParentIndex", 0,
                "Targets", [],
                "ClickX", sx,
                "ClickY", sy
            )
            if win.Has("W") && win["W"] > 0 {
                desc["Targets"] := [Map(
                    "rank", 99,
                    "strategy", "WindowRelativeSoft",
                    "relX", (sx - win["X"]) / win["W"],
                    "relY", (sy - win["Y"]) / win["H"],
                    "soft", true
                )]
            }
            this._Status("UIA miss @ click — stored soft window-relative only", "err")
        }
        step := Map(
            "action", action,
            "timeoutMs", 4000,
            "window", desc.Has("Window") ? desc["Window"] : Map(),
            "targets", desc.Has("Targets") ? desc["Targets"] : [],
            "captured", Map(
                "AutomationId", desc.Has("AutomationId") ? desc["AutomationId"] : "",
                "Name", desc.Has("Name") ? desc["Name"] : "",
                "ControlType", desc.Has("ControlType") ? desc["ControlType"] : 0,
                "ControlTypeName", desc.Has("ControlTypeName") ? desc["ControlTypeName"] : "",
                "LocalizedControlType", desc.Has("LocalizedControlType") ? desc["LocalizedControlType"] : "",
                "ClassName", desc.Has("ClassName") ? desc["ClassName"] : "",
                "ParentIndex", desc.Has("ParentIndex") ? desc["ParentIndex"] : 0
            ),
            "screen", Map("x", sx, "y", sy)
        )
        ; Hybrid: client-area % spots (never taskbar) when Strict spots enabled
        if this.strictSpots {
            hwndSpot := 0
            if step["window"].Has("Hwnd")
                hwndSpot := Integer(step["window"]["Hwnd"])
            if !hwndSpot
                hwndSpot := hwndUnder
            try {
                if hwndSpot
                    WinActivate("ahk_id " hwndSpot)
            }
            fs := ScreenSpots.IsProbablyFullscreen(hwndSpot)
            if fs
                this.noteFullscreen := true
            pack := ScreenSpots.CapturePack(hwndSpot, fs)
            step["spots"] := pack
            if !IsObject(this.sessionDisplay) && pack.Has("display")
                this.sessionDisplay := pack["display"]
        }
        this.steps.Push(step)
        this._Emit(step)
        label := this.StepLabel(step)
        extra := ""
        if step.Has("spots") && step["spots"].Has("spots")
            extra := " · spots " step["spots"]["spots"].Length
        this._Status("Recorded #" this.steps.Length ": " label extra, "ok")
    }

    StepLabel(step) {
        if !(step is Map)
            return "?"
        action := step.Has("action") ? step["action"] : "click"
        cap := step.Has("captured") ? step["captured"] : Map()
        aid := cap.Has("AutomationId") ? Trim(cap["AutomationId"]) : ""
        name := cap.Has("Name") ? Trim(cap["Name"]) : ""
        ctn := cap.Has("ControlTypeName") ? cap["ControlTypeName"] : ""
        target := ""
        if aid != ""
            target := "AutomationId=" aid
        else if name != ""
            target := ctn " '" name "'"
        else {
            win := step.Has("window") ? step["window"] : Map()
            cls := win.Has("Class") ? win["Class"] : ""
            target := "soft@" cls
        }
        if action = "type" {
            t := step.Has("text") ? String(step["text"]) : ""
            if StrLen(t) > 28
                t := SubStr(t, 1, 25) "…"
            t := StrReplace(StrReplace(t, "`n", "\n"), "`r", "")
            return "type '" t "' → " target
        }
        if action = "wheel" {
            notches := step.Has("notches") ? Integer(step["notches"]) : 0
            if !notches && step.Has("delta")
                notches := Integer(step["delta"]) // DesktopRecord.WheelDeltaPerNotch
            dir := notches >= 0 ? "Up" : "Down"
            return "wheel" dir " x" Abs(notches) " " target
        }
        if action = "dblclick"
            return "dblclick " target
        if action = "rclick" || action = "rightclick"
            return "rclick " target
        return "click " target
    }

    ; Short one-line summary for the Tab3 step ListBox.
    StepListLine(index, step) {
        return index ". " this.StepLabel(step)
    }

    DeleteStep(index) {
        if index < 1 || index > this.steps.Length
            return false
        this.steps.RemoveAt(index)
        return true
    }

    MoveStep(index, delta) {
        dest := index + delta
        if index < 1 || index > this.steps.Length
            return false
        if dest < 1 || dest > this.steps.Length
            return false
        tmp := this.steps[index]
        this.steps[index] := this.steps[dest]
        this.steps[dest] := tmp
        return true
    }

    ; Play all steps. Returns {ok, failedAt, message, log}
    Play(verifyOnly := false) {
        if this.recording {
            return { ok: false, failedAt: 0, message: "Stop recording first", log: "" }
        }
        if this.playing
            return { ok: false, failedAt: 0, message: "Already playing", log: "" }
        if this.steps.Length = 0
            return { ok: false, failedAt: 0, message: "No desktop steps to play", log: "" }
        if !UiaCore.Ensure()
            return { ok: false, failedAt: 0, message: UiaCore.LastError, log: "" }

        this.playing := true
        log := ""
        failedAt := 0
        msg := ""
        ok := true

        ; Early hard-fail: display profile (resolution/DPI/monitors)
        if this.strictSpots {
            recordedProf := ""
            if IsObject(this.sessionDisplay)
                recordedProf := this.sessionDisplay
            else if this.steps.Length && this.steps[1] is Map && this.steps[1].Has("spots") && this.steps[1]["spots"].Has("display")
                recordedProf := this.steps[1]["spots"]["display"]
            if IsObject(recordedProf) {
                cur := ScreenSpots.CaptureDisplayProfile()
                if !ScreenSpots.ProfilesEqual(recordedProf, cur) {
                    this.playing := false
                    msg := ScreenSpots.ProfileDiffMessage(recordedProf, cur)
                    this._Status(msg, "err")
                    return { ok: false, failedAt: 0, message: msg, log: msg "`n" }
                }
            }
        }

        for i, step in this.steps {
            this._EmitPlayIndex(i)
            this._Status((verifyOnly ? "Verify" : "Play") " step " i "/" this.steps.Length "…")
            Sleep(15)  ; let ListBox / status paint
            res := this.RunStep(step, verifyOnly)
            line := "#" i " " this.StepLabel(step) " → " res.message "`n"
            log .= line
            if !res.ok {
                ok := false
                failedAt := i
                msg := res.message
                this._EmitPlayIndex(i)  ; leave failing step selected
                break
            }
        }
        this.playing := false
        if ok
            msg := (verifyOnly ? "Verify OK — " : "Play OK — ") this.steps.Length " steps"
        this._Status(msg, ok ? "ok" : "err")
        return { ok: ok, failedAt: failedAt, message: msg, log: log }
    }

    Verify() => this.Play(true)

    ; Single step: ranked targets; miss one ≠ fail until list exhausted.
    ; Hard-fail only on wrong process/window class.
    RunStep(step, verifyOnly := false) {
        if !(step is Map)
            return { ok: false, message: "bad step" }
        winMap := step.Has("window") ? step["window"] : Map()
        targets := step.Has("targets") ? step["targets"] : []
        timeoutMs := step.Has("timeoutMs") ? Integer(step["timeoutMs"]) : 4000

        ; Hard window identity
        wantClass := winMap.Has("Class") ? winMap["Class"] : ""
        wantProc := winMap.Has("ProcessName") ? StrLower(winMap["ProcessName"]) : ""
        hwnd := UiaCore.FindWindowHwnd(winMap, Min(timeoutMs, 5000))
        if !hwnd {
            return { ok: false, message: "HARD-FAIL window not found (class='" wantClass "' proc='" wantProc "')" }
        }
        ; Confirm hard keys — wrong process/class = hard fail
        try {
            gotClass := WinGetClass("ahk_id " hwnd)
            gotProc := StrLower(WinGetProcessName("ahk_id " hwnd))
            if wantClass != "" && gotClass != wantClass
                return { ok: false, message: "HARD-FAIL window class got='" gotClass "' want='" wantClass "'" }
            if wantProc != "" && gotProc != wantProc
                return { ok: false, message: "HARD-FAIL process got='" gotProc "' want='" wantProc "'" }
        } catch as e {
            return { ok: false, message: "HARD-FAIL window probe: " e.Message }
        }

        try WinActivate("ahk_id " hwnd)

        ; Separate hard vs soft targets
        hard := []
        soft := []
        if targets is Array {
            for t in targets {
                if !(t is Map)
                    continue
                if t.Has("soft") && t["soft"]
                    soft.Push(t)
                else
                    hard.Push(t)
            }
        }

        resolved := ""
        used := ""
        if hard.Length {
            resolved := UiaCore.ResolveFromTargets(hwnd, hard, timeoutMs)
            if IsObject(resolved) && IsObject(resolved.el) {
                used := resolved.strategy
            } else {
                resolved := ""
            }
        }

        if !IsObject(resolved) || !IsObject(resolved.el) {
            actionEarly := step.Has("action") ? step["action"] : "click"
            ; Soft last-resort only after hard list exhausted
            if soft.Length {
                st := soft[1]
                if st.Has("relX") {
                    right := (actionEarly = "rclick" || actionEarly = "rightclick")
                    dbl := (actionEarly = "dblclick")
                    if verifyOnly {
                        spotRes := this._VerifyStepSpots(hwnd, step)
                        if !spotRes.ok
                            return spotRes
                        return { ok: true, message: "VERIFY soft-only (no UIA hit) " st["strategy"] (spotRes.message != "" ? " · " spotRes.message : "") }
                    }
                    if actionEarly = "type" {
                        ; Soft relative: click to focus then type
                        UiaCore.SoftClickRelative(hwnd, st["relX"], st["relY"], false)
                        Sleep(40)
                        return this._PlayType(hwnd, step, "", "soft-rel", hard)
                    }
                    if actionEarly = "wheel" {
                        notches := this._StepNotches(step)
                        if !UiaCore.SoftWheelRelative(hwnd, st["relX"], st["relY"], notches)
                            return { ok: false, message: "FAIL soft wheel" }
                        spotRes := this._VerifyStepSpots(hwnd, step)
                        if !spotRes.ok
                            return spotRes
                        return { ok: true, message: "PLAY soft wheel WindowRelative" (spotRes.message != "" ? " · " spotRes.message : "") }
                    }
                    clickCount := dbl ? 2 : 1
                    if UiaCore.SoftClickRelative(hwnd, st["relX"], st["relY"], right, clickCount) {
                        spotRes := this._VerifyStepSpots(hwnd, step)
                        if !spotRes.ok
                            return spotRes
                        return { ok: true, message: "PLAY soft WindowRelative (last resort)" (spotRes.message != "" ? " · " spotRes.message : "") }
                    }
                }
                return { ok: false, message: "FAIL soft fallback click" }
            }
            ; Type / wheel may proceed with window-only when no UIA target matched
            if actionEarly = "type" {
                if verifyOnly {
                    spotRes := this._VerifyStepSpots(hwnd, step)
                    if !spotRes.ok
                        return spotRes
                    return { ok: true, message: "VERIFY type window-only (no UIA hit)" (spotRes.message != "" ? " · " spotRes.message : "") }
                }
                return this._PlayType(hwnd, step, "", "", hard)
            }
            if actionEarly = "wheel" {
                if verifyOnly {
                    spotRes := this._VerifyStepSpots(hwnd, step)
                    if !spotRes.ok
                        return spotRes
                    return { ok: true, message: "VERIFY wheel window-only (no UIA hit)" (spotRes.message != "" ? " · " spotRes.message : "") }
                }
                return this._PlayWheel(hwnd, step, "", "", hard)
            }
            return { ok: false, message: "FAIL no ranked UIA target matched (list exhausted)" }
        }

        if verifyOnly {
            spotRes := this._VerifyStepSpots(hwnd, step)
            if !spotRes.ok
                return spotRes
            return { ok: true, message: "VERIFY ok via " used (spotRes.message != "" ? " · " spotRes.message : "") }
        }

        action := step.Has("action") ? step["action"] : "click"
        if action = "type" {
            return this._PlayType(hwnd, step, resolved, used, hard)
        }
        if action = "wheel" {
            return this._PlayWheel(hwnd, step, resolved, used, hard)
        }
        if action = "rclick" || action = "rightclick" {
            ; Prefer clickable/bounds right-click (Invoke is left-default)
            if !UiaCore.InvokeRightClick(resolved.el) {
                return { ok: false, message: "FAIL rclick via " used }
            }
        } else if action = "dblclick" {
            if !UiaCore.InvokeDoubleClick(resolved.el) {
                return { ok: false, message: "FAIL dblclick via " used }
            }
        } else if !UiaCore.InvokeClick(resolved.el) {
            return { ok: false, message: "FAIL invoke/click via " used }
        }
        settle := step.Has("settleMs") ? Integer(step["settleMs"]) : 80
        if settle < 0
            settle := 0
        Sleep(settle)
        ; Re-check element still addressable (property wait)
        check := UiaCore.ResolveFromTargets(hwnd, hard, 800)
        baseMsg := IsObject(check) && IsObject(check.el)
            ? "PLAY ok via " used " (post-check)"
            : "PLAY ok via " used " (post-check soft miss)"
        spotRes := this._VerifyStepSpots(hwnd, step)
        if !spotRes.ok
            return spotRes
        if spotRes.message != ""
            baseMsg .= " · " spotRes.message
        return { ok: true, message: baseMsg }
    }

    ; Type playback: focus + SetValue when possible, else SendText. Spots unchanged.
    _PlayType(hwnd, step, resolved, used, hard) {
        text := step.Has("text") ? String(step["text"]) : ""
        el := IsObject(resolved) && IsObject(resolved.el) ? resolved.el : ""
        how := used != "" ? used : "SendText"
        ok := false
        if IsObject(el) {
            UiaCore.SetFocus(el)
            Sleep(40)
            if UiaCore.SetValue(el, text) {
                ok := true
                how := used " SetValue"
            } else {
                ; Click to focus then SendText
                try UiaCore.InvokeClick(el)
                Sleep(40)
                SendText(text)
                ok := true
                how := used " SendText"
            }
        } else {
            ; Soft / no element — activate window and SendText
            try WinActivate("ahk_id " hwnd)
            Sleep(40)
            SendText(text)
            ok := true
            how := "SendText (no UIA el)"
        }
        if !ok
            return { ok: false, message: "FAIL type via " how }
        settle := step.Has("settleMs") ? Integer(step["settleMs"]) : 80
        if settle < 0
            settle := 0
        Sleep(settle)
        baseMsg := "PLAY type ok via " how
        spotRes := this._VerifyStepSpots(hwnd, step)
        if !spotRes.ok
            return spotRes
        if spotRes.message != ""
            baseMsg .= " · " spotRes.message
        return { ok: true, message: baseMsg }
    }

    _StepNotches(step) {
        if !(step is Map)
            return 0
        if step.Has("notches")
            return Integer(step["notches"])
        if step.Has("delta")
            return Integer(step["delta"]) // DesktopRecord.WheelDeltaPerNotch
        return 0
    }

    ; Wheel playback: activate hard-keys, move to target when possible, then WheelUp/Down.
    _PlayWheel(hwnd, step, resolved, used, hard) {
        notches := this._StepNotches(step)
        if notches = 0
            return { ok: false, message: "FAIL wheel notches=0" }
        el := IsObject(resolved) && IsObject(resolved.el) ? resolved.el : ""
        how := used != "" ? used : "window"
        try WinActivate("ahk_id " hwnd)
        if IsObject(el) {
            UiaCore.MoveToElement(el)
            Sleep(20)
            how := used " + Wheel"
        } else {
            ; Fall back: screen coords from recording if present
            if step.Has("screen") && step["screen"] is Map {
                sx := step["screen"].Has("x") ? Integer(step["screen"]["x"]) : ""
                sy := step["screen"].Has("y") ? Integer(step["screen"]["y"]) : ""
                if sx != "" && sy != ""
                    MouseMove(sx, sy, 0)
            }
            how := "Wheel (no UIA el)"
        }
        if !UiaCore.WheelAtCursor(notches)
            return { ok: false, message: "FAIL wheel via " how }
        settle := step.Has("settleMs") ? Integer(step["settleMs"]) : 80
        if settle < 0
            settle := 0
        Sleep(settle)
        baseMsg := "PLAY wheel ok via " how " notches=" notches
        spotRes := this._VerifyStepSpots(hwnd, step)
        if !spotRes.ok
            return spotRes
        if spotRes.message != ""
            baseMsg .= " · " spotRes.message
        return { ok: true, message: baseMsg }
    }

    ; Hybrid spots after UIA (client-pct). Skipped when Strict spots OFF.
    _VerifyStepSpots(hwnd, step) {
        if !this.strictSpots
            return { ok: true, message: "" }
        if !(step is Map) || !step.Has("spots")
            return { ok: true, message: "spots skipped (none recorded)" }
        pack := step["spots"]
        ; If recording noted not to use spots and pack empty — skip
        if !(pack is Map)
            return { ok: true, message: "" }
        res := ScreenSpots.VerifyPack(hwnd, pack)
        if res.ok
            return { ok: true, message: res.message }
        return { ok: false, message: res.message }
    }

    ; Load newest desktop-*.json from recordings/windows (by file time).
    LoadLatest(repoRoot := "") {
        root := repoRoot != "" ? repoRoot : this.repoRoot
        dir := DesktopRecord.Dir(root)
        if !DirExist(dir)
            return ""
        best := ""
        bestT := 0
        loop files dir "\desktop-*.json" {
            try {
                t := FileGetTime(A_LoopFileFullPath, "M")
                ; YYYYMMDDHHMISS lexical works
                if t > bestT {
                    bestT := t
                    best := A_LoopFileFullPath
                }
            }
        }
        if best = ""
            return ""
        try raw := FileRead(best, "UTF-8")
        catch {
            return ""
        }
        if !this.LoadJson(raw)
            return ""
        this.lastPath := best
        this._Status("Loaded latest " best, "ok")
        return best
    }

    Save(repoRoot := "") {
        root := repoRoot != "" ? repoRoot : this.repoRoot
        DesktopRecord.EnsureDirs(root)
        stamp := FormatTime(, "yyyyMMdd-HHmmss")
        path := root "\" DesktopRecord.RelDir "\desktop-" stamp ".json"
        if FileExist(path)
            path := root "\" DesktopRecord.RelDir "\desktop-" stamp "-" A_TickCount ".json"
        json := this.ToJson()
        try {
            f := FileOpen(path, "w", "UTF-8")
            f.Write(json)
            if !RegExMatch(json, "\n$")
                f.Write("`n")
            f.Close()
        } catch as e {
            this._Status("Save failed: " e.Message, "err")
            return ""
        }
        ; Companion AHK stub (maintainable)
        ahkPath := RegExReplace(path, "i)\.json$", ".ahk")
        try FileOpen(ahkPath, "w", "UTF-8").Write(this.ToAhkStub(path)).Close()
        catch {
            ; non-fatal
        }
        this.lastPath := path
        this._Status("Saved " path, "ok")
        return path
    }

    ToAhkStub(jsonPath) {
        return (
            "; Auto-generated Windows UIA desktop recording — NOT Playwright`n"
            "#Requires AutoHotkey v2.0`n"
            "; Source JSON: " jsonPath "`n"
            "; Re-play from PlaywrightAhkApp Tab 3 (Desktop UIA) or load JSON into DesktopRecord.`n"
            "; Kind: " DesktopRecord.Kind "`n"
        )
    }

    BuildCopilotPrompt(instruction := "") {
        json := this.ToJson()
        instruction := Trim(instruction)
        prompt :=
        (
            "```json
" json "
```

" DesktopRecord.Seed "
"
        )
        if instruction != ""
            prompt .= "`n`n" instruction
        return prompt
    }

    ; Describe element under cursor without appending (debug / teach ranked targets).
    ProbeUnderCursor() {
        if !UiaCore.Ensure() {
            this._Status(UiaCore.LastError, "err")
            return ""
        }
        MouseGetPos(&sx, &sy)
        desc := UiaCore.ElementFromScreenPoint(sx, sy)
        if desc = "" {
            this._Status("Probe: no UIA element under cursor", "err")
            return ""
        }
        this._Status("Probe: " (desc.Has("AutomationId") && desc["AutomationId"] != "" ? "AutomationId=" desc["AutomationId"] : desc["ControlTypeName"] " '" desc["Name"] "'"), "ok")
        return desc
    }

    _Emit(step) {
        cb := this.onStep
        if cb
            cb.Call(step)
    }

    _EmitPlayIndex(index) {
        cb := this.onPlayIndex
        if cb
            cb.Call(index)
    }

    _Status(msg, tone := "") {
        cb := this.onStatus
        if cb
            cb.Call(msg, tone)
    }
}
