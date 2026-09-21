; Theme.ahk — dark UI helpers for Playwright AHK overnight GUI
#Requires AutoHotkey v2.0

class Theme {
    static Bg := "1E1E1E"
    static BgPanel := "252526"
    static BgInput := "2D2D30"
    static Fg := "D4D4D4"
    static FgDim := "9D9D9D"
    static Accent := "0E639C"
    static AccentHot := "1177BB"
    static Chip := "3C3C3C"
    static ChipFg := "E0E0E0"
    static Ok := "4EC9B0"
    static Err := "F44747"
    static Border := "3E3E42"
    static Train := "0A4D73"
    static DropTarget := "264F78"
    static DropTargetFg := "9CDCFE"
    static ErrBg := "3A1D1D"

    ; Prefer immersive dark titlebar (Win10 1903+ / Win11). Falls back silently.
    static ApplyDarkTitleBar(hwnd) {
        if !hwnd
            return false
        val := 1
        ; 20 = DWMWA_USE_IMMERSIVE_DARK_MODE (newer); 19 = older builds
        ok := DllCall("dwmapi\DwmSetWindowAttribute", "ptr", hwnd, "int", 20, "int*", &val, "int", 4)
        if ok != 0 {
            val := 1
            ok := DllCall("dwmapi\DwmSetWindowAttribute", "ptr", hwnd, "int", 19, "int*", &val, "int", 4)
        }
        return ok = 0
    }

    ; Soft rounded outer region via SetWindowRgn (CreateRoundRectRgn). No-op on failure.
    static ApplyRoundedRegion(hwnd, w, h, radius := 16) {
        if !hwnd || w < 32 || h < 32
            return false
        hrgn := DllCall("gdi32\CreateRoundRectRgn"
            , "int", 0, "int", 0, "int", w + 1, "int", h + 1
            , "int", radius, "int", radius, "ptr")
        if !hrgn
            return false
        ; SetWindowRgn takes ownership of hrgn on success
        if DllCall("user32\SetWindowRgn", "ptr", hwnd, "ptr", hrgn, "int", 1) {
            return true
        }
        DllCall("gdi32\DeleteObject", "ptr", hrgn)
        return false
    }

    static StyleGui(g) {
        g.BackColor := Theme.Bg
        g.SetFont("s10 c" Theme.Fg, "Segoe UI")
    }

    static StyleEdit(ctrl, multiline := true) {
        opts := "Background" Theme.BgInput " c" Theme.Fg
        ctrl.Opt(opts)
        try ctrl.SetFont("s10 c" Theme.Fg, "Consolas")
    }

    static StyleButton(ctrl, accent := false) {
        if accent
            ctrl.Opt("Background" Theme.Accent " cFFFFFF")
        else
            ctrl.Opt("Background" Theme.Chip " c" Theme.ChipFg)
        try ctrl.SetFont("s9 c" (accent ? "FFFFFF" : Theme.ChipFg), "Segoe UI")
    }

    static StyleChip(ctrl) {
        ctrl.Opt("Background" Theme.Chip " c" Theme.ChipFg)
        try ctrl.SetFont("s8 c" Theme.ChipFg, "Segoe UI")
    }

    static StyleStatus(ctrl) {
        ctrl.Opt("Background" Theme.BgPanel " c" Theme.FgDim)
        try ctrl.SetFont("s9 c" Theme.FgDim, "Segoe UI")
    }

    static StyleStatusTone(ctrl, tone := "") {
        if !IsObject(ctrl)
            return
        if tone = "ok" {
            ctrl.Opt("Background" Theme.BgPanel " c" Theme.Ok)
            try ctrl.SetFont("s9 c" Theme.Ok, "Segoe UI")
        } else if tone = "err" {
            ctrl.Opt("Background" Theme.BgPanel " c" Theme.Err)
            try ctrl.SetFont("s9 c" Theme.Err, "Segoe UI")
        } else {
            Theme.StyleStatus(ctrl)
        }
    }

    static StyleTabBtn(ctrl, active := false) {
        if active
            ctrl.Opt("Background" Theme.Accent " cFFFFFF")
        else
            ctrl.Opt("Background" Theme.BgPanel " c" Theme.FgDim)
        try ctrl.SetFont("s10 Bold c" (active ? "FFFFFF" : Theme.FgDim), "Segoe UI")
    }

    ; Flash / highlight an Edit as a drop target during chip drag.
    static HighlightDropTarget(ctrl, on := true) {
        if !IsObject(ctrl)
            return
        if on
            ctrl.Opt("Background" Theme.DropTarget " c" Theme.DropTargetFg)
        else
            Theme.StyleEdit(ctrl)
    }

    ; Brief OK / error flash on an Edit (e.g. canvas after successful drop).
    static FlashEdit(ctrl, ok := true, ms := 220) {
        if !IsObject(ctrl)
            return
        if ok
            ctrl.Opt("Background" Theme.DropTarget " c" Theme.DropTargetFg)
        else
            ctrl.Opt("Background" Theme.ErrBg " c" Theme.Err)
        SetTimer(() => Theme.StyleEdit(ctrl), -Max(ms, 80))
    }

    ; Dark Yes/No confirm. Returns true if Yes. Default focus = No (safer).
    static ConfirmDark(message, title := "Playwright AHK", ownerHwnd := 0) {
        result := false
        done := false
        opts := "+AlwaysOnTop -MinimizeBox -MaximizeBox +MinSize360x140"
        if ownerHwnd
            opts .= " +Owner" ownerHwnd
        g := Gui(opts, title)
        Theme.StyleGui(g)
        g.MarginX := 16
        g.MarginY := 14
        g.Add("Text", "w340 c" Theme.Fg, message)
        btnYes := g.Add("Button", "xm w100 h30", "Yes")
        Theme.StyleButton(btnYes, true)
        btnNo := g.Add("Button", "x+12 w100 h30 Default", "No")
        Theme.StyleButton(btnNo)
        Finish(yes) {
            if done
                return
            done := true
            result := yes
            g.Destroy()
        }
        btnYes.OnEvent("Click", (*) => Finish(true))
        btnNo.OnEvent("Click", (*) => Finish(false))
        g.OnEvent("Close", (*) => Finish(false))
        g.OnEvent("Escape", (*) => Finish(false))
        hwnd := g.Hwnd
        Theme.ApplyDarkTitleBar(hwnd)
        g.Show("w380")
        try btnNo.Focus()
        WinWaitClose("ahk_id " hwnd)
        return result
    }


    ; Dark OK-only info dialog.
    static InfoDark(message, title := "Playwright AHK", ownerHwnd := 0) {
        done := false
        opts := "+AlwaysOnTop -MinimizeBox -MaximizeBox +MinSize380x140"
        if ownerHwnd
            opts .= " +Owner" ownerHwnd
        g := Gui(opts, title)
        Theme.StyleGui(g)
        g.MarginX := 16
        g.MarginY := 14
        g.Add("Text", "w360 c" Theme.Fg, message)
        btn := g.Add("Button", "xm w100 h30 Default", "OK")
        Theme.StyleButton(btn, true)
        Finish(*) {
            if done
                return
            done := true
            g.Destroy()
        }
        btn.OnEvent("Click", Finish)
        g.OnEvent("Close", Finish)
        g.OnEvent("Escape", Finish)
        hwnd := g.Hwnd
        Theme.ApplyDarkTitleBar(hwnd)
        g.Show("w400")
        try btn.Focus()
        WinWaitClose("ahk_id " hwnd)
    }


    static StyleCheck(ctrl) {
        if !IsObject(ctrl)
            return
        try ctrl.Opt("c" Theme.Fg)
        try ctrl.SetFont("s9 c" Theme.Fg, "Segoe UI")
    }
}
