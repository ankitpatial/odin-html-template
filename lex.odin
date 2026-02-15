package ohtml

import "core:fmt"
import "core:strings"
import "core:unicode"
import "core:unicode/utf8"

Pos :: int

EOF_RUNE :: rune(-1)

SPACE_CHARS :: " \t\r\n"
TRIM_MARKER :: '-'
TRIM_MARKER_LEN :: 1 + 1 // marker plus space before or after

LEFT_COMMENT :: "/*"
RIGHT_COMMENT :: "*/"

DEFAULT_LEFT_DELIM :: "{{"
DEFAULT_RIGHT_DELIM :: "}}"

Lex_Options :: struct {
	emit_comment: bool, // emit Comment tokens
	break_ok:     bool, // break keyword allowed
	continue_ok:  bool, // continue keyword allowed
}

// Lexer tokenizes template text into a stream of tokens.
Lexer :: struct {
	name:          string, // template name for errors
	input:         string, // source text
	left_delim:    string, // start of action, default "{{"
	right_delim:   string, // end of action, default "}}"
	pos:           Pos, // current byte position in input
	start:         Pos, // start of current token
	at_eof:        bool,
	paren_depth:   int,
	line:          int, // current line number (1-based)
	start_line:    int, // line at start of current token
	item:          Token, // last emitted token
	inside_action: bool, // inside {{ }}
	options:       Lex_Options,
	last_rune_w:   int, // byte width of last rune read by next_rune (for fast backup)
	last_rune_nl:  bool, // whether last rune was '\n' (for line tracking in backup)
}

// lexer_init initializes a lexer with the given template name, input, and delimiters.
lexer_init :: proc(l: ^Lexer, name, input: string, left_delim := "", right_delim := "") {
	l.name = name
	l.input = input
	l.left_delim = left_delim if len(left_delim) > 0 else DEFAULT_LEFT_DELIM
	l.right_delim = right_delim if len(right_delim) > 0 else DEFAULT_RIGHT_DELIM
	l.line = 1
	l.start_line = 1
	l.pos = 0
	l.start = 0
	l.at_eof = false
	l.paren_depth = 0
	l.inside_action = false
}

// State_Fn represents a lexer state function.
// Returns the next state, or nil to indicate a token has been produced.
State_Fn :: #type proc(l: ^Lexer) -> State_Fn

// next_token drives the state machine until a token is produced and returns it.
next_token :: proc(l: ^Lexer) -> Token {
	l.item = Token {
		kind = .EOF,
		pos  = l.pos,
		val  = "EOF",
		line = l.start_line,
	}
	state: State_Fn = lex_text if !l.inside_action else lex_inside_action
	for state != nil {
		state = state(l)
	}
	return l.item
}

// --- Character-level navigation ---

next_rune :: proc(l: ^Lexer) -> rune {
	if int(l.pos) >= len(l.input) {
		l.at_eof = true
		l.last_rune_w = 0
		return EOF_RUNE
	}
	r, w := utf8.decode_rune_in_string(l.input[l.pos:])
	l.pos += Pos(w)
	l.last_rune_w = w
	l.last_rune_nl = r == '\n'
	if l.last_rune_nl {
		l.line += 1
	}
	return r
}

peek_rune :: proc(l: ^Lexer) -> rune {
	r := next_rune(l)
	backup(l)
	return r
}

backup :: proc(l: ^Lexer) {
	if !l.at_eof && l.last_rune_w > 0 {
		l.pos -= Pos(l.last_rune_w)
		if l.last_rune_nl {
			l.line -= 1
		}
	}
	l.at_eof = false
}

// --- Token emission helpers ---

this_item :: proc(l: ^Lexer, kind: Token_Kind) -> Token {
	t := Token {
		kind = kind,
		pos  = l.start,
		val  = l.input[l.start:l.pos],
		line = l.start_line,
	}
	l.start = l.pos
	l.start_line = l.line
	return t
}

emit :: proc(l: ^Lexer, kind: Token_Kind) -> State_Fn {
	return emit_item(l, this_item(l, kind))
}

emit_item :: proc(l: ^Lexer, item: Token) -> State_Fn {
	l.item = item
	return nil
}

ignore :: proc(l: ^Lexer) {
	l.line += strings.count(l.input[l.start:l.pos], "\n")
	l.start = l.pos
	l.start_line = l.line
}

accept :: proc(l: ^Lexer, valid: string) -> bool {
	if strings.contains_rune(valid, next_rune(l)) {
		return true
	}
	backup(l)
	return false
}

accept_run :: proc(l: ^Lexer, valid: string) {
	for strings.contains_rune(valid, next_rune(l)) {}
	backup(l)
}

errorf :: proc(l: ^Lexer, format: string, args: ..any) -> State_Fn {
	l.item = Token {
		kind = .Error,
		pos  = l.start,
		val  = fmt.aprintf(format, ..args),
		line = l.start_line,
	}
	l.start = 0
	l.pos = 0
	l.input = l.input[:0]
	return nil
}

// --- Helper predicates ---

is_space :: proc(r: rune) -> bool {
	return r == ' ' || r == '\t' || r == '\r' || r == '\n'
}

is_alpha_numeric :: proc(r: rune) -> bool {
	return r == '_' || unicode.is_letter(r) || unicode.is_digit(r)
}

at_terminator :: proc(l: ^Lexer) -> bool {
	r := peek_rune(l)
	if is_space(r) {
		return true
	}
	switch r {
	case EOF_RUNE, '.', ',', '|', ':', ')', '(':
		return true
	}
	return strings.has_prefix(l.input[l.pos:], l.right_delim)
}

at_right_delim :: proc(l: ^Lexer) -> (delim: bool, trim_spaces: bool) {
	if has_right_trim_marker(l.input[l.pos:]) &&
	   strings.has_prefix(l.input[l.pos + TRIM_MARKER_LEN:], l.right_delim) {
		return true, true
	}
	if strings.has_prefix(l.input[l.pos:], l.right_delim) {
		return true, false
	}
	return false, false
}

has_left_trim_marker :: proc(s: string) -> bool {
	return len(s) >= 2 && s[0] == u8(TRIM_MARKER) && is_space(rune(s[1]))
}

has_right_trim_marker :: proc(s: string) -> bool {
	return len(s) >= 2 && is_space(rune(s[0])) && s[1] == u8(TRIM_MARKER)
}

right_trim_length :: proc(s: string) -> Pos {
	return Pos(len(s) - len(strings.trim_right(s, SPACE_CHARS)))
}

left_trim_length :: proc(s: string) -> Pos {
	return Pos(len(s) - len(strings.trim_left(s, SPACE_CHARS)))
}

// --- State functions ---

// lex_text scans plain text until the left delimiter or end of input.
lex_text :: proc(l: ^Lexer) -> State_Fn {
	if x := strings.index(l.input[l.pos:], l.left_delim); x >= 0 {
		if x > 0 {
			l.pos += Pos(x)
			trim_length := Pos(0)
			delim_end := l.pos + Pos(len(l.left_delim))
			if has_left_trim_marker(l.input[delim_end:]) {
				trim_length = right_trim_length(l.input[l.start:l.pos])
			}
			l.pos -= trim_length
			l.line += strings.count(l.input[l.start:l.pos], "\n")
			i := this_item(l, .Text)
			l.pos += trim_length
			ignore(l)
			if len(i.val) > 0 {
				return emit_item(l, i)
			}
		}
		return lex_left_delim
	}
	l.pos = Pos(len(l.input))
	if l.pos > l.start {
		l.line += strings.count(l.input[l.start:l.pos], "\n")
		return emit(l, .Text)
	}
	return emit(l, .EOF)
}

// lex_left_delim scans the left delimiter {{ and detects comments.
lex_left_delim :: proc(l: ^Lexer) -> State_Fn {
	l.pos += Pos(len(l.left_delim))
	trim_space := has_left_trim_marker(l.input[l.pos:])
	after_marker := Pos(0)
	if trim_space {
		after_marker = TRIM_MARKER_LEN
	}
	if strings.has_prefix(l.input[l.pos + after_marker:], LEFT_COMMENT) {
		l.pos += after_marker
		ignore(l)
		return lex_comment
	}
	i := this_item(l, .Left_Delim)
	l.inside_action = true
	l.pos += after_marker
	ignore(l)
	l.paren_depth = 0
	return emit_item(l, i)
}

// lex_comment scans a comment /* ... */ inside delimiters.
lex_comment :: proc(l: ^Lexer) -> State_Fn {
	l.pos += Pos(len(LEFT_COMMENT))
	x := strings.index(l.input[l.pos:], RIGHT_COMMENT)
	if x < 0 {
		return errorf(l, "unclosed comment")
	}
	l.pos += Pos(x + len(RIGHT_COMMENT))
	delim, trim_space := at_right_delim(l)
	if !delim {
		return errorf(l, "comment ends before closing delimiter")
	}
	l.line += strings.count(l.input[l.start:l.pos], "\n")
	i := this_item(l, .Comment)
	if trim_space {
		l.pos += TRIM_MARKER_LEN
	}
	l.pos += Pos(len(l.right_delim))
	if trim_space {
		l.pos += left_trim_length(l.input[l.pos:])
	}
	ignore(l)
	if l.options.emit_comment {
		return emit_item(l, i)
	}
	return lex_text
}

// lex_right_delim scans the right delimiter }}.
lex_right_delim :: proc(l: ^Lexer) -> State_Fn {
	_, trim_space := at_right_delim(l)
	if trim_space {
		l.pos += TRIM_MARKER_LEN
		ignore(l)
	}
	l.pos += Pos(len(l.right_delim))
	i := this_item(l, .Right_Delim)
	if trim_space {
		l.pos += left_trim_length(l.input[l.pos:])
		ignore(l)
	}
	l.inside_action = false
	return emit_item(l, i)
}

// lex_inside_action is the main dispatch inside {{ ... }}.
lex_inside_action :: proc(l: ^Lexer) -> State_Fn {
	delim, _ := at_right_delim(l)
	if delim {
		if l.paren_depth == 0 {
			return lex_right_delim
		}
		return errorf(l, "unclosed left paren")
	}
	r := next_rune(l)
	switch {
	case r == EOF_RUNE:
		return errorf(l, "unclosed action")
	case is_space(r):
		backup(l)
		return lex_space
	case r == '=':
		return emit(l, .Assign)
	case r == ':':
		if next_rune(l) != '=' {
			return errorf(l, "expected :=")
		}
		return emit(l, .Declare)
	case r == '|':
		return emit(l, .Pipe)
	case r == '"':
		return lex_quote
	case r == '`':
		return lex_raw_quote
	case r == '$':
		return lex_variable
	case r == '\'':
		return lex_char
	case r == '.':
		// Special case: if the next char is a digit, it starts a number (.123).
		if l.pos < Pos(len(l.input)) {
			nr := l.input[l.pos]
			if nr < '0' || '9' < nr {
				return lex_field
			}
		}
		// Fall through to number scanning for .123 etc.
		backup(l)
		return lex_number
	case r == '+' || r == '-' || ('0' <= r && r <= '9'):
		backup(l)
		return lex_number
	case is_alpha_numeric(r):
		backup(l)
		return lex_identifier
	case r == '(':
		l.paren_depth += 1
		return emit(l, .Left_Paren)
	case r == ')':
		l.paren_depth -= 1
		if l.paren_depth < 0 {
			return errorf(l, "unexpected right paren")
		}
		return emit(l, .Right_Paren)
	case r <= rune(unicode.MAX_ASCII) && unicode.is_print(r):
		return emit(l, .Char)
	case:
		return errorf(l, "unrecognized character in action: %r", r)
	}
	return nil // unreachable
}

// lex_space scans a run of whitespace inside an action.
lex_space :: proc(l: ^Lexer) -> State_Fn {
	num_spaces := 0
	for {
		r := peek_rune(l)
		if !is_space(r) {
			break
		}
		next_rune(l)
		num_spaces += 1
	}
	// If the last space is part of a right trim marker, back up one space.
	if l.pos > 0 &&
	   has_right_trim_marker(l.input[l.pos - 1:]) &&
	   strings.has_prefix(l.input[l.pos - 1 + TRIM_MARKER_LEN:], l.right_delim) {
		backup(l)
		if num_spaces == 1 {
			return lex_right_delim
		}
	}
	return emit(l, .Space)
}

// lex_identifier scans an alphanumeric identifier or keyword.
lex_identifier :: proc(l: ^Lexer) -> State_Fn {
	for {
		r := next_rune(l)
		if is_alpha_numeric(r) {
			// absorb
			continue
		}
		backup(l)
		word := l.input[l.start:l.pos]
		if !at_terminator(l) {
			return errorf(l, "bad character %r", r)
		}
		kw, is_kw := keyword_lookup(word)
		switch {
		case is_kw && kw > .Keyword:
			// break and continue are context-sensitive
			if kw == .Break && !l.options.break_ok {
				return emit(l, .Identifier)
			}
			if kw == .Continue && !l.options.continue_ok {
				return emit(l, .Identifier)
			}
			return emit(l, kw)
		case word[0] == '.':
			return emit(l, .Field)
		case word == "true" || word == "false":
			return emit(l, .Bool)
		case:
			return emit(l, .Identifier)
		}
	}
}

// lex_field scans a field access starting with '.'.
lex_field :: proc(l: ^Lexer) -> State_Fn {
	return lex_field_or_variable(l, .Field)
}

// lex_variable scans a variable starting with '$'.
lex_variable :: proc(l: ^Lexer) -> State_Fn {
	if at_terminator(l) {
		return emit(l, .Variable)
	}
	return lex_field_or_variable(l, .Variable)
}

// lex_field_or_variable scans a field or variable (shared logic).
lex_field_or_variable :: proc(l: ^Lexer, typ: Token_Kind) -> State_Fn {
	if at_terminator(l) {
		if typ == .Variable {
			return emit(l, .Variable)
		}
		return emit(l, .Dot)
	}
	r: rune
	for {
		r = next_rune(l)
		if !is_alpha_numeric(r) {
			backup(l)
			break
		}
	}
	if !at_terminator(l) {
		return errorf(l, "bad character %r", r)
	}
	return emit(l, typ)
}

// lex_char scans a character constant 'x'.
lex_char :: proc(l: ^Lexer) -> State_Fn {
	for {
		r := next_rune(l)
		switch r {
		case '\\':
			nr := next_rune(l)
			if nr != EOF_RUNE && nr != '\n' {
				continue
			}
			return errorf(l, "unterminated character constant")
		case EOF_RUNE, '\n':
			return errorf(l, "unterminated character constant")
		case '\'':
			return emit(l, .Char_Constant)
		}
	}
}

// lex_number scans a numeric literal.
lex_number :: proc(l: ^Lexer) -> State_Fn {
	if !scan_number(l) {
		return errorf(l, "bad number syntax: %q", l.input[l.start:l.pos])
	}
	// Check for imaginary/complex (not needed for HTML templates but matching Go)
	sign := peek_rune(l)
	if sign == '+' || sign == '-' {
		if !scan_number(l) || l.input[l.pos - 1] != 'i' {
			return errorf(l, "bad number syntax: %q", l.input[l.start:l.pos])
		}
		return emit(l, .Number) // complex
	}
	return emit(l, .Number)
}

// scan_number scans a number: decimal, hex, octal, binary, float.
scan_number :: proc(l: ^Lexer) -> bool {
	accept(l, "+-")
	digits := "0123456789_"
	if accept(l, "0") {
		if accept(l, "xX") {
			digits = "0123456789abcdefABCDEF_"
		} else if accept(l, "oO") {
			digits = "01234567_"
		} else if accept(l, "bB") {
			digits = "01_"
		}
	}
	accept_run(l, digits)
	if accept(l, ".") {
		accept_run(l, digits)
	}
	if len(digits) == 10 + 1 && accept(l, "eE") {
		accept(l, "+-")
		accept_run(l, "0123456789_")
	}
	if len(digits) == 16 + 6 + 1 && accept(l, "pP") {
		accept(l, "+-")
		accept_run(l, "0123456789_")
	}
	// Imaginary suffix
	accept(l, "i")
	// Verify next char is a terminator
	if is_alpha_numeric(peek_rune(l)) {
		next_rune(l)
		return false
	}
	return true
}

// lex_quote scans a double-quoted string.
lex_quote :: proc(l: ^Lexer) -> State_Fn {
	for {
		r := next_rune(l)
		switch r {
		case '\\':
			nr := next_rune(l)
			if nr != EOF_RUNE && nr != '\n' {
				continue
			}
			return errorf(l, "unterminated quoted string")
		case EOF_RUNE, '\n':
			return errorf(l, "unterminated quoted string")
		case '"':
			return emit(l, .String)
		}
	}
}

// lex_raw_quote scans a backtick-quoted raw string.
lex_raw_quote :: proc(l: ^Lexer) -> State_Fn {
	for {
		r := next_rune(l)
		switch r {
		case EOF_RUNE:
			return errorf(l, "unterminated raw quoted string")
		case '`':
			return emit(l, .Raw_String)
		}
	}
}
