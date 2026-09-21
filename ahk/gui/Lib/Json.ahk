; Json.ahk — minimal UTF-8 JSON parse/stringify for AHK v2 (objects/arrays/scalars)
#Requires AutoHotkey v2.0

class Json {
    static Parse(text) {
        p := Json.Parser(text)
        return p.ParseValue()
    }

    static Stringify(val, indent := 0) {
        return Json._Str(val, indent, 0)
    }

    static _Str(val, indent, level) {
        if val is String {
            return '"' Json._Esc(val) '"'
        }
        if val is Number
            return String(val)
        if Type(val) = "Object" && !(val is Array) && !(val is Map) {
            ; AHK object with own props
            parts := []
            for k, v in val.OwnProps()
                parts.Push('"' Json._Esc(k) '": ' Json._Str(v, indent, level + 1))
            return "{" JoinComma(parts) "}"
        }
        if val is Map {
            parts := []
            for k, v in val
                parts.Push('"' Json._Esc(String(k)) '": ' Json._Str(v, indent, level + 1))
            return "{" JoinComma(parts) "}"
        }
        if val is Array {
            parts := []
            for v in val
                parts.Push(Json._Str(v, indent, level + 1))
            return "[" JoinComma(parts) "]"
        }
        if val = true
            return "true"
        if val = false
            return "false"
        return "null"

        JoinComma(arr) {
            out := ""
            for i, s in arr
                out .= (i > 1 ? ", " : "") s
            return out
        }
    }

    static _Esc(s) {
        s := StrReplace(s, "\", "\\")
        s := StrReplace(s, '"', '\"')
        s := StrReplace(s, "`n", "\n")
        s := StrReplace(s, "`r", "\r")
        s := StrReplace(s, "`t", "\t")
        return s
    }

    class Parser {
        s := ""
        i := 1
        n := 0

        __New(text) {
            this.s := text
            this.n := StrLen(text)
            this.i := 1
        }

        Peek() => SubStr(this.s, this.i, 1)
        Next() {
            ch := SubStr(this.s, this.i, 1)
            this.i += 1
            return ch
        }

        SkipWs() {
            loop {
                ch := this.Peek()
                if ch = "" || !InStr(" `t`r`n", ch)
                    break
                this.i += 1
            }
        }

        ParseValue() {
            this.SkipWs()
            ch := this.Peek()
            if ch = "{"
                return this.ParseObject()
            if ch = "["
                return this.ParseArray()
            if ch = '"'
                return this.ParseString()
            if ch = "t" || ch = "f" || ch = "n"
                return this.ParseLiteral()
            if ch = "-" || (ch >= "0" && ch <= "9")
                return this.ParseNumber()
            throw Error("JSON: unexpected '" ch "' at " this.i)
        }

        ParseObject() {
            this.Next() ; {
            obj := Map()
            this.SkipWs()
            if this.Peek() = "}" {
                this.Next()
                return obj
            }
            loop {
                this.SkipWs()
                if this.Peek() != '"'
                    throw Error("JSON: object key expected at " this.i)
                key := this.ParseString()
                this.SkipWs()
                if this.Next() != ":"
                    throw Error("JSON: expected : at " this.i)
                obj[key] := this.ParseValue()
                this.SkipWs()
                ch := this.Next()
                if ch = "}"
                    return obj
                if ch != ","
                    throw Error("JSON: expected , or } at " this.i)
            }
        }

        ParseArray() {
            this.Next() ; [
            arr := []
            this.SkipWs()
            if this.Peek() = "]" {
                this.Next()
                return arr
            }
            loop {
                arr.Push(this.ParseValue())
                this.SkipWs()
                ch := this.Next()
                if ch = "]"
                    return arr
                if ch != ","
                    throw Error("JSON: expected , or ] at " this.i)
            }
        }

        ParseString() {
            this.Next() ; "
            out := ""
            loop {
                ch := this.Next()
                if ch = ""
                    throw Error("JSON: unterminated string")
                if ch = '"'
                    return out
                if ch = "\" {
                    esc := this.Next()
                    switch esc {
                        case '"', "\", "/":
                            out .= esc
                        case "b":
                            out .= "`b"
                        case "f":
                            out .= "`f"
                        case "n":
                            out .= "`n"
                        case "r":
                            out .= "`r"
                        case "t":
                            out .= "`t"
                        case "u":
                            hex := SubStr(this.s, this.i, 4)
                            this.i += 4
                            out .= Chr(Integer("0x" hex))
                        default:
                            out .= esc
                    }
                } else
                    out .= ch
            }
        }

        ParseLiteral() {
            if SubStr(this.s, this.i, 4) = "true" {
                this.i += 4
                return 1
            }
            if SubStr(this.s, this.i, 5) = "false" {
                this.i += 5
                return 0
            }
            if SubStr(this.s, this.i, 4) = "null" {
                this.i += 4
                return ""
            }
            throw Error("JSON: bad literal at " this.i)
        }

        ParseNumber() {
            start := this.i
            if this.Peek() = "-"
                this.i += 1
            while (ch := this.Peek()) != "" && ((ch >= "0" && ch <= "9") || ch = "." || ch = "e" || ch = "E" || ch = "+" || ch = "-")
                this.i += 1
            raw := SubStr(this.s, start, this.i - start)
            if InStr(raw, ".") || InStr(StrLower(raw), "e")
                return Float(raw)
            return Integer(raw)
        }
    }
}
