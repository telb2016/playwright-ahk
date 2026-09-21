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
    static SuppressClick := false
    static HookInstalled := false

    ; Register a chip button HWND → piece Map
    static RegisterChip(hwnd, piece) {
        if hwnd
            ChipDrag.ChipHwnds[hwnd] := piece
    }

    static SetCanvas(hwnd) {
        ChipDrag.CanvasHwnd := hwnd
    }

    ; onDropCb(piece) — called when a drag is released over the canvas
    static Install(onDropCb) {
        ChipDrag.OnDrop := onDropCb
        if ChipDrag.HookInstalled
            return
        ; WM_LBUTTONDOWN = 0x0201 — fires on the control that was clicked
        OnMessage(0x0201, ChipDrag.OnLButtonDown)
        ChipDrag.HookInstalled := true
    }

    static OnLButtonDown(wParam, lParam, msg, hwnd) {
        if !ChipDrag.ChipHwnds.Has(hwnd)
            return
        ; Only drag when puzzle tab chips are relevant (caller may clear map)
        piece := ChipDrag.ChipHwnds[hwnd]
        MouseGetPos(&mx, &my)
        ChipDrag.State := {
            piece: piece,
            startX: mx,
            startY: my,
            dragging: false,
            hwnd: hwnd
        }
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
            if over
                ToolTip("Release to drop on canvas")
            else
                ToolTip("Drag to canvas · Esc cancels")
        }
    }

    static EndDrag() {
        st := ChipDrag.State
        ChipDrag.State := ""
        ToolTip()
        wasDragging := IsObject(st) && st.dragging
        ChipDrag.HideGhost()
        if !wasDragging
            return
        ; Suppress the Button Click that follows a drag
        ChipDrag.SuppressClick := true
        SetTimer(() => (ChipDrag.SuppressClick := false), -400)
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
        MouseGetPos(, , , &ctrlHwnd, 2)
        if !ctrlHwnd
            return false
        if ctrlHwnd = target
            return true
        ; Walk parents a few levels (Edit may report child)
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

    static ShowGhost(piece, mx, my) {
        ChipDrag.HideGhost()
        label := piece.Has("label") ? piece["label"] : "piece"
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
    }

    ; Allow Esc to cancel an in-progress drag
    static Cancel() {
        if !IsObject(ChipDrag.State)
            return false
        SetTimer(ChipDrag.Poll, 0)
        ChipDrag.State := ""
        ChipDrag.SuppressClick := true
        SetTimer(() => (ChipDrag.SuppressClick := false), -400)
        ChipDrag.HideGhost()
        return true
    }
}
