; Playwright.ahk — AutoHotkey v2 wrappers for official Playwright CLI (pinned @playwright/test 1.63.0)
; Wrap fork only: shells npx/npm from the repo root. Does not replace Playwright.
;
; Setup (once, in repo root):
;   npm install
;   npx playwright install
;
; Then from AHK (or #Include this file):
;   exitCode := Playwright.Test()
;   Playwright.Codegen("https://playwright.dev")

#Requires AutoHotkey v2.0

class Playwright {
    ; Repo root = parent of the ahk\ folder that holds this file
    static RepoRoot := Playwright._ResolveRepoRoot()

    ; Run `npx --no-install playwright <args…>` from RepoRoot.
    ; Returns process exit code (0 = success). Throws on missing Node / install.
    static Run(args*) {
        Playwright._EnsureReady()
        cmd := Playwright._BuildNpxCmd(args)
        ; Hide console for batch runs; use RunVisible for codegen/report/trace
        return Playwright._RunWait(cmd, false)
    }

    ; Same as Run, but keeps the console window visible (codegen, reports, traces).
    static RunVisible(args*) {
        Playwright._EnsureReady()
        cmd := Playwright._BuildNpxCmd(args)
        return Playwright._RunWait(cmd, true)
    }

    ; Prefer package.json scripts when no extra CLI flags are needed.
    static NpmRun(scriptName, extraArgs*) {
        Playwright._EnsureReady()
        if !RegExMatch(scriptName, "^[\w:-]+$")
            throw Error("Invalid npm script name: " scriptName)
        cmd := 'npm run ' scriptName
        if extraArgs.Length {
            cmd .= " --"
            for a in extraArgs {
                if a = ""
                    continue
                cmd .= " " Playwright._Quote(a)
            }
        }
        visible := scriptName = "codegen" || scriptName = "show-report" || scriptName = "show-trace"
        return Playwright._RunWait(cmd, visible)
    }

    ; --- Convenience wrappers (match package.json) ---

    static Test(extra*) {
        if extra.Length
            return Playwright.Run("test", extra*)
        return Playwright.NpmRun("test")
    }

    static Codegen(url := "") {
        if url != ""
            return Playwright.RunVisible("codegen", url)
        return Playwright.NpmRun("codegen")
    }

    static Install(browser := "") {
        ; browsers are separate from npm package — always go through playwright install
        if browser != ""
            return Playwright.RunVisible("install", browser)
        return Playwright.NpmRun("install-browsers")
    }

    static ShowReport() => Playwright.NpmRun("show-report")

    static ShowTrace(file) {
        if file = ""
            throw Error("ShowTrace requires a trace zip path")
        return Playwright.RunVisible("show-trace", file)
    }

    ; --- internals ---

    static _ResolveRepoRoot() {
        ; Prefer A_LineFile so #Include from any script still finds <repo>\ahk\Playwright.ahk
        src := A_LineFile != "" ? A_LineFile : A_ScriptFullPath
        dir := RegExReplace(src, "i)[\\/][^\\/]+$", "")
        if RegExMatch(dir, "i)\\ahk$")
            return SubStr(dir, 1, StrLen(dir) - 4)
        ; Fallback: parent of A_ScriptDir when demo lives in ahk\
        if RegExMatch(A_ScriptDir, "i)\\ahk$")
            return SubStr(A_ScriptDir, 1, StrLen(A_ScriptDir) - 4)
        return A_ScriptDir
    }

    static _EnsureReady() {
        root := Playwright.RepoRoot
        if !FileExist(root "\package.json")
            throw Error("package.json not found. RepoRoot=" root " — run AHK from the cloned playwright-ahk repo (ahk\ under root).")
        if !Playwright._CommandExists("node")
            throw Error("Node.js not found on PATH (need Node >= 18).")
        if !Playwright._CommandExists("npm")
            throw Error("npm not found on PATH.")
        if !DirExist(root "\node_modules\@playwright\test")
            throw Error("Pinned Playwright missing. In repo root run:`nnpm install`")
    }

    static _BuildNpxCmd(args) {
        ; --no-install: use local node_modules only (pinned 1.63.0), never fetch ad hoc
        cmd := "npx --no-install playwright"
        for a in args {
            if a = ""
                continue
            cmd .= " " Playwright._Quote(a)
        }
        return cmd
    }

    static _Quote(s) {
        s := String(s)
        ; Wrap in double quotes; escape embedded quotes for cmd.exe
        s := StrReplace(s, '"', '\"')
        return '"' s '"'
    }

    static _RunWait(cmd, visible := false) {
        root := Playwright.RepoRoot
        ; Use ComSpec so npx.cmd resolves on Windows
        full := Format('{1} /d /c {2}', A_ComSpec, cmd)
        opts := visible ? "" : "Hide"
        exitCode := RunWait(full, root, opts)
        return exitCode
    }

    static _CommandExists(name) {
        ; where.exe returns 0 if found
        return RunWait(Format('{1} /d /c where {2}', A_ComSpec, name), , "Hide") = 0
    }
}
