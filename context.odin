package ohtml

// ---------------------------------------------------------------------------
// Escape_Context — tracks the HTML/JS/CSS parsing state during escaping
// ---------------------------------------------------------------------------

Escape_Context :: struct {
	state:    Context_State,
	delim:    Delim_Type,
	url_part: URL_Part,
	js_ctx:   JS_Ctx,
	attr:     Attr_Type,
	element:  Element_Type,
}

// Context_State enumerates the HTML parser states.
Context_State :: enum {
	Text,
	Tag,
	Attr_Name,
	After_Name,
	Before_Value,
	HTML_Cmt,
	RCDATA,
	Attr,
	URL,
	Srcset,
	JS,
	JS_Dq_Str,
	JS_Sq_Str,
	JS_Tmpl_Lit,
	JS_Regexp,
	JS_Block_Cmt,
	JS_Line_Cmt,
	JS_HTML_Open_Cmt,
	JS_HTML_Close_Cmt,
	CSS,
	CSS_Dq_Str,
	CSS_Sq_Str,
	CSS_Dq_URL,
	CSS_Sq_URL,
	CSS_URL,
	CSS_Block_Cmt,
	CSS_Line_Cmt,
	Error,
	Dead,
}

// Delim_Type enumerates attribute delimiter types.
Delim_Type :: enum {
	None,
	Double_Quote,
	Single_Quote,
	Space_Or_Tag_End,
}

// URL_Part enumerates which part of a URL we're in.
URL_Part :: enum {
	None,
	Pre_Query,
	Query_Or_Frag,
	Unknown,
}

// JS_Ctx tracks JavaScript parsing context for regexp vs division.
JS_Ctx :: enum {
	Regexp,
	Div_Op,
	Unknown,
}

// Attr_Type enumerates special HTML attribute types.
Attr_Type :: enum {
	None,
	Script,
	Script_Type,
	Style,
	URL,
	Srcset,
}

// Element_Type enumerates special HTML element types.
Element_Type :: enum {
	None,
	Script,
	Style,
	Textarea,
	Title,
}

// is_in_js returns true if the context state is within JavaScript.
is_in_js :: proc(c: Escape_Context) -> bool {
	#partial switch c.state {
	case .JS,
	     .JS_Dq_Str,
	     .JS_Sq_Str,
	     .JS_Tmpl_Lit,
	     .JS_Regexp,
	     .JS_Block_Cmt,
	     .JS_Line_Cmt,
	     .JS_HTML_Open_Cmt,
	     .JS_HTML_Close_Cmt:
		return true
	}
	return false
}

// is_in_css returns true if the context state is within CSS.
is_in_css :: proc(c: Escape_Context) -> bool {
	#partial switch c.state {
	case .CSS,
	     .CSS_Dq_Str,
	     .CSS_Sq_Str,
	     .CSS_Dq_URL,
	     .CSS_Sq_URL,
	     .CSS_URL,
	     .CSS_Block_Cmt,
	     .CSS_Line_Cmt:
		return true
	}
	return false
}

// context_eq compares two contexts for equality (ignoring node/error).
context_eq :: proc(a: Escape_Context, b: Escape_Context) -> bool {
	return(
		a.state == b.state &&
		a.delim == b.delim &&
		a.url_part == b.url_part &&
		a.js_ctx == b.js_ctx &&
		a.attr == b.attr &&
		a.element == b.element \
	)
}
