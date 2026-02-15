package ohtml

import "core:strings"

@(rodata)
HEX_DIGITS := [16]u8 {
	'0',
	'1',
	'2',
	'3',
	'4',
	'5',
	'6',
	'7',
	'8',
	'9',
	'a',
	'b',
	'c',
	'd',
	'e',
	'f',
}

@(rodata)
HEX_DIGITS_UPPER := [16]u8 {
	'0',
	'1',
	'2',
	'3',
	'4',
	'5',
	'6',
	'7',
	'8',
	'9',
	'A',
	'B',
	'C',
	'D',
	'E',
	'F',
}

// css_escape_string escapes a string for safe embedding in CSS.
// Returns s unchanged (no allocation) if no escaping is needed.
css_escape_string :: proc(s: string) -> string {
	// Fast path: check if any character needs escaping.
	needs_escape := false
	for ch in s {
		if !((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9')) {
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
		case ch >= 'a' && ch <= 'z', ch >= 'A' && ch <= 'Z', ch >= '0' && ch <= '9':
			strings.write_rune(&b, ch)
		case:
			// Escape as \HHHHHH (6 hex digits).
			n := int(ch)
			strings.write_byte(&b, '\\')
			strings.write_byte(&b, HEX_DIGITS[(n >> 20) & 0xf])
			strings.write_byte(&b, HEX_DIGITS[(n >> 16) & 0xf])
			strings.write_byte(&b, HEX_DIGITS[(n >> 12) & 0xf])
			strings.write_byte(&b, HEX_DIGITS[(n >> 8) & 0xf])
			strings.write_byte(&b, HEX_DIGITS[(n >> 4) & 0xf])
			strings.write_byte(&b, HEX_DIGITS[n & 0xf])
		}
	}
	return strings.to_string(b)
}
