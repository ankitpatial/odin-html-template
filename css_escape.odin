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
// Uses byte-level chunk-copy: writes safe ASCII spans in bulk.
css_escape_string :: proc(s: string) -> string {
	// Fast path: check if any byte needs escaping.
	needs_escape := false
	for i in 0 ..< len(s) {
		ch := s[i]
		if !((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9')) {
			needs_escape = true
			break
		}
	}
	if !needs_escape {
		return s
	}

	b: strings.Builder
	strings.builder_init_len_cap(&b, 0, len(s) * 2)
	last := 0
	for ch, i in s {
		if (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9') {
			continue
		}
		// Write safe chunk before this character.
		// Note: i here is the byte offset of the rune start.
		strings.write_string(&b, s[last:i])
		// Escape as \HHHHHH (6 hex digits).
		n := int(ch)
		strings.write_byte(&b, '\\')
		strings.write_byte(&b, HEX_DIGITS[(n >> 20) & 0xf])
		strings.write_byte(&b, HEX_DIGITS[(n >> 16) & 0xf])
		strings.write_byte(&b, HEX_DIGITS[(n >> 12) & 0xf])
		strings.write_byte(&b, HEX_DIGITS[(n >> 8) & 0xf])
		strings.write_byte(&b, HEX_DIGITS[(n >> 4) & 0xf])
		strings.write_byte(&b, HEX_DIGITS[n & 0xf])
		// Advance past this rune's UTF-8 bytes.
		rune_len := _utf8_rune_len(ch)
		last = i + rune_len
	}
	// Write any remaining safe tail.
	strings.write_string(&b, s[last:])
	return strings.to_string(b)
}

// _utf8_rune_len returns the number of bytes in the UTF-8 encoding of a rune.
@(private = "file")
_utf8_rune_len :: proc(r: rune) -> int {
	c := u32(r)
	if c < 0x80 {return 1}
	if c < 0x800 {return 2}
	if c < 0x10000 {return 3}
	return 4
}
