package ohtml

import "core:strings"

// url_query_escape percent-encodes a string for use in URL query parameters.
// Returns s unchanged (no allocation) if no escaping is needed.
url_query_escape :: proc(s: string) -> string {
	// Fast path: check if any character needs escaping.
	needs_escape := false
	for ch in s {
		is_safe :=
			(ch >= 'A' && ch <= 'Z') ||
			(ch >= 'a' && ch <= 'z') ||
			(ch >= '0' && ch <= '9') ||
			ch == '-' ||
			ch == '_' ||
			ch == '.' ||
			ch == '~'
		if !is_safe {
			needs_escape = true
			break
		}
	}
	if !needs_escape {
		return s
	}

	b: strings.Builder
	for ch in s {
		switch {
		case (ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9'):
			strings.write_rune(&b, ch)
		case ch == '-' || ch == '_' || ch == '.' || ch == '~':
			strings.write_rune(&b, ch)
		case:
			// Percent-encode each byte of the UTF-8 representation.
			buf: [4]u8
			n := _encode_rune(buf[:], ch)
			for i in 0 ..< n {
				strings.write_byte(&b, '%')
				strings.write_byte(&b, HEX_DIGITS_UPPER[buf[i] >> 4])
				strings.write_byte(&b, HEX_DIGITS_UPPER[buf[i] & 0xf])
			}
		}
	}
	return strings.to_string(b)
}

// _encode_rune encodes a rune to UTF-8 bytes, returns number of bytes written.
@(private = "file")
_encode_rune :: proc(buf: []u8, r: rune) -> int {
	c := u32(r)
	if c < 0x80 {
		buf[0] = u8(c)
		return 1
	}
	if c < 0x800 {
		buf[0] = u8(0xC0 | (c >> 6))
		buf[1] = u8(0x80 | (c & 0x3F))
		return 2
	}
	if c < 0x10000 {
		buf[0] = u8(0xE0 | (c >> 12))
		buf[1] = u8(0x80 | ((c >> 6) & 0x3F))
		buf[2] = u8(0x80 | (c & 0x3F))
		return 3
	}
	buf[0] = u8(0xF0 | (c >> 18))
	buf[1] = u8(0x80 | ((c >> 12) & 0x3F))
	buf[2] = u8(0x80 | ((c >> 6) & 0x3F))
	buf[3] = u8(0x80 | (c & 0x3F))
	return 4
}
