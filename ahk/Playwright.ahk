; Playwright.ahk — thin AutoHotkey wrappers for official Playwright CLI (stable 1.63.0)
; Requires: Node.js, npm install in repo root, browsers via `npx playwright install`

#Requires AutoHotkey v2.0

class Playwright {
    static RepoRoot := A_ScriptDir "\.."

    static Run(args*) {
        cmd := 'npx --no-install playwright'
        for a in args
            cmd .= ' "' . a . '"'
        Run Wait, A_ComSpec ' /c "' cmd '"', this.RepoRoot, "Hide"
        return A_LastError
    }

    static Test(extra := "") => this.Run("test", extra)
    static Codegen(url := "") => (url != "" ? this.Run("codegen", url) : this.Run("codegen"))
    static Install(browser := "") => (browser != "" ? this.Run("install", browser) : this.Run("install"))
    static ShowReport() => this.Run("show-report")
    static ShowTrace(file) => this.Run("show-trace", file)
}
