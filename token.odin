package ohtml

// Token_Kind identifies the type of lexer tokens.
// The ordering matters: keywords are > Keyword sentinel.
Token_Kind :: enum {
	Error, // lexing error; val is text of error
	Bool, // boolean constant
	Char, // printable ASCII character; grab bag for comma etc.
	Char_Constant, // character constant 'x'
	Comment, // comment text
	Assign, // equals ('=') introducing an assignment
	Declare, // colon-equals (':=') introducing a declaration
	EOF,
	Field, // alphanumeric identifier starting with '.'
	Identifier, // alphanumeric identifier not starting with '.'
	Left_Delim, // left action delimiter {{
	Left_Paren, // '(' inside action
	Number, // simple number, including imaginary
	Pipe, // pipe symbol |
	Raw_String, // raw quoted string (includes quotes)
	Right_Delim, // right action delimiter }}
	Right_Paren, // ')' inside action
	Space, // run of spaces separating arguments
	String, // quoted string (includes quotes)
	Text, // plain text
	Variable, // variable starting with '$', such as '$' or '$1' or '$hello'
	// Keywords appear after all the rest.
	Keyword, // used only to delimit the keywords
	Block, // block keyword
	Break, // break keyword
	Continue, // continue keyword
	Dot, // the cursor, spelled '.'
	Define, // define keyword
	Else, // else keyword
	End, // end keyword
	If, // if keyword
	Nil, // the untyped nil constant
	Range, // range keyword
	Template, // template keyword
	With, // with keyword
}

// Token represents a token returned from the lexer.
Token :: struct {
	kind: Token_Kind,
	pos:  Pos, // byte offset in source
	val:  string, // token text (slice into source)
	line: int, // line number (1-based)
}

// keyword_lookup maps keyword strings to their Token_Kind.
keyword_lookup :: proc(word: string) -> (Token_Kind, bool) {
	switch word {
	case ".":
		return .Dot, true
	case "block":
		return .Block, true
	case "break":
		return .Break, true
	case "continue":
		return .Continue, true
	case "define":
		return .Define, true
	case "else":
		return .Else, true
	case "end":
		return .End, true
	case "if":
		return .If, true
	case "range":
		return .Range, true
	case "nil":
		return .Nil, true
	case "template":
		return .Template, true
	case "with":
		return .With, true
	}
	return .Error, false
}
