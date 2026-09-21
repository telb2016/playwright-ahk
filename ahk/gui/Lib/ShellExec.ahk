; ShellExec.ahk — async / sync shell helpers (GUI-safe polling, repo-root cwd)
#Requires AutoHotkey v2.0

class ShellExec {
    static CommandExists(name) {
        if !RegExMatch(name, "^[\w.-]+$")
            return false
        return RunWait(Format('{1} /d /c where {2}', A_ComSpec, name), , "Hide") = 0
    }

    static Quote(s) {
        s := String(s)
        s := StrReplace(s, '"', '\"')
        return '"' s '"'
    }

    ; playwright-ahk repo root = directory that contains package.json AND ahk\
    static ResolveRepoRoot(hintFile := "") {
        src := hintFile != "" ? hintFile : (A_LineFile != "" ? A_LineFile : A_ScriptFullPath)
        dir := RegExReplace(src, "i)[\\/][^\\/]+$", "")
        loop 6 {
            if FileExist(dir "\package.json") && DirExist(dir "\ahk")
                return dir
            parent := RegExReplace(dir, "i)[\\/][^\\/]+$", "")
            if parent = dir
                break
            dir := parent
        }
        if RegExMatch(A_ScriptDir, "i)[\\/]ahk[\\/]gui$")
            return RegExReplace(A_ScriptDir, "i)[\\/]ahk[\\/]gui$", "")
        if RegExMatch(A_ScriptDir, "i)[\\/]ahk$")
            return RegExReplace(A_ScriptDir, "i)[\\/]ahk$", "")
        return A_ScriptDir
    }

    static RunCapture(cmd, workDir, hide := true) {
        job := ShellExec.StartCapture(cmd, workDir)
        ; Blocking helper for probes only — prefer StartCapture + Poll in GUI paths
        while !job.Poll()
            Sleep(50)
        return {exitCode: job.exitCode, output: job.output, cmd: cmd, done: true}
    }

    ; Async single command. workDir MUST be repo root for Playwright runs.
    static StartCapture(cmd, workDir) {
        job := Job()
        job.workDir := workDir
        job.lines := [cmd]
        job.multi := false
        job._StartNextLine()
        return job
    }

    ; Multi-line: sequential from workDir; stop on first nonzero exit.
    static StartCaptureLines(lines, workDir) {
        cleaned := []
        for line in lines {
            t := Trim(line)
            if t != ""
                cleaned.Push(t)
        }
        job := Job()
        job.workDir := workDir
        job.lines := cleaned
        job.multi := true
        if cleaned.Length = 0 {
            job.done := true
            job.exitCode := 1
            job.output := "ERROR: empty slots — add command pieces (or type a command) before Run."
            return job
        }
        job._StartNextLine()
        return job
    }

    static StartCopilot(prompt, workDir) {
        job := Job()
        job.workDir := workDir
        job.copilot := true
        job.cmd := 'copilot -p "<prompt>" --allow-all-tools'

        if !ShellExec.CommandExists("copilot") {
            job.done := true
            job.exitCode := 127
            job.output :=
            (
                "ERROR: GitHub Copilot CLI (`copilot`) was not found on PATH.

Install Copilot CLI and ensure the `copilot` command resolves in a normal cmd.exe session, then click Send again.

Expected invocation:
  copilot -p `"<prompt>`" --allow-all-tools"
            )
            return job
        }

        stamp := A_TickCount "_" Random(1000, 9999)
        tmpPrompt := A_Temp "\pwahk_prompt_" stamp ".txt"
        tmpOut := A_Temp "\pwahk_copilot_" stamp ".txt"
        tmpPs := A_Temp "\pwahk_copilot_" stamp ".ps1"
        try FileDelete(tmpPrompt)
        try FileDelete(tmpOut)
        try FileDelete(tmpPs)

        f := FileOpen(tmpPrompt, "w", "UTF-8")
        f.Write(prompt)
        f.Close()

        psBody :=
        (
            "$ErrorActionPreference = 'Continue'
$p = Get-Content -Raw -Encoding UTF8 -Path '" tmpPrompt "'
$out = '" tmpOut "'
try {
  & copilot -p $p --allow-all-tools *>&1 | Out-File -FilePath $out -Encoding utf8
  $code = $LASTEXITCODE
  Add-Content -Path $out -Value (`"`n__PWAHK_EXIT__=$code`") -Encoding utf8
  exit $code
} catch {
  $_ | Out-File -FilePath $out -Encoding utf8
  Add-Content -Path $out -Value "`n__PWAHK_EXIT__=1" -Encoding utf8
  exit 1
}
"
        )
        pf := FileOpen(tmpPs, "w", "UTF-8")
        pf.Write(psBody)
        pf.Close()

        full := Format(
            '{1} /d /c powershell -NoProfile -ExecutionPolicy Bypass -File "{2}"',
            A_ComSpec, tmpPs
        )
        pid := 0
        Run(full, workDir, "Hide", &pid)
        job.pid := pid
        job.outFile := tmpOut
        job.cleanup := [tmpPrompt, tmpPs]
        return job
    }

    static PeekFile(path) {
        if path = "" || !FileExist(path)
            return ""
        try {
            t := FileRead(path, "UTF-8")
            return StrReplace(StrReplace(t, "`r`n", "`n"), "`r", "`n")
        } catch
            return ""
    }

    static ReadAndDelete(path) {
        t := ShellExec.PeekFile(path)
        if path != ""
            try FileDelete(path)
        return t
    }

    static StripExitMarker(text, &exitCode) {
        exitCode := 0
        if RegExMatch(text, "s)(.*)\n?__PWAHK_EXIT__=(\d+)\s*$", &m) {
            exitCode := Integer(m[2])
            return RTrim(m[1], "`r`n")
        }
        return text
    }

    static AnnotateCopilotFailure(exitCode, output) {
        low := StrLower(output)
        authHints := InStr(low, "not logged") || InStr(low, "unauthor") || InStr(low, "authenticat")
            || InStr(low, "not signed") || InStr(low, "login required") || InStr(low, "gh auth")
            || InStr(low, "please login") || InStr(low, "please log in") || InStr(low, "not authenticated")
            || InStr(low, "sign in") || InStr(low, "sign-in") || InStr(low, "logged out")
            || InStr(low, "requires authentication") || InStr(low, "auth required")
            || InStr(low, "run: gh") || InStr(low, "gh auth login")
            || (InStr(low, "401") && InStr(low, "auth"))
            || (InStr(low, "403") && (InStr(low, "auth") || InStr(low, "forbidden") || InStr(low, "copilot")))
        if exitCode = 0 && !authHints
            return output
        if authHints || exitCode = 127 {
            banner :=
            (
                "╔══════════════════════════════════════════════════════════╗
║  COPILOT AUTH / LOGIN REQUIRED                         ║
║  Output looks unauthenticated or login was required.   ║
║  Fix: open a terminal → sign in so ``copilot`` works,  ║
║  then click Send again.                                ║
╚══════════════════════════════════════════════════════════╝
"
            )
            banner := Format(
                "`n{1}`nERROR: Copilot CLI failed (exit {2}).`n",
                banner, exitCode
            )
            return banner (output = "" ? "" : output)
        }
        if exitCode != 0 && output = ""
            return Format("ERROR: Copilot exited {1} with no captured output.", exitCode)
        return output
    }
}

; Async job — call Poll() from SetTimer so the GUI never freezes on RunWait.
class Job {
    pid := 0
    outFile := ""
    cmd := ""
    workDir := ""
    done := false
    exitCode := 0
    output := ""
    partial := ""
    cleanup := []
    copilot := false
    multi := false
    lines := []
    lineIndex := 0
    combined := ""

    Poll() {
        if this.done
            return true

        if this.pid && ProcessExist(this.pid) {
            this.partial := ShellExec.PeekFile(this.outFile)
            ; Live view without exit marker noise
            live := this.partial
            live := RegExReplace(live, "\n?__PWAHK_EXIT__=\d+\s*$", "")
            this.partial := live
            return false
        }

        raw := ShellExec.ReadAndDelete(this.outFile)
        this.outFile := ""
        code := 0
        chunk := ShellExec.StripExitMarker(raw, &code)

        if this.copilot {
            this.exitCode := code
            this.output := ShellExec.AnnotateCopilotFailure(code, chunk)
            this.done := true
            this._CleanupExtras()
            return true
        }

        if this.multi || this.lines.Length {
            this.combined .= (this.combined = "" ? "" : "`n`n")
                . ">>> " this.cmd "`n" chunk
                . "`n[exit " code "]"
            if code != 0 {
                this.exitCode := code
                this.output := this.combined
                this.done := true
                this._CleanupExtras()
                return true
            }
            if this.lineIndex >= this.lines.Length {
                this.exitCode := 0
                this.output := this.combined
                this.done := true
                this._CleanupExtras()
                return true
            }
            this._StartNextLine()
            return false
        }

        this.exitCode := code
        this.output := chunk
        this.done := true
        this._CleanupExtras()
        return true
    }

    _StartNextLine() {
        this.lineIndex += 1
        if this.lineIndex > this.lines.Length {
            this.done := true
            this.exitCode := 0
            this.output := this.combined = "" ? "" : this.combined
            return
        }
        this.cmd := this.lines[this.lineIndex]
        stamp := A_TickCount "_" Random(1000, 9999)
        this.outFile := A_Temp "\pwahk_line_" stamp ".txt"
        try FileDelete(this.outFile)
        ; Redirect + append exit marker (async-safe exit code)
        inner := Format('({1}) > "{2}" 2>&1 & call echo __PWAHK_EXIT__=%ERRORLEVEL%>>"{2}"', this.cmd, this.outFile)
        full := Format('{1} /d /c {2}', A_ComSpec, inner)
        pid := 0
        Run(full, this.workDir, "Hide", &pid)
        this.pid := pid
        this.partial := ""
    }

    ; Kill in-flight process + stop multi-line chain. Safe to call from GUI Cancel.
    Cancel(reason := "CANCELLED by user.") {
        if this.done
            return true
        pid := this.pid
        if pid {
            try ProcessClose(pid)
            ; Best-effort: also kill orphaned powershell/cmd children by waiting briefly
            try {
                if ProcessExist(pid)
                    ProcessClose(pid)
            }
            this.pid := 0
        }
        this.done := true
        this.exitCode := -1
        prefix := this.combined != "" ? this.combined "`n`n" : ""
        live := this.partial != "" ? this.partial "`n" : ""
        this.output := prefix live reason
        this.partial := ""
        this._CleanupExtras()
        return true
    }

    _CleanupExtras() {
        for p in this.cleanup {
            try FileDelete(p)
        }
        this.cleanup := []
        if this.pid
            this.pid := 0
    }
}
