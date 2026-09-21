; PuzzlePieces.ahk — load scripts/puzzle-pieces.json and compose CLI lines
#Requires AutoHotkey v2.0
#Include Json.ahk
#Include ShellExec.ahk

class PuzzlePieces {
    prefix := ["npx", "--no-install", "playwright"]
    pieces := []          ; array of Maps from JSON
    byId := Map()
    repoRoot := ""
    runPolicy := Map("stopOnNonZero", 1, "blockIncompleteSlots", 1)
    loadedFrom := ""

    static Load(repoRoot) {
        inst := PuzzlePieces()
        inst.repoRoot := repoRoot
        path := repoRoot "\scripts\puzzle-pieces.json"
        if !FileExist(path) {
            ; Fallback: minimal 1 default piece so GUI still opens
            inst.loadedFrom := "(builtin fallback — scripts/puzzle-pieces.json missing)"
            def := Map(
                "id", 5,
                "label", "test --project=chromium",
                "argv", ["test", "--project=chromium"],
                "npmScript", "test:chromium",
                "slots", [],
                "defaultFirstDrop", 1
            )
            inst.pieces.Push(def)
            inst.byId[5] := def
            return inst
        }
        raw := FileRead(path, "UTF-8")
        data := Json.Parse(raw)
        inst.loadedFrom := path
        if data.Has("prefix") && data["prefix"] is Array
            inst.prefix := data["prefix"]
        if data.Has("runPolicy") && data["runPolicy"] is Map
            inst.runPolicy := data["runPolicy"]
        if data.Has("pieces") && data["pieces"] is Array {
            for p in data["pieces"] {
                inst.pieces.Push(p)
                if p.Has("id")
                    inst.byId[p["id"]] := p
            }
        }
        return inst
    }

    DefaultFirstPiece() {
        for p in this.pieces {
            if p.Has("defaultFirstDrop") && p["defaultFirstDrop"]
                return p
        }
        ; Fallback id 5 / label match
        for p in this.pieces {
            if p.Has("label") && p["label"] = "test --project=chromium"
                return p
        }
        return this.pieces.Length ? this.pieces[1] : ""
    }

    ; Build argv tokens for a piece, prompting for required slots.
    ; Returns "" if user cancels or required slot left empty (block Run).
    ResolvePieceArgv(piece, ownerHwnd := 0) {
        argv := []
        for a in piece["argv"]
            argv.Push(a)

        slots := piece.Has("slots") ? piece["slots"] : []
        if !(slots is Array) || slots.Length = 0
            return argv

        for slot in slots {
            name := slot.Has("name") ? slot["name"] : "value"
            required := slot.Has("required") && slot["required"]
            def := ""
            if name = "url"
                def := "https://playwright.dev"
            if name = "out"
                def := name = "out" && InStr(piece["label"], "pdf") ? "page.pdf" : "shot.png"
            if name = "file"
                def := "trace.zip"
            if name = "grep"
                def := ""

            prompt := "Piece: " piece["label"] "`nEnter value for slot '" name "'" (required ? " (required)" : "") ":"
            res := InputBox(prompt, "Playwright puzzle slot", "w420 h160", def)
            if res.Result != "OK" {
                if required
                    return ""  ; cancel + required => block
                continue
            }
            val := Trim(res.Value)
            if required && val = ""
                return ""  ; empty required slot => block

            if slot.Has("appendTo") {
                flag := slot["appendTo"]
                ; Replace matching argv entry that equals / starts with appendTo
                replaced := false
                for i, a in argv {
                    if a = flag || (flag != "" && InStr(a, flag) = 1) {
                        argv[i] := flag val
                        replaced := true
                        break
                    }
                }
                if !replaced
                    argv.Push(flag val)
            } else {
                ; trailing position
                argv.Push(val)
            }
        }
        return argv
    }

    ; Quote + join prefix and argv into one cmd.exe line
    BuildCommandLine(argvPieces*) {
        parts := []
        for p in this.prefix
            parts.Push(p)
        for chunk in argvPieces {
            if chunk is Array {
                for a in chunk
                    parts.Push(a)
            } else if chunk != ""
                parts.Push(chunk)
        }
        line := ""
        for i, tok in parts {
            if i > 1
                line .= " "
            ; Quote if spaces / specials
            if RegExMatch(tok, '[ \t&|<>^%"]')
                line .= ShellExec.Quote(tok)
            else
                line .= tok
        }
        return line
    }

    BlockIncomplete() {
        ; Default true when policy missing
        if !this.runPolicy.Has("blockIncompleteSlots")
            return true
        return !!this.runPolicy["blockIncompleteSlots"]
    }
}

; Canvas model: ordered list of resolved argv arrays (each drop = one piece)
class PuzzleCanvas {
    rows := []           ; [{label, argv, cmdLine}]
    catalog := ""
    prefixLine := ""

    __New(catalog) {
        this.catalog := catalog
        this.prefixLine := catalog.BuildCommandLine()
    }

    Clear() {
        this.rows := []
    }

    Count() => this.rows.Length

    Backspace() {
        if this.rows.Length
            this.rows.Pop()
    }

    AddResolved(label, argv) {
        if !(argv is Array) || argv.Length = 0
            return false
        cmd := this.catalog.BuildCommandLine(argv)
        this.rows.Push({label: label, argv: argv, cmdLine: cmd})
        return true
    }

    ; Seed default first drop
    SeedDefault() {
        this.Clear()
        p := this.catalog.DefaultFirstPiece()
        if p = ""
            return
        argv := []
        for a in p["argv"]
            argv.Push(a)
        this.AddResolved(p["label"], argv)
    }

    ; Multi-line text for the canvas Edit
    ToText() {
        if this.rows.Length = 0
            return ""
        out := ""
        for i, row in this.rows
            out .= (i > 1 ? "`n" : "") row.cmdLine
        return out
    }

    ; Parse Edit text back into command lines (user may type/edit)
    ; Empty / blank-only => no lines (Run blocked)
    LinesFromText(text) {
        lines := []
        for line in StrSplit(text, "`n", "`r") {
            t := Trim(line)
            if t != ""
                lines.Push(t)
        }
        return lines
    }

    HasEmptySlotsInText(text) {
        ; Heuristic: trailing = with nothing after (--grep=) or dangling required placeholders
        for line in this.LinesFromText(text) {
            if RegExMatch(line, "--grep=\s*$")
                return true
            if RegExMatch(line, "i)\b(codegen|open|show-trace|screenshot|pdf)\s*$")
                return true  ; verb alone without trailing args when slots required
        }
        return false
    }
}
