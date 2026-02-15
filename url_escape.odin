package ohtml

import "core:strings"

// url_query_escape percent-encodes a string for use in URL query parameters.
// Returns s unchanged (no allocation) if no escaping is needed.
// Uses byte-level chunk-copy: writes safe spans in bulk.
url_query_escape :: proc(s: string) -> string {
	// Fast path: check if any byte needs escaping.
	needs_escape := false
	for i in 0 ..< len(s) {
		ch := s[i]
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
	strings.builder_init_len_cap(&b, 0, len(s) + len(s) / 2)
	last := 0
	for i in 0 ..< len(s) {
		ch := s[i]
		is_safe :=
			(ch >= 'A' && ch <= 'Z') ||
			(ch >= 'a' && ch <= 'z') ||
			(ch >= '0' && ch <= '9') ||
			ch == '-' ||
			ch == '_' ||
			ch == '.' ||
			ch == '~'
		if is_safe {
			continue
		}
		// Write the safe chunk before this byte.
		strings.write_string(&b, s[last:i])
		// Percent-encode this byte.
		strings.write_byte(&b, '%')
		strings.write_byte(&b, HEX_DIGITS_UPPER[ch >> 4])
		strings.write_byte(&b, HEX_DIGITS_UPPER[ch & 0xf])
		last = i + 1
	}
	// Write any remaining safe tail.
	strings.write_string(&b, s[last:])
	return strings.to_string(b)
}
