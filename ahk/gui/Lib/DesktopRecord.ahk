; DesktopRecord.ahk — Tab 3 Windows UIA desktop recorder / playback / verify
; Kind: windows-uia. NEVER feeds Playwright / @playwright/test.
#Requires AutoHotkey v2.0
#Include UiaCore.ahk
; Json.ahk must be included by the host script before this file.

class DesktopRecord {
    static Kind := "windows-uia"
    static Version := 1
    static Seed := "These are AutoHotkey v2 + UI Automation desktop steps for Windows — keep IUIAutomation targets (AutomationId / Name+ControlType / LocalizedType+index). Do NOT convert to @playwright/test or browser codegen."

    static RelDir := "recordings\windows"
    static MinPollMs := 30
    static ClickDebounceMs := 180

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

    __New(repoRoot) {
        this.repoRoot := repoRoot
        DesktopRecord.EnsureDirs(repoRoot)
    }

    static EnsureDirs(repoRoot) {
        DirCreate(repoRoot "\" DesktopRecord.RelDir)
    }

    static Dir(repoRoot) => repoRoot "\" DesktopRecord.RelDir

    Clear() {
        this.steps := []
        this.lastPath := ""
    }

    Count() => this.steps.Length

    ToMap() {
        return Map(
            "version", DesktopRecord.Version,
            "kind", DesktopRecord.Kind,
            "created", FormatTime(, "yyyy-MM-dd'T'HH:mm:ss"),
            "steps", this.steps
        )
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
        SetTimer(this._Poll.Bind(this), DesktopRecord.MinPollMs)
        this._Status("Desktop UIA recording… click UI targets (Esc/Stop to end)", "ok")
        return true
    }

    StopRecord() {
        if !this.recording
            return
        this.recording := false
        SetTimer(this._Poll.Bind(this), 0)
        this._Status("Recording stopped — " this.steps.Length " steps", "ok")
    }

    _Poll() {
        if !this.recording {
            SetTimer(this._Poll.Bind(this), 0)
            return
        }
        down := GetKeyState("LButton", "P")
        if down && !this.lastBtn {
            if (A_TickCount - this.lastClickTick) >= DesktopRecord.ClickDebounceMs {
                this.lastClickTick := A_TickCount
                this._CaptureClick("click")
            }
        }
        this.lastBtn := down
        rdown := GetKeyState("RButton", "P")
        if rdown && !this.lastRBtn {
            if (A_TickCount - this.lastClickTick) >= DesktopRecord.ClickDebounceMs {
                this.lastClickTick := A_TickCount
                this._CaptureClick("rightclick")
            }
        }
        this.lastRBtn := rdown
        ; Esc stops
        if GetKeyState("Escape", "P") {
            this.StopRecord()
        }
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
        this.steps.Push(step)
        this._Emit(step)
        label := this.StepLabel(step)
        this._Status("Recorded #" this.steps.Length ": " label, "ok")
    }

    StepLabel(step) {
        if !(step is Map)
            return "?"
        cap := step.Has("captured") ? step["captured"] : Map()
        aid := cap.Has("AutomationId") ? Trim(cap["AutomationId"]) : ""
        name := cap.Has("Name") ? Trim(cap["Name"]) : ""
        ctn := cap.Has("ControlTypeName") ? cap["ControlTypeName"] : ""
        if aid != ""
            return "AutomationId=" aid
        if name != ""
            return ctn " '" name "'"
        win := step.Has("window") ? step["window"] : Map()
        cls := win.Has("Class") ? win["Class"] : ""
        return "soft@" cls
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
        for i, step in this.steps {
            this._Status((verifyOnly ? "Verify" : "Play") " step " i "/" this.steps.Length "…")
            res := this.RunStep(step, verifyOnly)
            line := "#" i " " this.StepLabel(step) " → " res.message "`n"
            log .= line
            if !res.ok {
                ok := false
                failedAt := i
                msg := res.message
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
            ; Soft last-resort only after hard list exhausted
            if soft.Length {
                st := soft[1]
                if verifyOnly {
                    return { ok: true, message: "VERIFY soft-only (no UIA hit) strategy=" st["strategy"] " — accepted as soft" }
                }
                if st.Has("relX") {
                    right := (step.Has("action") && step["action"] = "rightclick")
                    if UiaCore.SoftClickRelative(hwnd, st["relX"], st["relY"], right)
                        return { ok: true, message: "PLAY soft WindowRelative (last resort)" }
                }
                return { ok: false, message: "FAIL soft fallback click" }
            }
            return { ok: false, message: "FAIL no ranked UIA target matched (list exhausted)" }
        }

        if verifyOnly {
            return { ok: true, message: "VERIFY ok via " used }
        }

        action := step.Has("action") ? step["action"] : "click"
        if action = "rightclick" {
            ; Prefer clickable/bounds right-click (Invoke is left-default)
            if !UiaCore.InvokeRightClick(resolved.el) {
                return { ok: false, message: "FAIL right-click via " used }
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
        if IsObject(check) && IsObject(check.el)
            return { ok: true, message: "PLAY ok via " used " (post-check)" }
        ; Post-check miss is warning-ish but action already invoked — treat OK if invoke succeeded
        return { ok: true, message: "PLAY ok via " used " (post-check soft miss)" }
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

    _Status(msg, tone := "") {
        cb := this.onStatus
        if cb
            cb.Call(msg, tone)
    }
}
