package tpls

import "core:strings"

@(rodata)
_HEX_UPPER := [16]u8{'0','1','2','3','4','5','6','7','8','9','A','B','C','D','E','F'}

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

