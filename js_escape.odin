package ohtml

import "core:strings"

// js_escape_string escapes a string for safe embedding in JavaScript.
// Returns s unchanged (no allocation) if no escaping is needed.
js_escape_string :: proc(s: string) -> string {
	// Fast path: check if any character needs escaping.
	needs_escape := false
	for ch in s {
		switch ch {
		case '\\', '\'', '"', '<', '>', '&', '=', '\n', '\r', '\t', 0:
			needs_escape = true
			break
		case:
			if ch < 0x20 {
				needs_escape = true
				break
			}
		}
	}
	if !needs_escape {
		return s
	}

	b: strings.Builder
	for ch in s {
		switch ch {
		case '\\':
			strings.write_string(&b, `\\`)
		case '\'':
			strings.write_string(&b, `\'`)
		case '"':
			strings.write_string(&b, `\"`)
		case '<':
			strings.write_string(&b, `\u003C`)
		case '>':
			strings.write_string(&b, `\u003E`)
		case '&':
			strings.write_string(&b, `\u0026`)
		case '=':
			strings.write_string(&b, `\u003D`)
		case '\n':
			strings.write_string(&b, `\n`)
		case '\r':
			strings.write_string(&b, `\r`)
		case '\t':
			strings.write_string(&b, `\t`)
		case 0:
			strings.write_string(&b, `\u0000`)
		case:
			if ch < 0x20 {
				n := int(ch)
				strings.write_string(&b, `\u`)
				strings.write_byte(&b, HEX_DIGITS_UPPER[(n >> 12) & 0xf])
				strings.write_byte(&b, HEX_DIGITS_UPPER[(n >> 8) & 0xf])
				strings.write_byte(&b, HEX_DIGITS_UPPER[(n >> 4) & 0xf])
				strings.write_byte(&b, HEX_DIGITS_UPPER[n & 0xf])
			} else {
				strings.write_rune(&b, ch)
			}
		}
	}
	return strings.to_string(b)
}
