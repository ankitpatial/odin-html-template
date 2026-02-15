package tpls

import "core:strings"

@(rodata)
_HEX_UPPER := [16]u8{'0','1','2','3','4','5','6','7','8','9','A','B','C','D','E','F'}

@(rodata)
_HEX_LOWER := [16]u8{'0','1','2','3','4','5','6','7','8','9','a','b','c','d','e','f'}

_ohtml_html_escape :: proc(s: string) -> string {
	for i in 0 ..< len(s) {
		switch s[i] {
		case '&', '<', '>', '"', '\'':
			return _html_escape_slow(s, i)
		}
	}
	return s
}

@(private="file")
_html_escape_slow :: proc(s: string, start: int) -> string {
	b: strings.Builder
	strings.builder_init_len_cap(&b, 0, len(s) + len(s) / 8)
	last := 0
	strings.write_string(&b, s[:start])
	last = start
	for i in start ..< len(s) {
		repl: string
		switch s[i] {
		case '&':  repl = "&amp;"
		case '<':  repl = "&lt;"
		case '>':  repl = "&gt;"
		case '"':  repl = "&#34;"
		case '\'': repl = "&#39;"
		case:      continue
		}
		strings.write_string(&b, s[last:i])
		strings.write_string(&b, repl)
		last = i + 1
	}
	strings.write_string(&b, s[last:])
	return strings.to_string(b)
}

_ohtml_js_escape :: proc(s: string) -> string {
	for i in 0 ..< len(s) {
		switch s[i] {
		case '\\', '\'', '"', '<', '>', '&', '=', '\n', '\r', '\t', 0:
			return _js_escape_slow(s, i)
		case:
			if s[i] < 0x20 { return _js_escape_slow(s, i) }
		}
	}
	return s
}

@(private="file")
_js_escape_slow :: proc(s: string, start: int) -> string {
	b: strings.Builder
	strings.builder_init_len_cap(&b, 0, len(s) + len(s) / 4)
	last := start
	strings.write_string(&b, s[:start])
	for i in start ..< len(s) {
		repl: string
		switch s[i] {
		case '\\': repl = "\\\\"
		case '\'': repl = "\\'"
		case '"':  repl = "\\\""
		case '<':  repl = "\\u003C"
		case '>':  repl = "\\u003E"
		case '&':  repl = "\\u0026"
		case '=':  repl = "\\u003D"
		case '\n': repl = "\\n"
		case '\r': repl = "\\r"
		case '\t': repl = "\\t"
		case 0:    repl = "\\u0000"
		case:
			if s[i] < 0x20 {
				strings.write_string(&b, s[last:i])
				n := int(s[i])
				strings.write_string(&b, "\\u")
				strings.write_byte(&b, _HEX_UPPER[(n >> 12) & 0xf])
				strings.write_byte(&b, _HEX_UPPER[(n >> 8) & 0xf])
				strings.write_byte(&b, _HEX_UPPER[(n >> 4) & 0xf])
				strings.write_byte(&b, _HEX_UPPER[n & 0xf])
				last = i + 1
			}
			continue
		}
		strings.write_string(&b, s[last:i])
		strings.write_string(&b, repl)
		last = i + 1
	}
	strings.write_string(&b, s[last:])
	return strings.to_string(b)
}

_ohtml_css_escape :: proc(s: string) -> string {
	for i in 0 ..< len(s) {
		ch := s[i]
		if !((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9')) {
			return _css_escape_slow(s, i)
		}
	}
	return s
}

@(private="file")
_css_escape_slow :: proc(s: string, start: int) -> string {
	b: strings.Builder
	strings.builder_init_len_cap(&b, 0, len(s) * 2)
	strings.write_string(&b, s[:start])
	last := start
	for ch, i in s[start:] {
		idx := i + start
		if (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9') {
			continue
		}
		strings.write_string(&b, s[last:idx])
		n := int(ch)
		strings.write_byte(&b, '\\')
		strings.write_byte(&b, _HEX_LOWER[(n >> 20) & 0xf])
		strings.write_byte(&b, _HEX_LOWER[(n >> 16) & 0xf])
		strings.write_byte(&b, _HEX_LOWER[(n >> 12) & 0xf])
		strings.write_byte(&b, _HEX_LOWER[(n >> 8) & 0xf])
		strings.write_byte(&b, _HEX_LOWER[(n >> 4) & 0xf])
		strings.write_byte(&b, _HEX_LOWER[n & 0xf])
		rune_len := 1
		c := u32(ch)
		if c >= 0x80 { rune_len = 2 }
		if c >= 0x800 { rune_len = 3 }
		if c >= 0x10000 { rune_len = 4 }
		last = idx + rune_len
	}
	strings.write_string(&b, s[last:])
	return strings.to_string(b)
}

_ohtml_url_filter :: proc(s: string) -> string {
	if _url_is_safe(s) { return s }
	return "#ZodinAutoUrl"
}

@(private="file")
_url_is_safe :: proc(s: string) -> bool {
	lo := proc(s: string, prefix: string) -> bool {
		if len(s) < len(prefix) { return false }
		for i in 0 ..< len(prefix) {
			c := s[i]
			if c >= 'A' && c <= 'Z' { c += 32 }
			if c != prefix[i] { return false }
		}
		return true
	}
	if lo(s, "javascript:") { return false }
	if lo(s, "vbscript:") { return false }
	if lo(s, "data:") {
		if lo(s, "data:image/") { return true }
		return false
	}
	return true
}

_ohtml_url_query_escape :: proc(s: string) -> string {
	for i in 0 ..< len(s) {
		ch := s[i]
		is_safe := (ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z') ||
			(ch >= '0' && ch <= '9') || ch == '-' || ch == '_' || ch == '.' || ch == '~'
		if !is_safe { return _url_query_escape_slow(s, i) }
	}
	return s
}

@(private="file")
_url_query_escape_slow :: proc(s: string, start: int) -> string {
	b: strings.Builder
	strings.builder_init_len_cap(&b, 0, len(s) + len(s) / 2)
	last := start
	strings.write_string(&b, s[:start])
	for i in start ..< len(s) {
		ch := s[i]
		is_safe := (ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z') ||
			(ch >= '0' && ch <= '9') || ch == '-' || ch == '_' || ch == '.' || ch == '~'
		if is_safe {
			continue
		}
		strings.write_string(&b, s[last:i])
		strings.write_byte(&b, '%')
		strings.write_byte(&b, _HEX_UPPER[ch >> 4])
		strings.write_byte(&b, _HEX_UPPER[ch & 0xf])
		last = i + 1
	}
	strings.write_string(&b, s[last:])
	return strings.to_string(b)
}

_ohtml_write_int :: proc(buf: []u8, val: i64) -> string {
	if val == 0 {
		buf[len(buf) - 1] = '0'
		return string(buf[len(buf) - 1:])
	}
	neg := val < 0
	n := val if !neg else -val
	i := len(buf)
	for n > 0 {
		i -= 1
		buf[i] = u8('0' + n % 10)
		n /= 10
	}
	if neg {
		i -= 1
		buf[i] = '-'
	}
	return string(buf[i:])
}

