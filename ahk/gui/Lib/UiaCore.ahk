; UiaCore.ahk — minimal UI Automation (IUIAutomation) helpers for Tab 3 desktop recorder
; Primary path: AutomationId / Name+ControlType / LocalizedType+index. No PixelSearch as verifier.
#Requires AutoHotkey v2.0

class UiaCore {
    static UIA := ""
    static Ready := false
    static LastError := ""

    ; ControlTypeIds (UIA_ControlTypeIds)
    static CT := Map(
        "Button", 50000, "Calendar", 50001, "CheckBox", 50002, "ComboBox", 50003,
        "Edit", 50004, "Hyperlink", 50005, "Image", 50006, "ListItem", 50007,
        "List", 50008, "Menu", 50009, "MenuBar", 50010, "MenuItem", 50011,
        "ProgressBar", 50012, "RadioButton", 50013, "ScrollBar", 50014, "Slider", 50015,
        "Spinner", 50016, "StatusBar", 50017, "Tab", 50018, "TabItem", 50019,
        "Text", 50020, "ToolBar", 50021, "ToolTip", 50022, "Tree", 50023,
        "TreeItem", 50024, "Custom", 50025, "Group", 50026, "Thumb", 50027,
        "DataGrid", 50028, "DataItem", 50029, "Document", 50030, "SplitButton", 50031,
        "Window", 50032, "Pane", 50033, "Header", 50034, "HeaderItem", 50035,
        "Table", 50036, "TitleBar", 50037, "Separator", 50038
    )

    ; Property IDs
    static P_RuntimeId := 30000
    static P_BoundingRectangle := 30001
    static P_ProcessId := 30002
    static P_ControlType := 30003
    static P_LocalizedControlType := 30004
    static P_Name := 30005
    static P_AcceleratorKey := 30006
    static P_AccessKey := 30007
    static P_HasKeyboardFocus := 30008
    static P_IsKeyboardFocusable := 30009
    static P_IsEnabled := 30010
    static P_AutomationId := 30011
    static P_ClassName := 30012
    static P_HelpText := 30013
    static P_ClickablePoint := 30014
    static P_Culture := 30015
    static P_IsControlElement := 30016
    static P_IsContentElement := 30017
    static P_LabeledBy := 30018
    static P_IsPassword := 30019
    static P_NativeWindowHandle := 30020
    static P_ItemType := 30021
    static P_IsOffscreen := 30022
    static P_Orientation := 30023
    static P_FrameworkId := 30024

    static TreeScope_Element := 1
    static TreeScope_Children := 2
    static TreeScope_Descendants := 4
    static TreeScope_Subtree := 7

    static Ensure() {
        if UiaCore.Ready && IsObject(UiaCore.UIA)
            return true
        UiaCore.LastError := ""
        try {
            ; CLSID_CUIAutomation
            UiaCore.UIA := ComObject("{ff48dba4-60ef-4201-aa87-54103eef594e}")
            UiaCore.Ready := true
            return true
        } catch as e1 {
            try {
                UiaCore.UIA := ComObject("UIAutomationClient.CUIAutomation")
                UiaCore.Ready := true
                return true
            } catch as e2 {
                UiaCore.LastError := "UI Automation COM unavailable: " e1.Message " / " e2.Message
                UiaCore.Ready := false
                return false
            }
        }
    }

    static ControlTypeName(id) {
        for name, cid in UiaCore.CT {
            if cid = id
                return name
        }
        return "Custom"
    }

    ; Element under screen point → descriptor Map (or "" on failure).
    static ElementFromPoint(sx, sy) {
        if !UiaCore.Ensure()
            return ""
        try {
            pt := ComObject("UIAutomationClient.tagPOINT")
        } catch {
            ; Build POINT via buffer passed to GetElementFromPoint — use ComCall style
        }
        try {
            ; IUIAutomation::GetElementFromPoint(POINT) — AHK ComObject accepts object with x,y or two ints via alternate
            el := UiaCore.UIA.ElementFromPoint(sx | (sy << 32))
        } catch {
            try {
                ; Some builds expose GetElementFromPoint
                el := UiaCore.UIA.GetElementFromPoint(sx, sy)
            } catch as e {
                UiaCore.LastError := "ElementFromPoint failed: " e.Message
                return ""
            }
        }
        if !IsObject(el)
            return ""
        return UiaCore.Describe(el)
    }

    ; Safer ElementFromPoint using DllCall-built POINT via ComCall on vtable when needed.
    static ElementFromScreenPoint(sx, sy) {
        if !UiaCore.Ensure()
            return ""
        el := ""
        ; POINT as Int64: low dword = x, high dword = y (two's complement for negatives)
        pt := (sy & 0xFFFFFFFF) << 32 | (sx & 0xFFFFFFFF)
        try el := UiaCore.UIA.ElementFromPoint(pt)
        catch as e1 {
            try el := UiaCore.UIA.ElementFromPoint(sx, sy)
            catch as e2 {
                UiaCore.LastError := "ElementFromPoint: " e1.Message " / " e2.Message
                return ""
            }
        }
        if !IsObject(el)
            return ""
        return UiaCore.Describe(el)
    }

    static CurrentProperty(el, propId) {
        try {
            return el.CurrentCurrentPropertyValue
                ? el.CurrentCurrentPropertyValue(propId)
                : el.GetCurrentPropertyValue(propId)
        } catch {
            try return el.GetCurrentPropertyValue(propId)
            catch {
                return ""
            }
        }
    }

    static Prop(el, propId) {
        try {
            return el.GetCurrentPropertyValue(propId)
        } catch {
            return ""
        }
    }

    static Describe(el) {
        d := Map()
        d["AutomationId"] := String(UiaCore.Prop(el, UiaCore.P_AutomationId))
        d["Name"] := String(UiaCore.Prop(el, UiaCore.P_Name))
        ct := UiaCore.Prop(el, UiaCore.P_ControlType)
        try ct := Integer(ct)
        catch
            ct := 0
        d["ControlType"] := ct
        d["ControlTypeName"] := UiaCore.ControlTypeName(ct)
        d["LocalizedControlType"] := String(UiaCore.Prop(el, UiaCore.P_LocalizedControlType))
        d["ClassName"] := String(UiaCore.Prop(el, UiaCore.P_ClassName))
        d["FrameworkId"] := String(UiaCore.Prop(el, UiaCore.P_FrameworkId))
        try d["ProcessId"] := Integer(UiaCore.Prop(el, UiaCore.P_ProcessId))
        catch
            d["ProcessId"] := 0
        d["IsEnabled"] := !!UiaCore.Prop(el, UiaCore.P_IsEnabled)
        d["IsOffscreen"] := !!UiaCore.Prop(el, UiaCore.P_IsOffscreen)

        ; Bounding rect → center (screen)
        try {
            rect := UiaCore.Prop(el, UiaCore.P_BoundingRectangle)
            ; SAFEARRAY or object with length 4
            if rect is Array || (IsObject(rect) && rect.Length = 4) {
                left := rect[1], top := rect[2], right := rect[3], bottom := rect[4]
            } else if IsObject(rect) {
                left := rect.left, top := rect.top, right := rect.right, bottom := rect.bottom
            } else {
                left := top := right := bottom := 0
            }
            d["Bounds"] := Map("left", left, "top", top, "right", right, "bottom", bottom)
            d["ClickX"] := Round((left + right) / 2)
            d["ClickY"] := Round((top + bottom) / 2)
        } catch {
            d["Bounds"] := Map()
            d["ClickX"] := 0
            d["ClickY"] := 0
        }

        ; Window ancestor info + hard-fail keys
        win := UiaCore.GetWindowInfo(el)
        d["Window"] := win

        ; Sibling index among same LocalizedControlType under parent (rank-3 key)
        d["ParentIndex"] := UiaCore.IndexAmongSiblings(el)

        ; Ranked target list (QC): try in order at playback
        d["Targets"] := UiaCore.BuildRankedTargets(d)
        return d
    }

    static BuildRankedTargets(d) {
        targets := []
        aid := Trim(d.Has("AutomationId") ? d["AutomationId"] : "")
        if aid != "" {
            targets.Push(Map(
                "rank", 1,
                "strategy", "AutomationId",
                "AutomationId", aid,
                "ControlType", d.Has("ControlType") ? d["ControlType"] : 0
            ))
        }
        name := Trim(d.Has("Name") ? d["Name"] : "")
        ct := d.Has("ControlType") ? d["ControlType"] : 0
        if name != "" && ct {
            targets.Push(Map(
                "rank", 2,
                "strategy", "Name+ControlType",
                "Name", name,
                "ControlType", ct
            ))
        }
        loc := Trim(d.Has("LocalizedControlType") ? d["LocalizedControlType"] : "")
        idx := d.Has("ParentIndex") ? d["ParentIndex"] : 0
        if loc != "" && idx > 0 {
            targets.Push(Map(
                "rank", 3,
                "strategy", "LocalizedType+Index",
                "LocalizedControlType", loc,
                "ParentIndex", idx,
                "ControlType", ct,
                "Name", name  ; soft hint
            ))
        }
        ; Soft last-resort metadata (never primary verifier) — relative click in window
        if d.Has("Bounds") && d.Has("Window") {
            w := d["Window"]
            b := d["Bounds"]
            if w.Has("X") && w["W"] > 0 && b.Has("left") {
                targets.Push(Map(
                    "rank", 99,
                    "strategy", "WindowRelativeSoft",
                    "relX", (Round((b["left"] + b["right"]) / 2) - w["X"]) / Max(w["W"], 1),
                    "relY", (Round((b["top"] + b["bottom"]) / 2) - w["Y"]) / Max(w["H"], 1),
                    "soft", true
                ))
            }
        }
        return targets
    }

    static GetWindowInfo(el) {
        info := Map("Title", "", "Class", "", "Hwnd", 0, "ProcessId", 0, "ProcessName", "", "X", 0, "Y", 0, "W", 0, "H", 0)
        try {
            hwnd := Integer(UiaCore.Prop(el, UiaCore.P_NativeWindowHandle))
        } catch
            hwnd := 0
        ; Walk up via WalkTree / GetParentElement for Window control type
        cur := el
        loop 12 {
            try {
                ct := Integer(UiaCore.Prop(cur, UiaCore.P_ControlType))
            } catch
                ct := 0
            try {
                nh := Integer(UiaCore.Prop(cur, UiaCore.P_NativeWindowHandle))
            } catch
                nh := 0
            if nh
                hwnd := nh
            if ct = UiaCore.CT["Window"] || (nh && WinExist("ahk_id " nh))
                break
            try cur := UiaCore.UIA.ControlViewWalker.GetParentElement(cur)
            catch {
                try cur := UiaCore.UIA.RawViewWalker.GetParentElement(cur)
                catch
                    break
            }
            if !IsObject(cur)
                break
        }
        if hwnd {
            info["Hwnd"] := hwnd
            try info["Title"] := WinGetTitle("ahk_id " hwnd)
            try info["Class"] := WinGetClass("ahk_id " hwnd)
            try {
                WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " hwnd)
                info["X"] := wx, info["Y"] := wy, info["W"] := ww, info["H"] := wh
            }
            try {
                pid := WinGetPID("ahk_id " hwnd)
                info["ProcessId"] := pid
                info["ProcessName"] := StrLower(WinGetProcessName("ahk_id " hwnd))
            }
        }
        try {
            if !info["ProcessId"]
                info["ProcessId"] := Integer(UiaCore.Prop(el, UiaCore.P_ProcessId))
        }
        return info
    }

    static IndexAmongSiblings(el) {
        ; 1-based index among siblings with same LocalizedControlType
        try {
            loc := String(UiaCore.Prop(el, UiaCore.P_LocalizedControlType))
            parent := UiaCore.UIA.ControlViewWalker.GetParentElement(el)
            if !IsObject(parent)
                return 0
            cond := UiaCore.UIA.CreateTrueCondition()
            kids := parent.FindAll(UiaCore.TreeScope_Children, cond)
            if !IsObject(kids)
                return 0
            idx := 0
            count := kids.Length
            loop count {
                kid := kids.GetElement(A_Index - 1)
                try kloc := String(UiaCore.Prop(kid, UiaCore.P_LocalizedControlType))
                catch
                    kloc := ""
                if kloc = loc {
                    idx += 1
                    ; Compare RuntimeId if possible
                    try {
                        if UiaCore.SameElement(kid, el)
                            return idx
                    } catch {
                        ; fallback Name+bounds
                        try {
                            if String(UiaCore.Prop(kid, UiaCore.P_Name)) = String(UiaCore.Prop(el, UiaCore.P_Name))
                                return idx
                        }
                    }
                }
            }
            return idx
        } catch {
            return 0
        }
    }

    static SameElement(a, b) {
        try {
            ra := a.GetRuntimeId()
            rb := b.GetRuntimeId()
            return String(ra) = String(rb)
        } catch {
            return false
        }
    }

    ; Find window hwnd matching recorded Window hard keys (class + process). Title soft.
    static FindWindowHwnd(winMap, timeoutMs := 3000) {
        if !(winMap is Map)
            return 0
        wantClass := winMap.Has("Class") ? winMap["Class"] : ""
        wantProc := winMap.Has("ProcessName") ? StrLower(winMap["ProcessName"]) : ""
        wantTitle := winMap.Has("Title") ? winMap["Title"] : ""
        ; Need at least one hard key — otherwise refuse (avoid clicking random windows)
        if wantClass = "" && wantProc = "" {
            UiaCore.LastError := "window descriptor missing Class and ProcessName"
            return 0
        }
        deadline := A_TickCount + timeoutMs
        while A_TickCount <= deadline {
            ; Prefer class + process hard match
            for hwnd in WinGetList() {
                try {
                    cls := WinGetClass("ahk_id " hwnd)
                    proc := StrLower(WinGetProcessName("ahk_id " hwnd))
                    title := WinGetTitle("ahk_id " hwnd)
                    classOk := (wantClass = "" || cls = wantClass)
                    procOk := (wantProc = "" || proc = wantProc)
                    if !(classOk && procOk)
                        continue
                    ; Soft title: exact or contains first 24 chars
                    if wantTitle != "" {
                        if title = wantTitle || (StrLen(wantTitle) > 8 && InStr(title, SubStr(wantTitle, 1, Min(24, StrLen(wantTitle)))))
                            return hwnd
                        ; class+proc matched but title drifted — still accept if both hard keys present
                        if wantClass != "" && wantProc != ""
                            return hwnd
                    } else {
                        return hwnd
                    }
                }
            }
            Sleep(80)
        }
        return 0
    }

    ; Resolve element from ranked targets under window root. Returns {el, strategy, soft} or "".
    static ResolveFromTargets(hwnd, targets, timeoutMs := 2500) {
        if !UiaCore.Ensure() || !hwnd
            return ""
        try root := UiaCore.UIA.ElementFromHandle(hwnd)
        catch {
            try root := UiaCore.UIA.GetElementFromHandle(hwnd)
            catch as e {
                UiaCore.LastError := e.Message
                return ""
            }
        }
        if !IsObject(root)
            return ""
        if !(targets is Array) || targets.Length = 0
            return ""

        deadline := A_TickCount + timeoutMs
        lastSoft := ""
        while A_TickCount <= deadline {
            for t in targets {
                if !(t is Map)
                    continue
                soft := t.Has("soft") && t["soft"]
                strat := t.Has("strategy") ? t["strategy"] : ""
                el := UiaCore.FindByStrategy(root, t)
                if IsObject(el) {
                    return { el: el, strategy: strat, soft: soft }
                }
                if soft
                    lastSoft := t
            }
            Sleep(60)
        }
        ; Soft fallback only after hard ranks exhausted — caller may use WindowRelative
        if IsObject(lastSoft)
            return { el: "", strategy: lastSoft["strategy"], soft: true, softTarget: lastSoft }
        return ""
    }

    static FindByStrategy(root, t) {
        strat := t.Has("strategy") ? t["strategy"] : ""
        try {
            if strat = "AutomationId" {
                aid := t["AutomationId"]
                cond := UiaCore.UIA.CreatePropertyCondition(UiaCore.P_AutomationId, aid)
                el := root.FindFirst(UiaCore.TreeScope_Descendants, cond)
                if IsObject(el) && t.Has("ControlType") && t["ControlType"] {
                    ct := Integer(UiaCore.Prop(el, UiaCore.P_ControlType))
                    if ct && ct != t["ControlType"] {
                        ; still accept AutomationId primary match
                    }
                }
                return IsObject(el) ? el : ""
            }
            if strat = "Name+ControlType" {
                c1 := UiaCore.UIA.CreatePropertyCondition(UiaCore.P_Name, t["Name"])
                c2 := UiaCore.UIA.CreatePropertyCondition(UiaCore.P_ControlType, t["ControlType"])
                cond := UiaCore.UIA.CreateAndCondition(c1, c2)
                return root.FindFirst(UiaCore.TreeScope_Descendants, cond)
            }
            if strat = "LocalizedType+Index" {
                loc := t["LocalizedControlType"]
                wantIdx := Integer(t["ParentIndex"])
                cond := UiaCore.UIA.CreateTrueCondition()
                all := root.FindAll(UiaCore.TreeScope_Descendants, cond)
                if !IsObject(all)
                    return ""
                ; Group by parent… approximate: scan all with matching LocalizedControlType and count
                ; Simpler: filter by LocalizedControlType property then take Nth
                try {
                    cLoc := UiaCore.UIA.CreatePropertyCondition(UiaCore.P_LocalizedControlType, loc)
                    matched := root.FindAll(UiaCore.TreeScope_Descendants, cLoc)
                    if IsObject(matched) && matched.Length >= wantIdx && wantIdx > 0
                        return matched.GetElement(wantIdx - 1)
                } catch {
                    ; fall through
                }
                ; Parent-scoped index: find any with Name hint
                if t.Has("Name") && t["Name"] != "" {
                    c1 := UiaCore.UIA.CreatePropertyCondition(UiaCore.P_Name, t["Name"])
                    if t.Has("ControlType") && t["ControlType"] {
                        c2 := UiaCore.UIA.CreatePropertyCondition(UiaCore.P_ControlType, t["ControlType"])
                        cond2 := UiaCore.UIA.CreateAndCondition(c1, c2)
                        return root.FindFirst(UiaCore.TreeScope_Descendants, cond2)
                    }
                    return root.FindFirst(UiaCore.TreeScope_Descendants, c1)
                }
            }
        } catch as e {
            UiaCore.LastError := e.Message
        }
        return ""
    }

    ; Invoke click via InvokePattern, else LegacyIAccessible, else clickable point.
    static InvokeClick(el) {
        if !IsObject(el)
            return false
        ; 10000 = UIA_InvokePatternId
        try {
            pat := el.GetCurrentPattern(10000)
            if IsObject(pat) {
                pat.Invoke()
                return true
            }
        }
        try {
            ; 10018 LegacyIAccessible
            pat := el.GetCurrentPattern(10018)
            if IsObject(pat) {
                pat.DoDefaultAction()
                return true
            }
        }
        try {
            ; Clickable point property
            cp := UiaCore.Prop(el, UiaCore.P_ClickablePoint)
            if IsObject(cp) {
                x := cp[1], y := cp[2]
                Click(x " " y)
                return true
            }
        }
        try {
            rect := UiaCore.Prop(el, UiaCore.P_BoundingRectangle)
            if rect is Array || (IsObject(rect) && rect.HasProp("Length") && rect.Length = 4) {
                x := Round((rect[1] + rect[3]) / 2)
                y := Round((rect[2] + rect[4]) / 2)
                Click(x " " y)
                return true
            }
        }
        return false
    }

    static InvokeRightClick(el) {
        if !IsObject(el)
            return false
        try {
            cp := UiaCore.Prop(el, UiaCore.P_ClickablePoint)
            if IsObject(cp) {
                Click(cp[1] " " cp[2] " Right")
                return true
            }
        }
        try {
            rect := UiaCore.Prop(el, UiaCore.P_BoundingRectangle)
            if rect is Array || (IsObject(rect) && rect.HasProp("Length") && rect.Length = 4) {
                x := Round((rect[1] + rect[3]) / 2)
                y := Round((rect[2] + rect[4]) / 2)
                Click(x " " y " Right")
                return true
            }
        }
        return false
    }

    ; Double-click at clickable point / bounds center (InvokePattern is single-activate).
    static InvokeDoubleClick(el) {
        if !IsObject(el)
            return false
        try {
            cp := UiaCore.Prop(el, UiaCore.P_ClickablePoint)
            if IsObject(cp) {
                Click(cp[1] " " cp[2] " 2")
                return true
            }
        }
        try {
            rect := UiaCore.Prop(el, UiaCore.P_BoundingRectangle)
            if rect is Array || (IsObject(rect) && rect.HasProp("Length") && rect.Length = 4) {
                x := Round((rect[1] + rect[3]) / 2)
                y := Round((rect[2] + rect[4]) / 2)
                Click(x " " y " 2")
                return true
            }
        }
        return false
    }

    ; Move cursor to element center (for wheel / focus) without clicking.
    static MoveToElement(el) {
        if !IsObject(el)
            return false
        try {
            cp := UiaCore.Prop(el, UiaCore.P_ClickablePoint)
            if IsObject(cp) {
                MouseMove(cp[1], cp[2], 0)
                return true
            }
        }
        try {
            rect := UiaCore.Prop(el, UiaCore.P_BoundingRectangle)
            if rect is Array || (IsObject(rect) && rect.HasProp("Length") && rect.Length = 4) {
                x := Round((rect[1] + rect[3]) / 2)
                y := Round((rect[2] + rect[4]) / 2)
                MouseMove(x, y, 0)
                return true
            }
        }
        return false
    }

    ; Focused UIA element → same descriptor Map as ElementFromScreenPoint (or "").
    static GetFocusedDescribe() {
        if !UiaCore.Ensure()
            return ""
        try {
            el := UiaCore.UIA.GetFocusedElement()
        } catch as e {
            UiaCore.LastError := "GetFocusedElement: " e.Message
            return ""
        }
        if !IsObject(el)
            return ""
        return UiaCore.Describe(el)
    }

    static SetFocus(el) {
        if !IsObject(el)
            return false
        try {
            el.SetFocus()
            return true
        } catch {
            return false
        }
    }

    ; ValuePattern (10002) SetValue, else LegacyIAccessible Value, else false.
    static SetValue(el, text) {
        if !IsObject(el)
            return false
        text := String(text)
        try {
            pat := el.GetCurrentPattern(10002)  ; UIA_ValuePatternId
            if IsObject(pat) {
                pat.SetValue(text)
                return true
            }
        }
        try {
            pat := el.GetCurrentPattern(10018)  ; LegacyIAccessible
            if IsObject(pat) {
                try pat.SetValue(text)
                catch {
                    try pat.Value := text
                    catch
                        return false
                }
                return true
            }
        }
        return false
    }

    ; Screen click-point for an element (clickable point, else bounds center).
    static ElementClickPoint(el) {
        if !IsObject(el)
            return ""
        try {
            cp := UiaCore.Prop(el, UiaCore.P_ClickablePoint)
            if IsObject(cp)
                return { x: Integer(cp[1]), y: Integer(cp[2]) }
        }
        try {
            rect := UiaCore.Prop(el, UiaCore.P_BoundingRectangle)
            if rect is Array || (IsObject(rect) && rect.HasProp("Length") && rect.Length = 4) {
                x := Round((rect[1] + rect[3]) / 2)
                y := Round((rect[2] + rect[4]) / 2)
                return { x: Integer(x), y: Integer(y) }
            }
        }
        return ""
    }

    ; LButton drag between two elements (Down at start → move → Up at end).
    static InvokeDrag(elStart, elEnd) {
        p1 := UiaCore.ElementClickPoint(elStart)
        p2 := UiaCore.ElementClickPoint(elEnd)
        if !(IsObject(p1) && IsObject(p2))
            return false
        return UiaCore.DragScreen(p1.x, p1.y, p2.x, p2.y)
    }

    ; Absolute screen-coordinate drag (CoordMode Screen for the gesture).
    static DragScreen(x1, y1, x2, y2) {
        try {
            CoordMode("Mouse", "Screen")
            MouseClickDrag("Left", Integer(x1), Integer(y1), Integer(x2), Integer(y2), 10)
            Sleep(30)
            return true
        }
        return false
    }

    ; Window-relative soft drag (last resort).
    static SoftDragRelative(hwnd, relX1, relY1, relX2, relY2) {
        if !hwnd
            return false
        try {
            WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " hwnd)
            if ww <= 0 || wh <= 0
                return false
            x1 := wx + Round(Float(relX1) * ww)
            y1 := wy + Round(Float(relY1) * wh)
            x2 := wx + Round(Float(relX2) * ww)
            y2 := wy + Round(Float(relY2) * wh)
            return UiaCore.DragScreen(x1, y1, x2, y2)
        }
        return false
    }

    static SoftClickRelative(hwnd, relX, relY, right := false, clickCount := 1) {
        if !hwnd
            return false
        try {
            WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " hwnd)
            x := wx + Round(relX * ww)
            y := wy + Round(relY * wh)
            if right
                Click(x " " y " Right")
            else if clickCount >= 2
                Click(x " " y " " Integer(clickCount))
            else
                Click(x " " y)
            return true
        }
        return false
    }

    ; Move to window-relative point then emit WheelUp/WheelDown notches (signed: +up / -down).
    static SoftWheelRelative(hwnd, relX, relY, notches) {
        if !hwnd
            return false
        notches := Integer(notches)
        if notches = 0
            return true
        try {
            WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " hwnd)
            x := wx + Round(relX * ww)
            y := wy + Round(relY * wh)
            MouseMove(x, y, 0)
            return UiaCore.WheelAtCursor(notches)
        }
        return false
    }

    static WheelAtCursor(notches) {
        notches := Integer(notches)
        if notches = 0
            return true
        dir := notches > 0 ? "WheelUp" : "WheelDown"
        n := Abs(notches)
        loop n
            Click(dir)
        return true
    }

    ; Wait until element matching ranked targets exists (verify).
    static WaitForTargets(hwnd, targets, timeoutMs := 4000) {
        r := UiaCore.ResolveFromTargets(hwnd, targets, timeoutMs)
        if IsObject(r) && IsObject(r.el)
            return r
        if IsObject(r) && r.HasProp("soft") && r.soft
            return r  ; soft only — caller decides
        return ""
    }
}
