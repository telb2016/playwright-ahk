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
}
