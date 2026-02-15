package ohtml_tests

import ohtml ".."
import "core:testing"

Token :: ohtml.Token
TK :: ohtml.Token_Kind

// Shorthand token constants (no proc calls at global scope)
t_eof :: Token {
	kind = .EOF,
}
t_left :: Token {
	kind = .Left_Delim,
	val  = "{{",
}
t_right :: Token {
	kind = .Right_Delim,
	val  = "}}",
}
t_pipe :: Token {
	kind = .Pipe,
	val  = "|",
}
t_space :: Token {
	kind = .Space,
	val  = " ",
}
t_dot :: Token {
	kind = .Dot,
	val  = ".",
}
t_lparen :: Token {
	kind = .Left_Paren,
	val  = "(",
}
t_rparen :: Token {
	kind = .Right_Paren,
	val  = ")",
}
t_assign :: Token {
	kind = .Assign,
	val  = "=",
}
t_declare :: Token {
	kind = .Declare,
	val  = ":=",
}

Lex_Test :: struct {
	name:   string,
	input:  string,
	tokens: []Token,
}

lex_tests := [?]Lex_Test {
	// --- Basic text ---
	{"empty", "", {t_eof}},
	{"spaces", " \t\n", {{kind = .Text, val = " \t\n"}, t_eof}},
	{"text", "now is the time", {{kind = .Text, val = "now is the time"}, t_eof}},
	{
		"text_and_action",
		"hello, {{.World}}",
		{{kind = .Text, val = "hello, "}, t_left, {kind = .Field, val = ".World"}, t_right, t_eof},
	},
	// --- Simple actions ---
	{"simple_action", "{{.X}}", {t_left, {kind = .Field, val = ".X"}, t_right, t_eof}},
	{"empty_action", `{{""}}`, {t_left, {kind = .String, val = `""`}, t_right, t_eof}},
	{
		"pipe",
		"{{.X | html}}",
		{
			t_left,
			{kind = .Field, val = ".X"},
			t_space,
			t_pipe,
			t_space,
			{kind = .Identifier, val = "html"},
			t_right,
			t_eof,
		},
	},
	{
		"multi_pipe",
		"{{.X | printf | html}}",
		{
			t_left,
			{kind = .Field, val = ".X"},
			t_space,
			t_pipe,
			t_space,
			{kind = .Identifier, val = "printf"},
			t_space,
			t_pipe,
			t_space,
			{kind = .Identifier, val = "html"},
			t_right,
			t_eof,
		},
	},
	// --- Variables ---
	{"variable", "{{$x}}", {t_left, {kind = .Variable, val = "$x"}, t_right, t_eof}},
	{"variable_bare", "{{$}}", {t_left, {kind = .Variable, val = "$"}, t_right, t_eof}},
	{"variable_hello", "{{$hello}}", {t_left, {kind = .Variable, val = "$hello"}, t_right, t_eof}},
	{
		"declare",
		"{{$x := .Y}}",
		{
			t_left,
			{kind = .Variable, val = "$x"},
			t_space,
			t_declare,
			t_space,
			{kind = .Field, val = ".Y"},
			t_right,
			t_eof,
		},
	},
	{
		"assign",
		"{{$x = .Y}}",
		{
			t_left,
			{kind = .Variable, val = "$x"},
			t_space,
			t_assign,
			t_space,
			{kind = .Field, val = ".Y"},
			t_right,
			t_eof,
		},
	},
	{
		"two_declarations",
		"{{$v, $w := 3}}",
		{
			t_left,
			{kind = .Variable, val = "$v"},
			{kind = .Char, val = ","},
			t_space,
			{kind = .Variable, val = "$w"},
			t_space,
			t_declare,
			t_space,
			{kind = .Number, val = "3"},
			t_right,
			t_eof,
		},
	},
	{
		"variable_invocation",
		"{{$x 23}}",
		{
			t_left,
			{kind = .Variable, val = "$x"},
			t_space,
			{kind = .Number, val = "23"},
			t_right,
			t_eof,
		},
	},
	// --- Strings ---
	{"string", `{{"hello"}}`, {t_left, {kind = .String, val = `"hello"`}, t_right, t_eof}},
	{"raw_string", "{{`hello`}}", {t_left, {kind = .Raw_String, val = "`hello`"}, t_right, t_eof}},
	// --- Numbers ---
	{"number", "{{42}}", {t_left, {kind = .Number, val = "42"}, t_right, t_eof}},
	{"negative_number", "{{-42}}", {t_left, {kind = .Number, val = "-42"}, t_right, t_eof}},
	{"float", "{{3.14}}", {t_left, {kind = .Number, val = "3.14"}, t_right, t_eof}},
	{"dot_float", "{{.123}}", {t_left, {kind = .Number, val = ".123"}, t_right, t_eof}},
	{"hex_number", "{{0x1F}}", {t_left, {kind = .Number, val = "0x1F"}, t_right, t_eof}},
	{"hex_upper", "{{0X1A}}", {t_left, {kind = .Number, val = "0X1A"}, t_right, t_eof}},
	{"octal_number", "{{0o17}}", {t_left, {kind = .Number, val = "0o17"}, t_right, t_eof}},
	{"binary_number", "{{0b101}}", {t_left, {kind = .Number, val = "0b101"}, t_right, t_eof}},
	{"scientific", "{{1e2}}", {t_left, {kind = .Number, val = "1e2"}, t_right, t_eof}},
	{"scientific_neg", "{{1e-2}}", {t_left, {kind = .Number, val = "1e-2"}, t_right, t_eof}},
	{"underscore_number", "{{1_000}}", {t_left, {kind = .Number, val = "1_000"}, t_right, t_eof}},
	// --- Booleans ---
	{"bool_true", "{{true}}", {t_left, {kind = .Bool, val = "true"}, t_right, t_eof}},
	{"bool_false", "{{false}}", {t_left, {kind = .Bool, val = "false"}, t_right, t_eof}},
	// --- Keywords ---
	{
		"keyword_if",
		"{{if .X}}yes{{end}}",
		{
			t_left,
			{kind = .If, val = "if"},
			t_space,
			{kind = .Field, val = ".X"},
			t_right,
			{kind = .Text, val = "yes"},
			t_left,
			{kind = .End, val = "end"},
			t_right,
			t_eof,
		},
	},
	{
		"keyword_range",
		"{{range .Items}}{{end}}",
		{
			t_left,
			{kind = .Range, val = "range"},
			t_space,
			{kind = .Field, val = ".Items"},
			t_right,
			t_left,
			{kind = .End, val = "end"},
			t_right,
			t_eof,
		},
	},
	{
		"keyword_else",
		"{{if .X}}a{{else}}b{{end}}",
		{
			t_left,
			{kind = .If, val = "if"},
			t_space,
			{kind = .Field, val = ".X"},
			t_right,
			{kind = .Text, val = "a"},
			t_left,
			{kind = .Else, val = "else"},
			t_right,
			{kind = .Text, val = "b"},
			t_left,
			{kind = .End, val = "end"},
			t_right,
			t_eof,
		},
	},
	{
		"keyword_with",
		"{{with .X}}{{.}}{{end}}",
		{
			t_left,
			{kind = .With, val = "with"},
			t_space,
			{kind = .Field, val = ".X"},
			t_right,
			t_left,
			t_dot,
			t_right,
			t_left,
			{kind = .End, val = "end"},
			t_right,
			t_eof,
		},
	},
	{
		"keyword_template",
		`{{template "sub" .}}`,
		{
			t_left,
			{kind = .Template, val = "template"},
			t_space,
			{kind = .String, val = `"sub"`},
			t_space,
			t_dot,
			t_right,
			t_eof,
		},
	},
	{
		"keyword_define",
		`{{define "sub"}}content{{end}}`,
		{
			t_left,
			{kind = .Define, val = "define"},
			t_space,
			{kind = .String, val = `"sub"`},
			t_right,
			{kind = .Text, val = "content"},
			t_left,
			{kind = .End, val = "end"},
			t_right,
			t_eof,
		},
	},
	{
		"keyword_block",
		`{{block "name" .}}default{{end}}`,
		{
			t_left,
			{kind = .Block, val = "block"},
			t_space,
			{kind = .String, val = `"name"`},
			t_space,
			t_dot,
			t_right,
			{kind = .Text, val = "default"},
			t_left,
			{kind = .End, val = "end"},
			t_right,
			t_eof,
		},
	},
	{"keyword_nil", "{{nil}}", {t_left, {kind = .Nil, val = "nil"}, t_right, t_eof}},
	// --- Fields ---
	{
		"dot_field_chain",
		"{{.A.B.C}}",
		{
			t_left,
			{kind = .Field, val = ".A"},
			{kind = .Field, val = ".B"},
			{kind = .Field, val = ".C"},
			t_right,
			t_eof,
		},
	},
	{
		"field_and_pipe",
		"{{.X | printf}}",
		{
			t_left,
			{kind = .Field, val = ".X"},
			t_space,
			t_pipe,
			t_space,
			{kind = .Identifier, val = "printf"},
			t_right,
			t_eof,
		},
	},
	// --- Parens ---
	{
		"parens",
		"{{(printf .X)}}",
		{
			t_left,
			t_lparen,
			{kind = .Identifier, val = "printf"},
			t_space,
			{kind = .Field, val = ".X"},
			t_rparen,
			t_right,
			t_eof,
		},
	},
	{
		"parens_in_pipe",
		"{{(.X) | html}}",
		{
			t_left,
			t_lparen,
			{kind = .Field, val = ".X"},
			t_rparen,
			t_space,
			t_pipe,
			t_space,
			{kind = .Identifier, val = "html"},
			t_right,
			t_eof,
		},
	},
	// --- Trimming ---
	{"trim_left", "  {{- .X}}", {t_left, {kind = .Field, val = ".X"}, t_right, t_eof}},
	{"trim_right", "{{.X -}}  ", {t_left, {kind = .Field, val = ".X"}, t_right, t_eof}},
	{"trim_both", "  {{- .X -}}  ", {t_left, {kind = .Field, val = ".X"}, t_right, t_eof}},
	{
		"trim_left_keeps_text",
		"hello  {{- .X}}",
		{{kind = .Text, val = "hello"}, t_left, {kind = .Field, val = ".X"}, t_right, t_eof},
	},
	// --- Comments ---
	{"comment", "{{/* a comment */}}", {t_eof}},
	{
		"text_and_comment",
		"hello {{/* comment */}}world",
		{{kind = .Text, val = "hello "}, {kind = .Text, val = "world"}, t_eof},
	},
	// --- Characters ---
	{"char_constant", "{{'a'}}", {t_left, {kind = .Char_Constant, val = "'a'"}, t_right, t_eof}},
	{
		"char_escape_n",
		"{{'\\n'}}",
		{t_left, {kind = .Char_Constant, val = "'\\n'"}, t_right, t_eof},
	},
	// --- Multiple actions ---
	{
		"multiple_actions",
		"{{.A}} and {{.B}}",
		{
			t_left,
			{kind = .Field, val = ".A"},
			t_right,
			{kind = .Text, val = " and "},
			t_left,
			{kind = .Field, val = ".B"},
			t_right,
			t_eof,
		},
	},
	// --- Punctuation ---
	{
		"comma",
		"{{$v, $w := 3}}",
		{
			t_left,
			{kind = .Variable, val = "$v"},
			{kind = .Char, val = ","},
			t_space,
			{kind = .Variable, val = "$w"},
			t_space,
			t_declare,
			t_space,
			{kind = .Number, val = "3"},
			t_right,
			t_eof,
		},
	},
	// --- Field of parenthesized expression ---
	{
		"field_of_paren",
		"{{(.X).Y}}",
		{
			t_left,
			t_lparen,
			{kind = .Field, val = ".X"},
			t_rparen,
			{kind = .Field, val = ".Y"},
			t_right,
			t_eof,
		},
	},
}

@(test)
test_lex :: proc(t: ^testing.T) {
	for &tt in lex_tests {
		l: ohtml.Lexer
		ohtml.lexer_init(&l, tt.name, tt.input)

		ok := true
		for i := 0; i < len(tt.tokens); i += 1 {
			tok := ohtml.next_token(&l)
			expected := tt.tokens[i]
			if tok.kind != expected.kind {
				testing.expectf(
					t,
					false,
					"[%s] token %d: kind = %v, want %v (val=%q)",
					tt.name,
					i,
					tok.kind,
					expected.kind,
					tok.val,
				)
				ok = false
				if tok.kind == .Error {
					delete(tok.val)
				}
				break
			}
			if len(expected.val) > 0 && tok.val != expected.val {
				testing.expectf(
					t,
					false,
					"[%s] token %d: val = %q, want %q",
					tt.name,
					i,
					tok.val,
					expected.val,
				)
				ok = false
				break
			}
		}
		if !ok {
			for {
				tok := ohtml.next_token(&l)
				if tok.kind == .EOF {
					break
				}
				if tok.kind == .Error {
					delete(tok.val)
					break
				}
			}
		}
	}
}

// ---------------------------------------------------------------------------
// Lexer error tests
// ---------------------------------------------------------------------------

@(test)
test_lex_errors :: proc(t: ^testing.T) {
	Error_Test :: struct {
		name:  string,
		input: string,
	}

	tests := [?]Error_Test {
		{"unclosed_action", "{{.X"},
		{"unclosed_quote", `{{"hello}`},
		{"unclosed_raw_quote", "{{`hello}}"},
		{"unclosed_char", "{{'a}}"},
		{"unclosed_comment", "{{/* comment"},
		{"bad_colon", "{{:}}"},
		{"unclosed_paren", "{{(.X}}"},
		{"unexpected_rparen", "{{)}}"},
		{"comment_ends_before_delim", "{{/* */ extra}}"},
		{"eof_in_action", "{{"},
		{"bad_number", "{{3k}}"},
		{"unrecognized_char", "{{\x01}}"},
	}

	for &tt in tests {
		l: ohtml.Lexer
		ohtml.lexer_init(&l, tt.name, tt.input)

		found_error := false
		for {
			tok := ohtml.next_token(&l)
			if tok.kind == .Error {
				found_error = true
				delete(tok.val) // free the aprintf'd error message
				break
			}
			if tok.kind == .EOF {
				break
			}
		}
		testing.expectf(t, found_error, "[%s] expected error token, got none", tt.name)
	}
}

// ---------------------------------------------------------------------------
// Custom delimiter tests
// ---------------------------------------------------------------------------

@(test)
test_lex_custom_delims :: proc(t: ^testing.T) {
	// Test with $$ and @@ as delimiters
	{
		l: ohtml.Lexer
		ohtml.lexer_init(&l, "custom_delim", "hello $$.X@@world", "$$", "@@")

		tok := ohtml.next_token(&l)
		testing.expectf(t, tok.kind == .Text, "custom: expected Text, got %v", tok.kind)
		testing.expectf(t, tok.val == "hello ", "custom: expected 'hello ', got %q", tok.val)

		tok = ohtml.next_token(&l)
		testing.expectf(
			t,
			tok.kind == .Left_Delim,
			"custom: expected Left_Delim, got %v",
			tok.kind,
		)

		tok = ohtml.next_token(&l)
		testing.expectf(t, tok.kind == .Field, "custom: expected Field, got %v", tok.kind)
		testing.expectf(t, tok.val == ".X", "custom: expected '.X', got %q", tok.val)

		tok = ohtml.next_token(&l)
		testing.expectf(
			t,
			tok.kind == .Right_Delim,
			"custom: expected Right_Delim, got %v",
			tok.kind,
		)

		tok = ohtml.next_token(&l)
		testing.expectf(t, tok.kind == .Text, "custom: expected Text, got %v", tok.kind)
		testing.expectf(t, tok.val == "world", "custom: expected 'world', got %q", tok.val)
	}

	// Test with longer delimiters
	{
		l: ohtml.Lexer
		ohtml.lexer_init(&l, "long_delim", "<%%.X%%>", "<%%", "%%>")

		tok := ohtml.next_token(&l)
		testing.expectf(t, tok.kind == .Left_Delim, "long: expected Left_Delim, got %v", tok.kind)

		tok = ohtml.next_token(&l)
		testing.expectf(t, tok.kind == .Field, "long: expected Field, got %v", tok.kind)

		tok = ohtml.next_token(&l)
		testing.expectf(
			t,
			tok.kind == .Right_Delim,
			"long: expected Right_Delim, got %v",
			tok.kind,
		)
	}
}

// ---------------------------------------------------------------------------
// Position/line tracking tests
// ---------------------------------------------------------------------------

@(test)
test_lex_positions :: proc(t: ^testing.T) {
	// Test that line numbers are tracked correctly
	input := "line1\nline2\n{{.X}}"
	l: ohtml.Lexer
	ohtml.lexer_init(&l, "pos_test", input)

	tok := ohtml.next_token(&l) // text "line1\nline2\n"
	testing.expectf(t, tok.kind == .Text, "pos: expected Text, got %v", tok.kind)

	tok = ohtml.next_token(&l) // {{
	testing.expectf(t, tok.kind == .Left_Delim, "pos: expected Left_Delim, got %v", tok.kind)
	testing.expectf(t, tok.line == 3, "pos: {{ should be on line 3, got %d", tok.line)

	tok = ohtml.next_token(&l) // .X
	testing.expectf(t, tok.kind == .Field, "pos: expected Field, got %v", tok.kind)
	testing.expectf(t, tok.line == 3, "pos: .X should be on line 3, got %d", tok.line)
}

// ---------------------------------------------------------------------------
// Break/continue keyword context tests
// ---------------------------------------------------------------------------

@(test)
test_lex_break_continue :: proc(t: ^testing.T) {
	// Outside range, break/continue should be identifiers
	{
		l: ohtml.Lexer
		ohtml.lexer_init(&l, "break_no_range", "{{break}}")

		tok := ohtml.next_token(&l) // {{
		tok = ohtml.next_token(&l) // break (as identifier)
		testing.expectf(
			t,
			tok.kind == .Identifier,
			"break outside range should be Identifier, got %v",
			tok.kind,
		)
	}

	// With break_ok, break should be keyword
	{
		l: ohtml.Lexer
		ohtml.lexer_init(&l, "break_in_range", "{{break}}")
		l.options.break_ok = true

		tok := ohtml.next_token(&l) // {{
		tok = ohtml.next_token(&l) // break (as keyword)
		testing.expectf(
			t,
			tok.kind == .Break,
			"break in range should be Break keyword, got %v",
			tok.kind,
		)
	}

	// With continue_ok, continue should be keyword
	{
		l: ohtml.Lexer
		ohtml.lexer_init(&l, "continue_in_range", "{{continue}}")
		l.options.continue_ok = true

		tok := ohtml.next_token(&l) // {{
		tok = ohtml.next_token(&l) // continue (as keyword)
		testing.expectf(
			t,
			tok.kind == .Continue,
			"continue in range should be Continue keyword, got %v",
			tok.kind,
		)
	}
}

// ---------------------------------------------------------------------------
// Comment with emit_comment option
// ---------------------------------------------------------------------------

@(test)
test_lex_emit_comment :: proc(t: ^testing.T) {
	l: ohtml.Lexer
	ohtml.lexer_init(&l, "emit_cmt", "{{/* hello */}}")
	l.options.emit_comment = true

	tok := ohtml.next_token(&l)
	testing.expectf(t, tok.kind == .Comment, "emit_comment: expected Comment, got %v", tok.kind)
}
