; ScreenSpots.ahk — hybrid verifier for Tab 3 (Strict fullscreen spots)
; Client-area % samples only (never taskbar/clock/tray). Settle-before-hash.
; UIA still identifies the control; spots confirm screen/client state.
#Requires AutoHotkey v2.0

class ScreenSpots {
    static Version := 1
    ; Fractional anchors inside CLIENT area (inset — avoids window chrome bleed)
    static Anchors := [
        [0.08, 0.08], [0.50, 0.08], [0.92, 0.08],
        [0.08, 0.50], [0.50, 0.50], [0.92, 0.50],
        [0.08, 0.88], [0.50, 0.88], [0.92, 0.88]
    ]
    static DefaultDelta := 28          ; ±RGB channel tolerance (AA/theme flicker)
    static DefaultPassRatio := 0.67    ; partial spot pass (~6 of 9)
    static SettleMs := 200             ; unchanged window for settle
    static SettleSlackMs := 50
    static SettleDelta := 12           ; tighter while proving stability

    ; ---- Display profile (hard-fail if playback differs) ----
    ; True when window client covers most of the primary (or virtual) screen.
    static IsProbablyFullscreen(hwnd) {
        rect := ScreenSpots.GetClientScreenRect(hwnd)
        if rect = ""
            return false
        sw := A_ScreenWidth
        sh := A_ScreenHeight
        try {
            sw := Max(sw, SysGet(78))
            sh := Max(sh, SysGet(79))
        }
        ; Client covers ≥92% of screen area and is near origin-ish OR covers virtually all
        area := rect["w"] * rect["h"]
        sarea := Max(sw * sh, 1)
        if area / sarea >= 0.92
            return true
        return false
    }

    static CaptureDisplayProfile() {
        monCount := 0
        try monCount := SysGet(80)  ; SM_CMONITORS
        catch
            monCount := 1
        dpi := 96
        try dpi := DllCall("user32\GetDpiForSystem", "uint")
        catch {
            try dpi := A_ScreenDPI
        }
        scale := Round(dpi / 96, 2)
        return Map(
            "screenW", A_ScreenWidth,
            "screenH", A_ScreenHeight,
            "dpi", dpi,
            "scale", scale,
            "monitors", monCount,
            "virtualW", SysGet(78),
            "virtualH", SysGet(79)
        )
    }

    static ProfilesEqual(a, b) {
        if !(a is Map) || !(b is Map)
            return false
        keys := ["screenW", "screenH", "dpi", "monitors"]
        for k in keys {
            if !a.Has(k) || !b.Has(k)
                return false
            if Integer(a[k]) != Integer(b[k])
                return false
        }
        return true
    }

    static ProfileDiffMessage(recorded, current) {
        bits := []
        for k in ["screenW", "screenH", "dpi", "scale", "monitors"] {
            rv := recorded.Has(k) ? recorded[k] : "?"
            cv := current.Has(k) ? current[k] : "?"
            if String(rv) != String(cv)
                bits.Push(k "=" cv " (recorded " rv ")")
        }
        return "HARD-FAIL display profile changed: " (bits.Length ? StrJoinSimple(bits, ", ") : "mismatch")
    }

    ; Client rect of hwnd in SCREEN coords (excludes non-client / taskbar outside window).
    static GetClientScreenRect(hwnd) {
        if !hwnd
            return ""
        try {
            ; Client top-left in screen coords
            pt := Buffer(8, 0)
            NumPut("int", 0, pt, 0)
            NumPut("int", 0, pt, 4)
            if !DllCall("user32\ClientToScreen", "ptr", hwnd, "ptr", pt)
                return ""
            x := NumGet(pt, 0, "int")
            y := NumGet(pt, 4, "int")
            ; Client size
            rc := Buffer(16, 0)
            if !DllCall("user32\GetClientRect", "ptr", hwnd, "ptr", rc)
                return ""
            w := NumGet(rc, 8, "int")
            h := NumGet(rc, 12, "int")
            if w < 32 || h < 32
                return ""
            return Map("x", x, "y", y, "w", w, "h", h)
        } catch {
            return ""
        }
    }

    static SampleColorAtClientPct(hwnd, rx, ry) {
        rect := ScreenSpots.GetClientScreenRect(hwnd)
        if rect = ""
            return ""
        ; Clamp pct into safe inset band (already anchors are inset)
        rx := Max(0.02, Min(0.98, rx))
        ry := Max(0.02, Min(0.98, ry))
        sx := rect["x"] + Round(rx * rect["w"])
        sy := rect["y"] + Round(ry * rect["h"])
        try {
            ; PixelGetColor returns 0xBBGGRR by default; use RGB mode
            col := PixelGetColor(sx, sy, "RGB")
            return Map("rx", rx, "ry", ry, "rgb", col, "sx", sx, "sy", sy)
        } catch {
            return ""
        }
    }

    static SampleAll(hwnd) {
        spots := []
        for a in ScreenSpots.Anchors {
            s := ScreenSpots.SampleColorAtClientPct(hwnd, a[1], a[2])
            if s != ""
                spots.Push(s)
        }
        return spots
    }

    ; Wait until two samples (SettleMs apart) match within SettleDelta — skip caret/anim flakes.
    static SettleAndSample(hwnd, settleMs := 0) {
        if settleMs <= 0
            settleMs := ScreenSpots.SettleMs
        first := ScreenSpots.SampleAll(hwnd)
        if first.Length < 4
            return { ok: false, spots: first, message: "too few client spots" }
        Sleep(settleMs)
        second := ScreenSpots.SampleAll(hwnd)
        if !ScreenSpots.SpotsStable(first, second, ScreenSpots.SettleDelta) {
            ; One retry with a bit more wait
            Sleep(ScreenSpots.SettleSlackMs + 80)
            third := ScreenSpots.SampleAll(hwnd)
            if !ScreenSpots.SpotsStable(second, third, ScreenSpots.SettleDelta)
                return { ok: false, spots: third, message: "settle failed — client still changing (anim/caret?)" }
            return { ok: true, spots: third, message: "settled (retry)" }
        }
        return { ok: true, spots: second, message: "settled" }
    }

    static SpotsStable(a, b, delta) {
        if a.Length != b.Length || a.Length = 0
            return false
        for i, sa in a {
            sb := b[i]
            if !ScreenSpots.RgbWithin(sa["rgb"], sb["rgb"], delta)
                return false
        }
        return true
    }

    static RgbWithin(c1, c2, delta) {
        ; Colors as 0xRRGGBB integers
        try {
            r1 := (c1 >> 16) & 0xFF, g1 := (c1 >> 8) & 0xFF, b1 := c1 & 0xFF
            r2 := (c2 >> 16) & 0xFF, g2 := (c2 >> 8) & 0xFF, b2 := c2 & 0xFF
            return Abs(r1 - r2) <= delta && Abs(g1 - g2) <= delta && Abs(b1 - b2) <= delta
        } catch {
            return false
        }
    }

    ; Capture pack for a step (or session header): profile + settled client spots as %.
    static CapturePack(hwnd, noteFullscreen := false) {
        pack := Map(
            "version", ScreenSpots.Version,
            "strictSpots", true,
            "noteFullscreen", !!noteFullscreen,
            "display", ScreenSpots.CaptureDisplayProfile(),
            "delta", ScreenSpots.DefaultDelta,
            "passRatio", ScreenSpots.DefaultPassRatio,
            "coordSpace", "client-pct",
            "spots", []
        )
        settled := ScreenSpots.SettleAndSample(hwnd)
        if !settled.ok {
            pack["settleOk"] := false
            pack["settleMessage"] := settled.message
            ; Still store last sample for debugging — playback may soft-warn
            pack["spots"] := ScreenSpots.SpotsForStorage(settled.spots)
            return pack
        }
        pack["settleOk"] := true
        pack["settleMessage"] := settled.message
        pack["spots"] := ScreenSpots.SpotsForStorage(settled.spots)
        return pack
    }

    ; Persist only rx/ry/% + rgb — never absolute screen pixels as identity.
    static SpotsForStorage(spots) {
        out := []
        for s in spots {
            out.Push(Map(
                "rx", Round(s["rx"], 4),
                "ry", Round(s["ry"], 4),
                "rgb", s["rgb"]
            ))
        }
        return out
    }

    ; Compare recorded pack against live client. Returns {ok, message, passed, total, soft}.
    static VerifyPack(hwnd, pack, delta := 0, passRatio := 0) {
        if !(pack is Map) || !pack.Has("spots")
            return { ok: true, message: "no spots pack — skipped", passed: 0, total: 0, soft: true }
        ; Display profile hard gate
        if pack.Has("display") {
            cur := ScreenSpots.CaptureDisplayProfile()
            if !ScreenSpots.ProfilesEqual(pack["display"], cur)
                return { ok: false, message: ScreenSpots.ProfileDiffMessage(pack["display"], cur), passed: 0, total: 0, soft: false }
        }
        if delta <= 0
            delta := pack.Has("delta") ? Integer(pack["delta"]) : ScreenSpots.DefaultDelta
        if passRatio <= 0
            passRatio := pack.Has("passRatio") ? Float(pack["passRatio"]) : ScreenSpots.DefaultPassRatio

        settled := ScreenSpots.SettleAndSample(hwnd)
        if !settled.ok {
            return { ok: false, message: "spot settle failed on playback: " settled.message, passed: 0, total: pack["spots"].Length, soft: false }
        }
        live := settled.spots
        recorded := pack["spots"]
        if !(recorded is Array) || recorded.Length = 0
            return { ok: true, message: "empty spots — skipped", passed: 0, total: 0, soft: true }

        passed := 0
        total := recorded.Length
        for i, rec in recorded {
            if !(rec is Map) || !rec.Has("rx")
                continue
            ; Prefer matching by rx/ry rather than index (stable)
            liveSpot := ScreenSpots.FindLiveSpot(live, rec["rx"], rec["ry"])
            if liveSpot = ""
                continue
            if ScreenSpots.RgbWithin(rec["rgb"], liveSpot["rgb"], delta)
                passed += 1
        }
        need := Max(1, Ceil(total * passRatio))
        if passed >= need
            return { ok: true, message: "spots OK " passed "/" total " (±" delta " RGB, need " need ")", passed: passed, total: total, soft: false }
        return { ok: false, message: "FAIL spots " passed "/" total " (need " need " within ±" delta " RGB)", passed: passed, total: total, soft: false }
    }

    static FindLiveSpot(live, rx, ry) {
        best := ""
        bestD := 999
        for s in live {
            d := Abs(s["rx"] - rx) + Abs(s["ry"] - ry)
            if d < bestD {
                bestD := d
                best := s
            }
        }
        return bestD < 0.05 ? best : ""
    }
}

StrJoinSimple(arr, sep) {
    out := ""
    for i, v in arr
        out .= (i > 1 ? sep : "") v
    return out
}
