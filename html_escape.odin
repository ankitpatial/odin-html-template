package ohtml

import "core:strings"

// html_escape_string escapes special HTML characters in s.
// Returns s unchanged (no allocation) if no escaping is needed.
// Uses byte-level iteration for ASCII (the common case) to avoid rune decode overhead.
html_escape_string :: proc(s: string) -> string {
	// Fast path: scan bytes for any character that needs escaping.
	needs_escape := false
	for i in 0 ..< len(s) {
		switch s[i] {
		case '&', '<', '>', '"', '\'':
			needs_escape = true
			break
		}
	}
	if !needs_escape {
		return s
	}

	b: strings.Builder
	strings.builder_init_len_cap(&b, 0, len(s) + len(s) / 8)
	last := 0
	for i in 0 ..< len(s) {
		repl: string
		switch s[i] {
		case '&':
			repl = "&amp;"
		case '<':
			repl = "&lt;"
		case '>':
			repl = "&gt;"
		case '"':
			repl = "&#34;"
		case '\'':
			repl = "&#39;"
		case:
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
