package cli

import "core:strings"

// ---------------------------------------------------------------------------
// Emitter — helpers for generating formatted Odin source code
// ---------------------------------------------------------------------------

Emitter :: struct {
	buf:          strings.Builder,
	indent_level: int,
	temp_count:   int,
}

emitter_init :: proc(e: ^Emitter) {
	e.buf = strings.builder_make_len_cap(0, 4096)
	e.indent_level = 0
	e.temp_count = 0
}

emitter_destroy :: proc(e: ^Emitter) {
	strings.builder_destroy(&e.buf)
}

emitter_to_string :: proc(e: ^Emitter) -> string {
	return strings.to_string(e.buf)
}

// Write the current indentation.
_write_indent :: proc(e: ^Emitter) {
	for _ in 0 ..< e.indent_level {
		strings.write_byte(&e.buf, '\t')
	}
}

// emit_line writes an indented line followed by newline.
emit_line :: proc(e: ^Emitter, line: string) {
	_write_indent(e)
	strings.write_string(&e.buf, line)
	strings.write_byte(&e.buf, '\n')
}

// emit_raw writes a string without indentation or newline.
emit_raw :: proc(e: ^Emitter, s: string) {
	strings.write_string(&e.buf, s)
}

// emit_newline writes a blank line.
emit_newline :: proc(e: ^Emitter) {
	strings.write_byte(&e.buf, '\n')
}

// emit_indent writes current indent level (no newline).
emit_indent :: proc(e: ^Emitter) {
	_write_indent(e)
}

// indent increases the indentation level.
indent :: proc(e: ^Emitter) {
	e.indent_level += 1
}

// dedent decreases the indentation level.
dedent :: proc(e: ^Emitter) {
	if e.indent_level > 0 {
		e.indent_level -= 1
	}
}

// fresh_temp generates a fresh temporary variable name.
fresh_temp :: proc(e: ^Emitter) -> string {
	// Use a small stack buffer — temp names are short like "_tmp_42"
	b := strings.builder_make_len_cap(0, 16)
	strings.write_string(&b, "_tmp_")
	buf: [16]u8
	n := e.temp_count
	e.temp_count += 1
	if n == 0 {
		strings.write_byte(&b, '0')
	} else {
		i := len(buf)
		for n > 0 {
			i -= 1
			buf[i] = u8('0' + n % 10)
			n /= 10
		}
		strings.write_string(&b, string(buf[i:]))
	}
	return strings.to_string(b)
}

// escape_string_literal converts a raw string into an Odin string literal,
// escaping special characters.
escape_string_literal :: proc(s: string) -> string {
	b := strings.builder_make_len_cap(0, len(s) + 16)
	strings.write_byte(&b, '"')
	for i in 0 ..< len(s) {
		ch := s[i]
		switch ch {
		case '\\':
			strings.write_string(&b, "\\\\")
		case '"':
			strings.write_string(&b, "\\\"")
		case '\n':
			strings.write_string(&b, "\\n")
		case '\r':
			strings.write_string(&b, "\\r")
		case '\t':
			strings.write_string(&b, "\\t")
		case '\x00':
			strings.write_string(&b, "\\x00")
		case:
			strings.write_byte(&b, ch)
		}
	}
	strings.write_byte(&b, '"')
	return strings.to_string(b)
}
