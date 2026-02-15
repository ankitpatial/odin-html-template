package ohtml

import "core:unicode/utf8"

// ---------------------------------------------------------------------------
// Context transition — advance escape context through raw HTML bytes
// ---------------------------------------------------------------------------

// Transition_Fn processes bytes in a given context state.
// Returns the new context and the number of bytes consumed.
Transition_Fn :: #type proc(c: Escape_Context, s: []u8) -> (Escape_Context, int)

// transition processes the raw text through the context state machine.
// Returns the context after processing all the text.
transition :: proc(c: Escape_Context, text: []u8) -> Escape_Context {
	ctx := c
	i := 0
	for i < len(text) {
		fn := _transition_for(ctx.state)
		new_ctx, consumed := fn(ctx, text[i:])
		if consumed <= 0 {
			consumed = 1 // always advance
		}
		ctx = new_ctx
		i += consumed
	}
	return ctx
}

// _transition_for returns the transition function for a given state.
@(private = "package")
_transition_for :: proc(state: Context_State) -> Transition_Fn {
	#partial switch state {
	case .Text:
		return _t_text
	case .Tag:
		return _t_tag
	case .Attr_Name:
		return _t_attr_name
	case .After_Name:
		return _t_after_name
	case .Before_Value:
		return _t_before_value
	case .HTML_Cmt:
		return _t_html_cmt
	case .RCDATA:
		return _t_rcdata
	case .Attr:
		return _t_attr
	case .URL:
		return _t_url
	case .Srcset:
		return _t_srcset
	case .JS:
		return _t_js
	case .JS_Dq_Str:
		return _t_js_dq_str
	case .JS_Sq_Str:
		return _t_js_sq_str
	case .JS_Tmpl_Lit:
		return _t_js_tmpl_lit
	case .JS_Regexp:
		return _t_js_regexp
	case .JS_Block_Cmt:
		return _t_js_block_cmt
	case .JS_Line_Cmt, .JS_HTML_Open_Cmt, .JS_HTML_Close_Cmt:
		return _t_js_line_cmt
	case .CSS:
		return _t_css
	case .CSS_Dq_Str:
		return _t_css_dq_str
	case .CSS_Sq_Str:
		return _t_css_sq_str
	case .CSS_Dq_URL:
		return _t_css_dq_url
	case .CSS_Sq_URL:
		return _t_css_sq_url
	case .CSS_URL:
		return _t_css_url
	case .CSS_Block_Cmt:
		return _t_css_block_cmt
	case .CSS_Line_Cmt:
		return _t_css_line_cmt
	}
	return _t_error
}

// ---------------------------------------------------------------------------
// State handlers
// ---------------------------------------------------------------------------

_t_text :: proc(c: Escape_Context, s: []u8) -> (Escape_Context, int) {
	for i in 0 ..< len(s) {
		if s[i] == '<' {
			// Check for comment.
			if i + 4 <= len(s) && s[i + 1] == '!' && s[i + 2] == '-' && s[i + 3] == '-' {
				return Escape_Context{state = .HTML_Cmt}, i + 4
			}
			// Check for tag.
			if i + 1 < len(s) {
				end, elem := _eat_tag_name(s, i + 1)
				if end > i + 1 {
					ctx := Escape_Context {
						state   = .Tag,
						element = elem,
					}
					// Special elements get special states.
					if elem == .Script {
						ctx.state = .Tag
						ctx.element = .Script
					} else if elem == .Style {
						ctx.state = .Tag
						ctx.element = .Style
					}
					return ctx, end
				}
			}
		}
	}
	return c, len(s)
}

_t_tag :: proc(c: Escape_Context, s: []u8) -> (Escape_Context, int) {
	i := _eat_white_space(s, 0)
	if i >= len(s) {
		return c, len(s)
	}

	if s[i] == '>' {
		ctx := c
		// After closing tag, enter element-specific state.
		switch c.element {
		case .Script:
			ctx.state = .JS
			ctx.js_ctx = .Regexp
		case .Style:
			ctx.state = .CSS
		case .Textarea, .Title:
			ctx.state = .RCDATA
		case .None:
			ctx.state = .Text
		}
		ctx.delim = .None
		ctx.attr = .None
		return ctx, i + 1
	}

	if s[i] == '/' && i + 1 < len(s) && s[i + 1] == '>' {
		return Escape_Context{state = .Text}, i + 2
	}

	// Start reading attribute name.
	end := _eat_attr_name(s, i)
	if end > i {
		ctx := c
		ctx.state = .After_Name
		attr_name := string(s[i:end])
		ctx.attr = _attr_type(attr_name, c.element)
		return ctx, end
	}

	return c, i + 1
}

_t_attr_name :: proc(c: Escape_Context, s: []u8) -> (Escape_Context, int) {
	end := _eat_attr_name(s, 0)
	if end > 0 {
		ctx := c
		ctx.state = .After_Name
		return ctx, end
	}
	return c, 1
}

_t_after_name :: proc(c: Escape_Context, s: []u8) -> (Escape_Context, int) {
	i := _eat_white_space(s, 0)
	if i >= len(s) {
		return c, len(s)
	}
	if s[i] == '=' {
		ctx := c
		ctx.state = .Before_Value
		return ctx, i + 1
	}
	// No '=' — it's a boolean attribute. Go back to tag.
	ctx := c
	ctx.state = .Tag
	return ctx, i
}

_t_before_value :: proc(c: Escape_Context, s: []u8) -> (Escape_Context, int) {
	i := _eat_white_space(s, 0)
	if i >= len(s) {
		return c, len(s)
	}
	ctx := c
	switch s[i] {
	case '"':
		ctx.delim = .Double_Quote
	case '\'':
		ctx.delim = .Single_Quote
	case:
		ctx.delim = .Space_Or_Tag_End
		// Don't consume the character — let the attr state handle it.
		ctx.state = _attr_start_state(c.attr, c.element)
		return ctx, i
	}
	ctx.state = _attr_start_state(c.attr, c.element)
	return ctx, i + 1
}

_t_html_cmt :: proc(c: Escape_Context, s: []u8) -> (Escape_Context, int) {
	if len(s) < 3 {
		return c, len(s)
	}
	for i in 0 ..< len(s) - 2 {
		if s[i] == '-' && s[i + 1] == '-' && s[i + 2] == '>' {
			return Escape_Context{state = .Text}, i + 3
		}
	}
	return c, len(s)
}

_t_rcdata :: proc(c: Escape_Context, s: []u8) -> (Escape_Context, int) {
	// Look for end tag matching the element.
	for i in 0 ..< len(s) {
		if s[i] == '<' && i + 1 < len(s) && s[i + 1] == '/' {
			end, _ := _eat_tag_name(s, i + 2)
			// Found a closing tag.
			if end > i + 2 {
				return Escape_Context{state = .Text}, end
			}
		}
	}
	return c, len(s)
}

_t_attr :: proc(c: Escape_Context, s: []u8) -> (Escape_Context, int) {
	for i in 0 ..< len(s) {
		if _is_delim_end(s[i], c.delim) {
			ctx := c
			ctx.state = .Tag
			ctx.delim = .None
			ctx.attr = .None
			consumed := i
			if c.delim != .Space_Or_Tag_End {
				consumed = i + 1 // consume the closing quote
			}
			return ctx, consumed
		}
	}
	return c, len(s)
}

_t_url :: proc(c: Escape_Context, s: []u8) -> (Escape_Context, int) {
	for i in 0 ..< len(s) {
		if _is_delim_end(s[i], c.delim) {
			ctx := c
			ctx.state = .Tag
			ctx.delim = .None
			ctx.attr = .None
			ctx.url_part = .None
			consumed := i
			if c.delim != .Space_Or_Tag_End {
				consumed = i + 1
			}
			return ctx, consumed
		}
		if c.url_part == .None || c.url_part == .Pre_Query {
			if s[i] == '?' || s[i] == '#' {
				ctx := c
				ctx.url_part = .Query_Or_Frag
				return ctx, i + 1
			}
		}
	}
	ctx := c
	if ctx.url_part == .None {
		ctx.url_part = .Pre_Query
	}
	return ctx, len(s)
}

_t_srcset :: proc(c: Escape_Context, s: []u8) -> (Escape_Context, int) {
	// Similar to URL — look for delimiter end.
	for i in 0 ..< len(s) {
		if _is_delim_end(s[i], c.delim) {
			ctx := c
			ctx.state = .Tag
			ctx.delim = .None
			ctx.attr = .None
			consumed := i
			if c.delim != .Space_Or_Tag_End {
				consumed = i + 1
			}
			return ctx, consumed
		}
	}
	return c, len(s)
}

// ---------------------------------------------------------------------------
// JavaScript state handlers
// ---------------------------------------------------------------------------

_t_js :: proc(c: Escape_Context, s: []u8) -> (Escape_Context, int) {
	for i in 0 ..< len(s) {
		switch s[i] {
		case '"':
			return Escape_Context{state = .JS_Dq_Str, element = c.element}, i + 1
		case '\'':
			return Escape_Context{state = .JS_Sq_Str, element = c.element}, i + 1
		case '`':
			return Escape_Context{state = .JS_Tmpl_Lit, element = c.element}, i + 1
		case '/':
			if i + 1 < len(s) {
				if s[i + 1] == '/' {
					return Escape_Context{state = .JS_Line_Cmt, element = c.element}, i + 2
				}
				if s[i + 1] == '*' {
					return Escape_Context{state = .JS_Block_Cmt, element = c.element}, i + 2
				}
			}
			if c.js_ctx == .Regexp {
				return Escape_Context{state = .JS_Regexp, element = c.element}, i + 1
			}
		case '<':
			if i + 1 < len(s) && s[i + 1] == '/' {
				// Potential </script> end tag.
				end, _ := _eat_tag_name(s, i + 2)
				if end > i + 2 {
					return Escape_Context{state = .Text}, end
				}
			}
		}
	}
	ctx := c
	ctx.js_ctx = .Div_Op
	return ctx, len(s)
}

_t_js_dq_str :: proc(c: Escape_Context, s: []u8) -> (Escape_Context, int) {
	return _t_js_str(c, s, '"')
}

_t_js_sq_str :: proc(c: Escape_Context, s: []u8) -> (Escape_Context, int) {
	return _t_js_str(c, s, '\'')
}

_t_js_str :: proc(c: Escape_Context, s: []u8, quote: u8) -> (Escape_Context, int) {
	for i in 0 ..< len(s) {
		if s[i] == '\\' {
			return c, i + 2 // skip escape
		}
		if s[i] == quote {
			return Escape_Context{state = .JS, js_ctx = .Div_Op, element = c.element}, i + 1
		}
	}
	return c, len(s)
}

_t_js_tmpl_lit :: proc(c: Escape_Context, s: []u8) -> (Escape_Context, int) {
	for i in 0 ..< len(s) {
		if s[i] == '\\' {
			return c, i + 2
		}
		if s[i] == '`' {
			return Escape_Context{state = .JS, js_ctx = .Div_Op, element = c.element}, i + 1
		}
	}
	return c, len(s)
}

_t_js_regexp :: proc(c: Escape_Context, s: []u8) -> (Escape_Context, int) {
	for i in 0 ..< len(s) {
		if s[i] == '\\' {
			return c, i + 2
		}
		if s[i] == '/' {
			return Escape_Context{state = .JS, js_ctx = .Div_Op, element = c.element}, i + 1
		}
	}
	return c, len(s)
}

_t_js_block_cmt :: proc(c: Escape_Context, s: []u8) -> (Escape_Context, int) {
	if len(s) < 2 {
		return c, len(s)
	}
	for i in 0 ..< len(s) - 1 {
		if s[i] == '*' && s[i + 1] == '/' {
			return Escape_Context{state = .JS, element = c.element}, i + 2
		}
	}
	return c, len(s)
}

_t_js_line_cmt :: proc(c: Escape_Context, s: []u8) -> (Escape_Context, int) {
	for i in 0 ..< len(s) {
		if s[i] == '\n' {
			return Escape_Context{state = .JS, element = c.element}, i + 1
		}
	}
	return c, len(s)
}

// ---------------------------------------------------------------------------
// CSS state handlers
// ---------------------------------------------------------------------------

_t_css :: proc(c: Escape_Context, s: []u8) -> (Escape_Context, int) {
	for i in 0 ..< len(s) {
		switch s[i] {
		case '"':
			return Escape_Context{state = .CSS_Dq_Str, element = c.element}, i + 1
		case '\'':
			return Escape_Context{state = .CSS_Sq_Str, element = c.element}, i + 1
		case '/':
			if i + 1 < len(s) && s[i + 1] == '*' {
				return Escape_Context{state = .CSS_Block_Cmt, element = c.element}, i + 2
			}
		case '<':
			if i + 1 < len(s) && s[i + 1] == '/' {
				end, _ := _eat_tag_name(s, i + 2)
				if end > i + 2 {
					return Escape_Context{state = .Text}, end
				}
			}
		}
	}
	return c, len(s)
}

_t_css_dq_str :: proc(c: Escape_Context, s: []u8) -> (Escape_Context, int) {
	return _t_css_str(c, s, '"', .CSS)
}

_t_css_sq_str :: proc(c: Escape_Context, s: []u8) -> (Escape_Context, int) {
	return _t_css_str(c, s, '\'', .CSS)
}

_t_css_dq_url :: proc(c: Escape_Context, s: []u8) -> (Escape_Context, int) {
	return _t_css_str(c, s, '"', .CSS_URL)
}

_t_css_sq_url :: proc(c: Escape_Context, s: []u8) -> (Escape_Context, int) {
	return _t_css_str(c, s, '\'', .CSS_URL)
}

_t_css_str :: proc(
	c: Escape_Context,
	s: []u8,
	quote: u8,
	ret_state: Context_State,
) -> (
	Escape_Context,
	int,
) {
	for i in 0 ..< len(s) {
		if s[i] == '\\' {
			return c, i + 2
		}
		if s[i] == quote {
			return Escape_Context{state = ret_state, element = c.element}, i + 1
		}
	}
	return c, len(s)
}

_t_css_url :: proc(c: Escape_Context, s: []u8) -> (Escape_Context, int) {
	for i in 0 ..< len(s) {
		if s[i] == ')' {
			return Escape_Context{state = .CSS, element = c.element}, i + 1
		}
	}
	return c, len(s)
}

_t_css_block_cmt :: proc(c: Escape_Context, s: []u8) -> (Escape_Context, int) {
	if len(s) < 2 {
		return c, len(s)
	}
	for i in 0 ..< len(s) - 1 {
		if s[i] == '*' && s[i + 1] == '/' {
			return Escape_Context{state = .CSS, element = c.element}, i + 2
		}
	}
	return c, len(s)
}

_t_css_line_cmt :: proc(c: Escape_Context, s: []u8) -> (Escape_Context, int) {
	for i in 0 ..< len(s) {
		if s[i] == '\n' {
			return Escape_Context{state = .CSS, element = c.element}, i + 1
		}
	}
	return c, len(s)
}

_t_error :: proc(c: Escape_Context, s: []u8) -> (Escape_Context, int) {
	return c, len(s)
}

// ---------------------------------------------------------------------------
// HTML parsing helpers
// ---------------------------------------------------------------------------

// _eat_tag_name reads a tag name starting at position i.
// Returns the end position and the element type.
@(private = "package")
_eat_tag_name :: proc(s: []u8, i: int) -> (end: int, elem: Element_Type) {
	if i >= len(s) {
		return i, .None
	}
	// Tag name must start with a letter.
	if !_is_alpha(s[i]) {
		return i, .None
	}
	j := i + 1
	for j < len(s) && (_is_alpha_numeric(s[j]) || s[j] == '-' || s[j] == ':') {
		j += 1
	}
	name := string(s[i:j])
	return j, _element_type_of(name)
}

// _eat_white_space skips ASCII whitespace.
@(private = "package")
_eat_white_space :: proc(s: []u8, i: int) -> int {
	j := i
	for j < len(s) &&
	    (s[j] == ' ' || s[j] == '\t' || s[j] == '\n' || s[j] == '\r' || s[j] == '\f') {
		j += 1
	}
	return j
}

// _eat_attr_name reads an attribute name.
@(private = "package")
_eat_attr_name :: proc(s: []u8, i: int) -> int {
	j := i
	for j < len(s) {
		b := s[j]
		if b == ' ' ||
		   b == '\t' ||
		   b == '\n' ||
		   b == '\r' ||
		   b == '\f' ||
		   b == '=' ||
		   b == '>' ||
		   b == '/' ||
		   b == '"' ||
		   b == '\'' {
			break
		}
		j += 1
	}
	return j
}

// _is_delim_end checks if a byte terminates the current attribute value.
@(private = "package")
_is_delim_end :: proc(b: u8, delim: Delim_Type) -> bool {
	switch delim {
	case .Double_Quote:
		return b == '"'
	case .Single_Quote:
		return b == '\''
	case .Space_Or_Tag_End:
		return b == ' ' || b == '\t' || b == '\n' || b == '\r' || b == '\f' || b == '>'
	case .None:
		return false
	}
	return false
}

// _attr_type classifies an attribute name (case-insensitive).
@(private = "package")
_attr_type :: proc(name: string, elem: Element_Type) -> Attr_Type {
	if _ascii_eq_lower(name, "style") {
		return .Style
	}
	url_attrs := [?]string {
		"href",
		"src",
		"action",
		"formaction",
		"cite",
		"data",
		"poster",
		"background",
		"codebase",
		"longdesc",
		"usemap",
		"manifest",
		"icon",
		"list",
	}
	for attr in url_attrs {
		if _ascii_eq_lower(name, attr) {
			return .URL
		}
	}
	if _ascii_eq_lower(name, "srcset") {
		return .Srcset
	}
	// on* event handlers are script.
	if len(name) >= 3 && _ascii_has_prefix_lower(name, "on") {
		return .Script
	}
	return .None
}

// _attr_start_state returns the context state for an attribute value.
@(private = "package")
_attr_start_state :: proc(attr: Attr_Type, elem: Element_Type) -> Context_State {
	switch attr {
	case .Script:
		return .JS
	case .Script_Type:
		return .Attr
	case .Style:
		return .CSS
	case .URL:
		return .URL
	case .Srcset:
		return .Srcset
	case .None:
		return .Attr
	}
	return .Attr
}

// _element_type_of maps element names to types (case-insensitive).
@(private = "package")
_element_type_of :: proc(name: string) -> Element_Type {
	if _ascii_eq_lower(name, "script") {
		return .Script
	}
	if _ascii_eq_lower(name, "style") {
		return .Style
	}
	if _ascii_eq_lower(name, "textarea") {
		return .Textarea
	}
	if _ascii_eq_lower(name, "title") {
		return .Title
	}
	return .None
}

// _is_alpha checks if a byte is an ASCII letter.
@(private = "package")
_is_alpha :: proc(b: u8) -> bool {
	return (b >= 'a' && b <= 'z') || (b >= 'A' && b <= 'Z')
}

// _is_alpha_numeric checks if a byte is an ASCII letter or digit.
@(private = "package")
_is_alpha_numeric :: proc(b: u8) -> bool {
	return _is_alpha(b) || (b >= '0' && b <= '9')
}

// _ascii_eq_lower does case-insensitive comparison of s against a lowercase target.
@(private = "package")
_ascii_eq_lower :: proc(s: string, target: string) -> bool {
	if len(s) != len(target) {
		return false
	}
	for i in 0 ..< len(s) {
		c := s[i]
		if c >= 'A' && c <= 'Z' {
			c += 32
		}
		if c != target[i] {
			return false
		}
	}
	return true
}

// _ascii_has_prefix_lower does case-insensitive prefix check against a lowercase target.
@(private = "package")
_ascii_has_prefix_lower :: proc(s: string, prefix: string) -> bool {
	if len(s) < len(prefix) {
		return false
	}
	for i in 0 ..< len(prefix) {
		c := s[i]
		if c >= 'A' && c <= 'Z' {
			c += 32
		}
		if c != prefix[i] {
			return false
		}
	}
	return true
}
