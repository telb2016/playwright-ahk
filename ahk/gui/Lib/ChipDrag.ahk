; ChipDrag.ahk — true chip→canvas drag-drop (click-to-add remains the fallback)
#Requires AutoHotkey v2.0
#Include Theme.ahk

class ChipDrag {
    static Threshold := 8
    static State := ""
    static Ghost := ""
    static ChipHwnds := Map()
    static CanvasHwnd := 0
    static OnDrop := ""          ; callback(piece)
    static OnHover := ""         ; callback(overCanvas:bool) while dragging
    static CanStart := ""        ; callback() => bool (e.g. ActiveTab = 2)
    static SuppressClick := false
    static HookInstalled := false
    static LastOver := false
    static LastTip := ""
    static OwnerHwnd := 0        ; main app hwnd — cancel if focus leaves app/ghost

    static RegisterChip(hwnd, piece) {
        if hwnd
            ChipDrag.ChipHwnds[hwnd] := piece
    }

    static SetCanvas(hwnd) {
        ChipDrag.CanvasHwnd := hwnd
    }

    static SetOwner(hwnd) {
        ChipDrag.OwnerHwnd := hwnd
    }

    ; onDropCb(piece), optional onHoverCb(over), optional canStartCb()
    static Install(onDropCb, onHoverCb := "", canStartCb := "") {
        ChipDrag.OnDrop := onDropCb
        ChipDrag.OnHover := onHoverCb
        ChipDrag.CanStart := canStartCb
        if ChipDrag.HookInstalled
            return
        ; WM_LBUTTONDOWN = 0x0201 — fires on the control that was clicked
        OnMessage(0x0201, ChipDrag.OnLButtonDown)
        ChipDrag.HookInstalled := true
    }

    static OnLButtonDown(wParam, lParam, msg, hwnd) {
        if !ChipDrag.ChipHwnds.Has(hwnd)
            return
        ; Already dragging — ignore nested downs
        if IsObject(ChipDrag.State)
            return
        can := ChipDrag.CanStart
        if can && !can.Call()
            return
        piece := ChipDrag.ChipHwnds[hwnd]
        MouseGetPos(&mx, &my)
        ChipDrag.State := {
            piece: piece,
            startX: mx,
            startY: my,
            dragging: false,
            hwnd: hwnd
        }
        ChipDrag.LastOver := false
        ChipDrag.LastTip := ""
        SetTimer(ChipDrag.Poll, 16)
    }

    static Poll() {
        st := ChipDrag.State
        if !IsObject(st) {
            SetTimer(ChipDrag.Poll, 0)
            return
        }
        if !GetKeyState("LButton", "P") {
            SetTimer(ChipDrag.Poll, 0)
            ChipDrag.EndDrag()
            return
        }
        ; Esc while dragging
        if GetKeyState("Escape", "P") {
            SetTimer(ChipDrag.Poll, 0)
            ChipDrag.Cancel()
            return
        }
        ; Cancel if owner app lost foreground (alt-tab / tray hide)
        if ChipDrag.OwnerHwnd && !ChipDrag.FocusInApp() {
            SetTimer(ChipDrag.Poll, 0)
            ChipDrag.Cancel()
            return
        }
        MouseGetPos(&mx, &my)
        if !st.dragging {
            dx := Abs(mx - st.startX)
            dy := Abs(my - st.startY)
            if dx < ChipDrag.Threshold && dy < ChipDrag.Threshold
                return
            st.dragging := true
            ChipDrag.ShowGhost(st.piece, mx, my)
        } else {
            ChipDrag.MoveGhost(mx, my)
            over := ChipDrag.IsOverCanvas()
            if over != ChipDrag.LastOver {
                ChipDrag.LastOver := over
                hover := ChipDrag.OnHover
                if hover
                    hover.Call(over)
            }
            tip := over ? "Release to drop on canvas" : "Drag to canvas · Esc cancels"
            if tip != ChipDrag.LastTip {
                ChipDrag.LastTip := tip
                ToolTip(tip)
            }
        }
    }

    static FocusInApp() {
        owner := ChipDrag.OwnerHwnd
        if !owner
            return true
        try {
            active := WinGetID("A")
            if !active
                return true
            if active = owner
                return true
            g := ChipDrag.Ghost
            if IsObject(g) && active = g.Hwnd
                return true
            ; Child of owner?
            hwnd := active
            loop 8 {
                parent := DllCall("user32\GetParent", "ptr", hwnd, "ptr")
                if !parent
                    break
                if parent = owner
                    return true
                hwnd := parent
            }
        }
        return false
    }

    static EndDrag() {
        st := ChipDrag.State
        ChipDrag.State := ""
        ChipDrag.LastTip := ""
        ToolTip()
        wasDragging := IsObject(st) && st.dragging
        ChipDrag.HideGhost()
        hover := ChipDrag.OnHover
        if hover
            hover.Call(false)
        ChipDrag.LastOver := false
        if !wasDragging
            return
        ChipDrag.SuppressClick := true
        ; Longer suppress so SlotEditor modal click doesn't re-fire chip Click
        SetTimer(() => (ChipDrag.SuppressClick := false), -800)
        if ChipDrag.IsOverCanvas() && IsObject(st.piece) {
            cb := ChipDrag.OnDrop
            if cb
                cb.Call(st.piece)
        }
    }

    static ConsumeClick() {
        if ChipDrag.SuppressClick {
            ChipDrag.SuppressClick := false
            return true
        }
        return false
    }

    static IsOverCanvas() {
        target := ChipDrag.CanvasHwnd
        if !target
            return false
        ; Prefer hit-test by screen rect (works even with WS_EX_TRANSPARENT ghost)
        if ChipDrag.PointInHwnd(target) {
            return true
        }
        MouseGetPos(, , , &ctrlHwnd, 2)
        if !ctrlHwnd
            return false
        if ctrlHwnd = target
            return true
        hwnd := ctrlHwnd
        loop 4 {
            parent := DllCall("user32\GetParent", "ptr", hwnd, "ptr")
            if !parent
                break
            if parent = target
                return true
            hwnd := parent
        }
        return false
    }

    static PointInHwnd(hwnd) {
        if !hwnd
            return false
        MouseGetPos(&mx, &my)
        rect := Buffer(16, 0)
        if !DllCall("user32\GetWindowRect", "ptr", hwnd, "ptr", rect)
            return false
        left := NumGet(rect, 0, "int")
        top := NumGet(rect, 4, "int")
        right := NumGet(rect, 8, "int")
        bottom := NumGet(rect, 12, "int")
        return mx >= left && mx < right && my >= top && my < bottom
    }

    static ShowGhost(piece, mx, my) {
        ChipDrag.HideGhost()
        label := piece.Has("label") ? piece["label"] : "piece"
        ; Truncate long labels so ghost stays compact
        if StrLen(label) > 36
            label := SubStr(label, 1, 33) "…"
        g := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20 +Border")
        g.BackColor := Theme.Accent
        g.MarginX := 8
        g.MarginY := 4
        t := g.Add("Text", "cFFFFFF", "✦ " label)
        try t.SetFont("s9 Bold cFFFFFF", "Segoe UI")
        g.Show("x" (mx + 12) " y" (my + 12) " AutoSize NoActivate")
        ChipDrag.Ghost := g
    }

    static MoveGhost(mx, my) {
        g := ChipDrag.Ghost
        if !IsObject(g)
            return
        try g.Show("x" (mx + 12) " y" (my + 12) " NoActivate")
    }

    static HideGhost() {
        g := ChipDrag.Ghost
        ChipDrag.Ghost := ""
        if IsObject(g) {
            try g.Destroy()
        }
        ToolTip()
        ChipDrag.LastTip := ""
    }

    static Cancel() {
        if !IsObject(ChipDrag.State)
            return false
        SetTimer(ChipDrag.Poll, 0)
        ChipDrag.State := ""
        ChipDrag.SuppressClick := true
        SetTimer(() => (ChipDrag.SuppressClick := false), -800)
        ChipDrag.HideGhost()
        hover := ChipDrag.OnHover
        if hover
            hover.Call(false)
        ChipDrag.LastOver := false
        return true
    }

    ; True while a drag gesture is active (past threshold or not).
    static IsDragging() {
        return IsObject(ChipDrag.State)
    }
}
