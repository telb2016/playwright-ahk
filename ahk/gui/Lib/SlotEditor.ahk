; SlotEditor.ahk — dark modal dialog for puzzle-piece slots (replaces InputBox)
#Requires AutoHotkey v2.0
#Include Theme.ahk

class SlotEditor {
    ; Remember last OK values per piece label+slot (session + optional ini path)
    static LastValues := Map()
    static IniPath := ""

    static SetIniPath(path) {
        SlotEditor.IniPath := path
        SlotEditor.LoadPersisted()
    }

    static CacheKey(pieceLabel, slotName) => pieceLabel "|" slotName

    static LoadPersisted() {
        path := SlotEditor.IniPath
        if path = "" || !FileExist(path)
            return
        try {
            ; Ini section SlotMemory — keys are label_slot with unsafe chars flattened
            ; We store as SlotMemory / key=value lines via IniRead of known slots on demand.
        }
    }

    static Remember(pieceLabel, name, val) {
        key := SlotEditor.CacheKey(pieceLabel, name)
        SlotEditor.LastValues[key] := val
        path := SlotEditor.IniPath
        if path = ""
            return
        safe := SlotEditor.IniKey(pieceLabel, name)
        try IniWrite(val, path, "SlotMemory", safe)
    }

    static Recall(pieceLabel, name) {
        key := SlotEditor.CacheKey(pieceLabel, name)
        if SlotEditor.LastValues.Has(key)
            return SlotEditor.LastValues[key]
        path := SlotEditor.IniPath
        if path = "" || !FileExist(path)
            return ""
        safe := SlotEditor.IniKey(pieceLabel, name)
        try {
            v := IniRead(path, "SlotMemory", safe, "")
            if v != "" {
                SlotEditor.LastValues[key] := v
                return v
            }
        }
        return ""
    }

    static IniKey(pieceLabel, name) {
        s := pieceLabel "_" name
        s := RegExReplace(s, "[^\w\-]+", "_")
        if StrLen(s) > 60
            s := SubStr(s, 1, 60)
        return s
    }

    ; Prompt for all slots on a piece.
    ; Returns Map(name -> value) on OK, or "" on cancel / failed required.
    static Prompt(piece, ownerHwnd := 0) {
        slots := piece.Has("slots") ? piece["slots"] : []
        if !(slots is Array) || slots.Length = 0
            return Map()

        label := piece.Has("label") ? piece["label"] : "piece"
        resultMap := ""
        done := false

        opts := "+AlwaysOnTop -MinimizeBox -MaximizeBox +MinSize460x200"
        if ownerHwnd
            opts .= " +Owner" ownerHwnd

        g := Gui(opts, "Slot editor — " label)
        Theme.StyleGui(g)
        g.MarginX := 16
        g.MarginY := 12

        g.Add("Text", "w420 c" Theme.Fg,
            "Fill slots for:  " label)
        g.Add("Text", "w420 c" Theme.FgDim,
            "* = required   ·   Esc / Cancel aborts the drop   ·   Browse for file/out")

        edits := []
        for slot in slots {
            name := slot.Has("name") ? slot["name"] : "value"
            required := slot.Has("required") && slot["required"]
            def := SlotEditor.DefaultFor(name, piece)
            recalled := SlotEditor.Recall(label, name)
            if recalled != ""
                def := recalled
            star := required ? " *" : ""
            g.Add("Text", "xm w420 c" Theme.FgDim, name star)

            browseable := (name = "file" || name = "out")
            if browseable {
                ed := g.Add("Edit", "xm w320 h26", def)
                Theme.StyleEdit(ed)
                btnBrowse := g.Add("Button", "x+8 w90 h26", "Browse…")
                Theme.StyleButton(btnBrowse)
                btnBrowse.OnEvent("Click", SlotEditor.BrowseClick.Bind(ed, name, ownerHwnd))
            } else {
                ed := g.Add("Edit", "xm w420 h26", def)
                Theme.StyleEdit(ed)
            }
            edits.Push({ name: name, required: required, ed: ed })
        }

        errLbl := g.Add("Text", "xm w420 h18 c" Theme.Err, "")
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
                    ; Light validation
                    if item.name = "url" && val != "" && !RegExMatch(val, "i)^https?://") && !RegExMatch(val, "i)^file://") {
                        errLbl.Value := "URL should start with http(s):// (or file://)"
                        try item.ed.Focus()
                        return
                    }
                    vals[item.name] := val
                }
                for item in edits {
                    if vals.Has(item.name) && vals[item.name] != ""
                        SlotEditor.Remember(label, item.name, vals[item.name])
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
        ; Center over owner when possible
        showOpts := "w460"
        if ownerHwnd {
            try {
                WinGetPos(&ox, &oy, &ow, &oh, "ahk_id " ownerHwnd)
                sx := ox + Max(Round((ow - 460) / 2), 0)
                sy := oy + Max(Round((oh - 280) / 2), 40)
                showOpts .= " x" sx " y" sy
            }
        }
        g.Show(showOpts)
        if edits.Length
            try edits[1].ed.Focus()
        WinWaitClose("ahk_id " hwnd)
        return resultMap
    }

    static BrowseClick(ed, name, ownerHwnd := 0, *) {
        opts := ""
        if ownerHwnd
            opts := "Owner" ownerHwnd
        if name = "file" {
            path := FileSelect(1, , "Select trace / report file", "Trace/Zip (*.zip)|*.zip|All (*.*)|*.*")
        } else {
            ; out — save-as style
            path := FileSelect("S 16", , "Output file", "PNG/PDF (*.png;*.pdf)|*.png;*.pdf|All (*.*)|*.*")
        }
        if path != ""
            ed.Value := path
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
