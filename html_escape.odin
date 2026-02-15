package ohtml

import "core:strings"

// html_escape_string escapes special HTML characters in s.
// Returns s unchanged (no allocation) if no escaping is needed.
html_escape_string :: proc(s: string) -> string {
	// Fast path: scan for any character that needs escaping.
	needs_escape := false
	for ch in s {
		switch ch {
		case '&', '<', '>', '"', '\'':
			needs_escape = true
			break
		}
	}
	if !needs_escape {
		return s
	}

	b: strings.Builder
	strings.builder_init_len_cap(&b, 0, len(s) + len(s) / 8) // pre-allocate ~112.5%
	for ch in s {
		switch ch {
		case '&':
			strings.write_string(&b, "&amp;")
		case '<':
			strings.write_string(&b, "&lt;")
		case '>':
			strings.write_string(&b, "&gt;")
		case '"':
			strings.write_string(&b, "&#34;")
		case '\'':
			strings.write_string(&b, "&#39;")
		case:
			strings.write_rune(&b, ch)
		}
	}
	return strings.to_string(b)
}
