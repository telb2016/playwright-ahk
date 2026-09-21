Windows Desktop UIA recordings (Tab 3)
=====================================
JSON files here are produced by PlaywrightAhkApp Tab 3.
kind: windows-uia

Playback order:
1. Window Class + ProcessName hard gate
2. Ranked UIA targets (AutomationId → Name+ControlType → LocalizedType+index)
3. Optional Strict fullscreen spots (client-area % checksums; never taskbar)
4. Display profile (resolution/DPI/monitors) must match or hard-fail early

Soft window-relative clicks are last-resort for control identity only.
These files are gitignored (except this README / .gitkeep).
