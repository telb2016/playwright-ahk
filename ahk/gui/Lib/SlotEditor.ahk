; SlotEditor.ahk — dark modal dialog for puzzle-piece slots (replaces InputBox)
#Requires AutoHotkey v2.0
#Include Theme.ahk

class SlotEditor {
    ; Prompt for all slots on a piece.
    ; Returns Map(name -> value) on OK, or "" on cancel / failed required.
    static Prompt(piece, ownerHwnd := 0) {
        slots := piece.Has("slots") ? piece["slots"] : []
        if !(slots is Array) || slots.Length = 0
            return Map()

        label := piece.Has("label") ? piece["label"] : "piece"
        resultMap := ""
        done := false

        opts := "+AlwaysOnTop -MinimizeBox -MaximizeBox +MinSize420x180"
        if ownerHwnd
            opts .= " +Owner" ownerHwnd

        g := Gui(opts, "Slot editor — " label)
        Theme.StyleGui(g)
        g.MarginX := 16
        g.MarginY := 12

        g.Add("Text", "w390 c" Theme.Fg,
            "Fill slots for:  " label)
        g.Add("Text", "w390 c" Theme.FgDim,
            "* = required   ·   Esc / Cancel aborts the drop")

        edits := []
        for slot in slots {
            name := slot.Has("name") ? slot["name"] : "value"
            required := slot.Has("required") && slot["required"]
            def := SlotEditor.DefaultFor(name, piece)
            star := required ? " *" : ""
            g.Add("Text", "xm w390 c" Theme.FgDim, name star)
            ed := g.Add("Edit", "xm w390 h26", def)
            Theme.StyleEdit(ed)
            edits.Push({ name: name, required: required, ed: ed })
        }

        errLbl := g.Add("Text", "xm w390 h18 c" Theme.Err, "")
        try errLbl.SetFont("s9 c" Theme.Err, "Segoe UI")

        btnOk := g.Add("Button", "xm w120 h32 Default", "OK")
        Theme.StyleButton(btnOk, true)
        btnCancel := g.Add("Button", "x+12 w120 h32", "Cancel")
        Theme.StyleButton(btnCancel)

        Finish(ok) {
            if done
                return
            if ok {
                vals := Map()
                for item in edits {
                    val := Trim(item.ed.Value)
                    if item.required && val = "" {
                        errLbl.Value := "Required slot empty: " item.name
                        try item.ed.Focus()
                        return
                    }
                    vals[item.name] := val
                }
                resultMap := vals
            } else {
                resultMap := ""
            }
            done := true
            g.Destroy()
        }

        btnOk.OnEvent("Click", (*) => Finish(true))
        btnCancel.OnEvent("Click", (*) => Finish(false))
        g.OnEvent("Close", (*) => Finish(false))
        g.OnEvent("Escape", (*) => Finish(false))

        hwnd := g.Hwnd
        Theme.ApplyDarkTitleBar(hwnd)
        g.Show("w430")
        ; Focus first edit
        if edits.Length
            try edits[1].ed.Focus()
        WinWaitClose("ahk_id " hwnd)
        return resultMap
    }

    static DefaultFor(name, piece) {
        label := piece.Has("label") ? piece["label"] : ""
        if name = "url"
            return "https://playwright.dev"
        if name = "out"
            return InStr(label, "pdf") ? "page.pdf" : "shot.png"
        if name = "file"
            return "trace.zip"
        if name = "grep"
            return ""
        return ""
    }
}
