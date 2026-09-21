; RecordSession.ahk — headed codegen → recordings/latest.spec.js → Copilot handoff
#Requires AutoHotkey v2.0
#Include ShellExec.ahk

class RecordSession {
    static LatestRel := "recordings\latest.spec.js"
    static MinBytes := 20
    static Seed := "This is a Playwright test recording — keep @playwright/test + getByRole where possible"

    static LatestPath(repoRoot) => repoRoot "\" RecordSession.LatestRel

    static EnsureDirs(repoRoot) {
        DirCreate(repoRoot "\recordings")
        DirCreate(repoRoot "\recordings\archive")
        DirCreate(repoRoot "\tests")
    }

    ; True when package.json defines "codegen:record" (PR #5 script).
    static HasNpmRecordScript(repoRoot) {
        pkg := repoRoot "\package.json"
        if !FileExist(pkg)
            return false
        try {
            raw := FileRead(pkg, "UTF-8")
            return InStr(raw, '"codegen:record"') > 0
        } catch {
            return false
        }
    }

    ; Archive latest.spec.js → recordings/archive/yyyyMMdd-HHmmss.spec.js
    ; Returns archive path or "" if nothing to archive.
    static ArchiveLatest(repoRoot) {
        RecordSession.EnsureDirs(repoRoot)
        latest := RecordSession.LatestPath(repoRoot)
        if !FileExist(latest)
            return ""
        stamp := FormatTime(, "yyyyMMdd-HHmmss")
        dest := repoRoot "\recordings\archive\" stamp ".spec.js"
        ; Avoid clobber if same-second re-record
        if FileExist(dest)
            dest := repoRoot "\recordings\archive\" stamp "-" A_TickCount ".spec.js"
        try {
            FileCopy(latest, dest, true)
            return dest
        } catch {
            return ""
        }
    }

    ; Build cmd.exe line (cwd = repo root). Prefer npm run codegen:record when present.
    static BuildRecordCommand(repoRoot, url := "") {
        url := Trim(url)
        if RecordSession.HasNpmRecordScript(repoRoot) {
            cmd := "npm run codegen:record"
            if url != ""
                cmd .= " -- " ShellExec.Quote(url)
            return cmd
        }
        ; Fallback headed codegen (Playwright codegen is headed by default)
        cmd := "npx --no-install playwright codegen --target=playwright-test -o recordings\latest.spec.js"
        if url != ""
            cmd .= " " ShellExec.Quote(url)
        return cmd
    }

    ; Start headed codegen visibly. Returns {pid, cmd, archived, usedNpm} or throws.
    ; Caller must wait for ProcessExist(pid) to clear — do NOT read stdout mid-session.
    static StartRecord(repoRoot, url := "") {
        RecordSession.EnsureDirs(repoRoot)
        usedNpm := RecordSession.HasNpmRecordScript(repoRoot)
        archived := ""
        ; npm script archives itself; AHK archives for the npx fallback
        if !usedNpm
            archived := RecordSession.ArchiveLatest(repoRoot)
        else {
            ; Still archive if latest exists in case script is a stub — cheap safety
            ; Prefer letting the script own archive; skip duplicate here.
            archived := ""
        }
        cmd := RecordSession.BuildRecordCommand(repoRoot, url)
        ; Visible window required for headed codegen UI
        full := Format('{1} /d /c {2}', A_ComSpec, cmd)
        pid := 0
        Run(full, repoRoot, , &pid)
        if !pid
            throw Error("Failed to start codegen process", -1, cmd)
        return { pid: pid, cmd: cmd, archived: archived, usedNpm: usedNpm }
    }

    ; True when latest.spec.js exists and is large enough to send.
    static LatestIsSendable(repoRoot) {
        latest := RecordSession.LatestPath(repoRoot)
        if !FileExist(latest)
            return false
        try {
            return FileGetSize(latest) >= RecordSession.MinBytes
        } catch {
            return false
        }
    }

    static ReadLatest(repoRoot) {
        latest := RecordSession.LatestPath(repoRoot)
        if !FileExist(latest)
            return ""
        try {
            return FileRead(latest, "UTF-8")
        } catch {
            return ""
        }
    }

    ; Build Copilot prompt: fenced latest + seed + Brian instruction last.
    static BuildCopilotPrompt(specText, instruction) {
        specText := Trim(specText)
        instruction := Trim(instruction)
        prompt :=
        (
            "```javascript
" specText "
```

" RecordSession.Seed "
"
        )
        if instruction != ""
            prompt .= "`n`n" instruction
        return prompt
    }

    ; Strip markdown fences (and optional language tag) from Copilot reply.
    static StripMarkdownFences(text) {
        t := Trim(text, " `t`r`n")
        if t = ""
            return ""
        ; Prefer first fenced block if present (common Copilot shape: prose + fence)
        if RegExMatch(t, "s)``````([\w+-]*)\r?\n(.*?)``````", &m) {
            return Trim(m[2], " `t`r`n")
        }
        ; Entire reply is a single fence
        if RegExMatch(t, "s)^``````([\w+-]*)\r?\n(.*)\r?\n``````$", &m2) {
            return Trim(m2[2], " `t`r`n")
        }
        ; Strip leading/trailing fence lines loosely
        t := RegExReplace(t, "s)^``````[\w+-]*\r?\n", "")
        t := RegExReplace(t, "s)\r?\n``````\s*$", "")
        return Trim(t, " `t`r`n")
    }

    ; Runnable @playwright/test heuristic.
    static LooksLikePlaywrightTest(text) {
        t := RecordSession.StripMarkdownFences(text)
        if t = ""
            return false
        hasTest := InStr(t, "test(") > 0
        hasImport := InStr(t, "@playwright/test") > 0 || InStr(t, "playwright/test") > 0
            || RegExMatch(t, "i)import\s+.*from\s+['""].*playwright")
        return hasTest && hasImport
    }

    ; Write stripped content to tests/recorded-YYYYMMDD-HHmmss.spec.js
    ; Returns path on success, or "" on failure.
    static SaveAsTest(repoRoot, replyText) {
        RecordSession.EnsureDirs(repoRoot)
        body := RecordSession.StripMarkdownFences(replyText)
        if !RecordSession.LooksLikePlaywrightTest(body)
            return ""
        stamp := FormatTime(, "yyyyMMdd-HHmmss")
        dest := repoRoot "\tests\recorded-" stamp ".spec.js"
        if FileExist(dest)
            dest := repoRoot "\tests\recorded-" stamp "-" A_TickCount ".spec.js"
        try {
            f := FileOpen(dest, "w", "UTF-8")
            f.Write(body)
            if !RegExMatch(body, "\n$")
                f.Write("`n")
            f.Close()
            return dest
        } catch {
            return ""
        }
    }

    ; One-click run of a saved recorded spec (chromium project).
    static BuildTestCommand(relOrAbsSpec, repoRoot) {
        spec := relOrAbsSpec
        ; Prefer path relative to repo root for prettier cmd
        if InStr(spec, repoRoot) = 1 {
            spec := SubStr(spec, StrLen(repoRoot) + 2)
            spec := StrReplace(spec, "/", "\")
        }
        return "npx --no-install playwright test --project=chromium " ShellExec.Quote(spec)
    }
}
