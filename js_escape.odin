package ohtml

import "core:strings"

// js_escape_string escapes a string for safe embedding in JavaScript.
// Returns s unchanged (no allocation) if no escaping is needed.
// Uses chunk-copy: writes safe spans in bulk, only switching to per-char for specials.
js_escape_string :: proc(s: string) -> string {
	// Fast path: check if any byte needs escaping.
	needs_escape := false
	for i in 0 ..< len(s) {
		switch s[i] {
		case '\\', '\'', '"', '<', '>', '&', '=', '\n', '\r', '\t', 0:
			needs_escape = true
			break
		case:
			if s[i] < 0x20 {
				needs_escape = true
				break
			}
		}
	}
	if !needs_escape {
		return s
	}

	b: strings.Builder
	strings.builder_init_len_cap(&b, 0, len(s) + len(s) / 4)
	last := 0
	for i in 0 ..< len(s) {
		repl: string
		switch s[i] {
		case '\\':
			repl = `\\`
		case '\'':
			repl = `\'`
		case '"':
			repl = `\"`
		case '<':
			repl = `\u003C`
		case '>':
			repl = `\u003E`
		case '&':
			repl = `\u0026`
		case '=':
			repl = `\u003D`
		case '\n':
			repl = `\n`
		case '\r':
			repl = `\r`
		case '\t':
			repl = `\t`
		case 0:
			repl = `\u0000`
		case:
			if s[i] < 0x20 {
				// Write safe chunk before this character.
				strings.write_string(&b, s[last:i])
				n := int(s[i])
				strings.write_string(&b, `\u`)
				strings.write_byte(&b, HEX_DIGITS_UPPER[(n >> 12) & 0xf])
				strings.write_byte(&b, HEX_DIGITS_UPPER[(n >> 8) & 0xf])
				strings.write_byte(&b, HEX_DIGITS_UPPER[(n >> 4) & 0xf])
				strings.write_byte(&b, HEX_DIGITS_UPPER[n & 0xf])
				last = i + 1
			}
			continue
		}
		// Write the safe chunk before this character, then the replacement.
		strings.write_string(&b, s[last:i])
		strings.write_string(&b, repl)
		last = i + 1
	}
	// Write any remaining safe tail.
	strings.write_string(&b, s[last:])
	return strings.to_string(b)
}
