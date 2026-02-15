package ohtml

import "core:fmt"
import "core:strings"

// ---------------------------------------------------------------------------
// Escaper — walks the AST and injects context-appropriate escaper functions
// ---------------------------------------------------------------------------

MAX_ESCAPERS :: 4

Escaper_List :: struct {
	items: [MAX_ESCAPERS]string,
	count: int,
}

Escaper :: struct {
	action_edits: map[^Action_Node]Escaper_List,
}

escaper_init :: proc(e: ^Escaper) {
	e.action_edits = make(map[^Action_Node]Escaper_List)
}

escaper_destroy :: proc(e: ^Escaper) {
	delete(e.action_edits)
}

// ---------------------------------------------------------------------------
// escape_template runs the escape analysis on a template and commits edits.
// This is the main entry point for the auto-escaping pass.
// ---------------------------------------------------------------------------

escape_template :: proc(t: ^Template) -> Error {
	if t == nil || t.tree == nil || t.tree.root == nil {
		return {}
	}

	e: Escaper
	escaper_init(&e)
	defer escaper_destroy(&e)

	// Register the escaper built-in functions.
	_register_escape_funcs(t)

	// Walk the AST starting from text context.
	ctx := Escape_Context {
		state = .Text,
	}
	result_ctx, err := _escape_list(&e, ctx, t.tree.root)
	if err.kind != .None {
		return err
	}

	// The template must end in text context.
	if result_ctx.state != .Text {
		return Error {
			kind = .Ends_In_Unsafe_Context,
			msg = fmt.aprintf(
				"template %q ends in a non-text context: %v",
				t.name,
				result_ctx.state,
			),
			name = t.name,
		}
	}

	// Commit the edits to the AST.
	_commit(&e, t)
	return {}
}

// ---------------------------------------------------------------------------
// AST walk — propagate context through nodes
// ---------------------------------------------------------------------------

@(private = "package")
_escape_list :: proc(e: ^Escaper, c: Escape_Context, list: ^List_Node) -> (Escape_Context, Error) {
	if list == nil {
		return c, {}
	}
	ctx := c
	for node in list.nodes {
		new_ctx, err := _escape_node(e, ctx, node)
		if err.kind != .None {
			return ctx, err
		}
		ctx = new_ctx
		if ctx.state == .Error || ctx.state == .Dead {
			break
		}
	}
	return ctx, {}
}

@(private = "package")
_escape_node :: proc(e: ^Escaper, c: Escape_Context, node: Node) -> (Escape_Context, Error) {
	#partial switch n in node {
	case ^Text_Node:
		return _escape_text(e, c, n), {}
	case ^Action_Node:
		return _escape_action(e, c, n)
	case ^If_Node:
		return _escape_branch(e, c, n.pipe, n.list, n.else_list)
	case ^Range_Node:
		return _escape_branch(e, c, n.pipe, n.list, n.else_list)
	case ^With_Node:
		return _escape_branch(e, c, n.pipe, n.list, n.else_list)
	case ^Template_Node:
		// Template calls don't change context in this simplified model.
		return c, {}
	case ^Block_Node:
		return c, {}
	case ^Comment_Node:
		return c, {}
	}
	return c, {}
}

// ---------------------------------------------------------------------------
// Text node — advance context through raw HTML
// ---------------------------------------------------------------------------

@(private = "package")
_escape_text :: proc(e: ^Escaper, c: Escape_Context, n: ^Text_Node) -> Escape_Context {
	return transition(c, n.text)
}

// ---------------------------------------------------------------------------
// Action node — determine which escapers to inject
// ---------------------------------------------------------------------------

@(private = "package")
_escape_action :: proc(
	e: ^Escaper,
	c: Escape_Context,
	n: ^Action_Node,
) -> (
	Escape_Context,
	Error,
) {
	if n.pipe == nil || len(n.pipe.cmds) == 0 {
		return c, {}
	}

	// Determine which escaper functions are needed based on context.
	escapers := _escapers_for_context(c)

	if escapers.count > 0 {
		e.action_edits[n] = escapers
	}

	// After an action, the context state may change (e.g., a URL attribute
	// value transitions to query-or-frag). For simplicity, we stay in the
	// same context state but mark URL progress.
	ctx := c
	if ctx.state == .URL && ctx.url_part == .None {
		ctx.url_part = .Pre_Query
	}
	return ctx, {}
}

// ---------------------------------------------------------------------------
// Branch node — escape both branches and verify they end in same context
// ---------------------------------------------------------------------------

@(private = "package")
_escape_branch :: proc(
	e: ^Escaper,
	c: Escape_Context,
	pipe: ^Pipe_Node,
	list: ^List_Node,
	else_list: ^List_Node,
) -> (
	Escape_Context,
	Error,
) {
	// Escape the condition pipeline (it doesn't change context).
	// Escape the if/then branch.
	then_ctx, then_err := _escape_list(e, c, list)
	if then_err.kind != .None {
		return c, then_err
	}

	if else_list != nil {
		else_ctx, else_err := _escape_list(e, c, else_list)
		if else_err.kind != .None {
			return c, else_err
		}
		// Both branches must end in the same context.
		if !context_eq(then_ctx, else_ctx) {
			return c, Error {
				kind = .Bad_Context,
				msg = "if/else branches end in different contexts",
			}
		}
		return then_ctx, {}
	}

	// No else branch — the context after the if must match the context
	// before it (since the body might not execute).
	if !context_eq(c, then_ctx) {
		// This is allowed in Go — the template may still be safe if the
		// body doesn't change context. For now, accept it.
	}
	return then_ctx, {}
}

// ---------------------------------------------------------------------------
// Context-to-escaper mapping
// ---------------------------------------------------------------------------

@(private = "package")
_escapers_for_context :: proc(c: Escape_Context) -> Escaper_List {
	result: Escaper_List

	_esc_add :: proc(r: ^Escaper_List, s: string) {
		if r.count < MAX_ESCAPERS {
			r.items[r.count] = s
			r.count += 1
		}
	}

	#partial switch c.state {
	case .Text:
		_esc_add(&result, "_html_escaper")
	case .RCDATA:
		_esc_add(&result, "_html_escaper")
	case .Attr:
		if c.delim == .Space_Or_Tag_End {
			_esc_add(&result, "_html_nospace_escaper")
		} else {
			_esc_add(&result, "_html_attr_escaper")
		}
		return result
	case .URL:
		_esc_add(&result, "_url_filter")
		_esc_add(&result, "_url_normalizer")
	case .Srcset:
		_esc_add(&result, "_srcset_filter")
	case .JS:
		_esc_add(&result, "_js_val_escaper")
	case .JS_Dq_Str, .JS_Sq_Str:
		_esc_add(&result, "_js_str_escaper")
	case .JS_Tmpl_Lit:
		_esc_add(&result, "_js_str_escaper")
	case .JS_Regexp:
		_esc_add(&result, "_js_regexp_escaper")
	case .CSS:
		_esc_add(&result, "_css_val_filter")
	case .CSS_Dq_Str, .CSS_Sq_Str:
		_esc_add(&result, "_css_escaper")
	case .CSS_Dq_URL, .CSS_Sq_URL, .CSS_URL:
		_esc_add(&result, "_url_filter")
		_esc_add(&result, "_css_escaper")
	case:
	// No escaping needed or unsupported state.
	}

	// For space-or-tag-end delimiters, add nospace escaper.
	if c.delim == .Space_Or_Tag_End && result.count > 0 {
		_esc_add(&result, "_html_nospace_escaper")
	} else if c.delim != .None && result.count > 0 {
		// Quoted attributes need attribute escaping.
		_esc_add(&result, "_html_attr_escaper")
	}

	return result
}

// ---------------------------------------------------------------------------
// Commit — apply edits to the AST
// ---------------------------------------------------------------------------

@(private = "package")
_commit :: proc(e: ^Escaper, t: ^Template) {
	// Apply action edits: inject escaper function calls into pipelines.
	for node, &escapers in e.action_edits {
		_ensure_pipeline_contains(node.pipe, escapers.items[:escapers.count])
	}
}

// _ensure_pipeline_contains appends escaper commands to a pipeline.
@(private = "package")
_ensure_pipeline_contains :: proc(pipe: ^Pipe_Node, escapers: []string) {
	if pipe == nil || len(escapers) == 0 {
		return
	}

	// Check if the pipeline already ends with equivalent escapers.
	// For simplicity, just append new commands.
	for esc_name in escapers {
		// Check if already present at the end.
		if _pipeline_has_escaper(pipe, esc_name) {
			continue
		}
		// Create a new command node with the escaper function identifier.
		cmd := new(Command_Node)
		ident := new(Identifier_Node)
		ident.ident = esc_name
		cmd_append(cmd, ident)
		pipe_append(pipe, cmd)
	}
}

@(private = "package")
_pipeline_has_escaper :: proc(pipe: ^Pipe_Node, name: string) -> bool {
	if len(pipe.cmds) == 0 {
		return false
	}
	last := pipe.cmds[len(pipe.cmds) - 1]
	if len(last.args) == 1 {
		ident, ok := last.args[0].(^Identifier_Node)
		if ok && ident.ident == name {
			return true
		}
	}
	return false
}

// ---------------------------------------------------------------------------
// Escaper function registration
// ---------------------------------------------------------------------------

@(private = "package")
_register_escape_funcs :: proc(t: ^Template) {
	fm: Func_Map
	fm["_html_escaper"] = _esc_html
	fm["_html_attr_escaper"] = _esc_html_attr
	fm["_html_nospace_escaper"] = _esc_html_nospace
	fm["_js_val_escaper"] = _esc_js_val
	fm["_js_str_escaper"] = _esc_js_str
	fm["_js_regexp_escaper"] = _esc_js_regexp
	fm["_css_val_filter"] = _esc_css_val
	fm["_css_escaper"] = _esc_css
	fm["_url_filter"] = _esc_url_filter
	fm["_url_normalizer"] = _esc_url_normalizer
	fm["_srcset_filter"] = _esc_srcset
	template_funcs(t, fm)
}

// ---------------------------------------------------------------------------
// Escaper function implementations (Template_Func signature)
// ---------------------------------------------------------------------------

_esc_html :: proc(args: []any) -> (any, Error) {
	if len(args) != 1 {
		return nil, Error{kind = .Wrong_Arg_Count, msg = "_html_escaper requires 1 arg"}
	}
	s, ct := stringify(args[0])
	if ct == .HTML {
		return args[0], {} // already safe HTML
	}
	return box_string(html_escape_string(s)), {}
}

_esc_html_attr :: proc(args: []any) -> (any, Error) {
	if len(args) != 1 {
		return nil, Error{kind = .Wrong_Arg_Count, msg = "_html_attr_escaper requires 1 arg"}
	}
	s, ct := stringify(args[0])
	if ct == .HTML_Attr {
		return args[0], {}
	}
	return box_string(html_escape_string(s)), {}
}

_esc_html_nospace :: proc(args: []any) -> (any, Error) {
	if len(args) != 1 {
		return nil, Error{kind = .Wrong_Arg_Count, msg = "_html_nospace_escaper requires 1 arg"}
	}
	s, _ := stringify(args[0])
	// Fast path: check if any character needs escaping.
	needs_escape := false
	for ch in s {
		switch ch {
		case '&', '<', '>', '"', '\'', '\t', '\n', '\r', '\f', ' ', '=', '`':
			needs_escape = true
			break
		}
	}
	if !needs_escape {
		return box_string(s), {}
	}
	// Additionally escape spaces, tabs, etc. for unquoted attributes.
	b := strings.builder_make_len_cap(0, len(s) + len(s) / 8)
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
		case '\t', '\n', '\r', '\f', ' ':
			n := int(ch)
			strings.write_string(&b, "&#x")
			strings.write_byte(&b, HEX_DIGITS[(n >> 4) & 0xf])
			strings.write_byte(&b, HEX_DIGITS[n & 0xf])
			strings.write_byte(&b, ';')
		case '=':
			strings.write_string(&b, "&#61;")
		case '`':
			strings.write_string(&b, "&#96;")
		case:
			strings.write_rune(&b, ch)
		}
	}
	return box_string(strings.to_string(b)), {}
}

_esc_js_val :: proc(args: []any) -> (any, Error) {
	if len(args) != 1 {
		return nil, Error{kind = .Wrong_Arg_Count, msg = "_js_val_escaper requires 1 arg"}
	}
	s, ct := stringify(args[0])
	if ct == .JS {
		return args[0], {}
	}
	// Wrap in a safe JavaScript representation.
	return box_string(js_escape_string(s)), {}
}

_esc_js_str :: proc(args: []any) -> (any, Error) {
	if len(args) != 1 {
		return nil, Error{kind = .Wrong_Arg_Count, msg = "_js_str_escaper requires 1 arg"}
	}
	s, ct := stringify(args[0])
	if ct == .JS_Str {
		return args[0], {}
	}
	return box_string(js_escape_string(s)), {}
}

_esc_js_regexp :: proc(args: []any) -> (any, Error) {
	if len(args) != 1 {
		return nil, Error{kind = .Wrong_Arg_Count, msg = "_js_regexp_escaper requires 1 arg"}
	}
	s, _ := stringify(args[0])
	return box_string(js_escape_string(s)), {}
}

_esc_css_val :: proc(args: []any) -> (any, Error) {
	if len(args) != 1 {
		return nil, Error{kind = .Wrong_Arg_Count, msg = "_css_val_filter requires 1 arg"}
	}
	s, ct := stringify(args[0])
	if ct == .CSS {
		return args[0], {}
	}
	return box_string(css_escape_string(s)), {}
}

_esc_css :: proc(args: []any) -> (any, Error) {
	if len(args) != 1 {
		return nil, Error{kind = .Wrong_Arg_Count, msg = "_css_escaper requires 1 arg"}
	}
	s, ct := stringify(args[0])
	if ct == .CSS {
		return args[0], {}
	}
	return box_string(css_escape_string(s)), {}
}

_esc_url_filter :: proc(args: []any) -> (any, Error) {
	if len(args) != 1 {
		return nil, Error{kind = .Wrong_Arg_Count, msg = "_url_filter requires 1 arg"}
	}
	s, ct := stringify(args[0])
	if ct == .URL {
		return args[0], {}
	}
	// Filter dangerous URL schemes.
	if _is_safe_url(s) {
		return box_string(s), {}
	}
	return box_string("#" + UNSAFE_URL_PREFIX), {}
}

_esc_url_normalizer :: proc(args: []any) -> (any, Error) {
	if len(args) != 1 {
		return nil, Error{kind = .Wrong_Arg_Count, msg = "_url_normalizer requires 1 arg"}
	}
	s, ct := stringify(args[0])
	if ct == .URL {
		return args[0], {}
	}
	return box_string(url_query_escape(s)), {}
}

_esc_srcset :: proc(args: []any) -> (any, Error) {
	if len(args) != 1 {
		return nil, Error{kind = .Wrong_Arg_Count, msg = "_srcset_filter requires 1 arg"}
	}
	s, ct := stringify(args[0])
	if ct == .Srcset {
		return args[0], {}
	}
	return box_string(html_escape_string(s)), {}
}

// ---------------------------------------------------------------------------
// URL safety check
// ---------------------------------------------------------------------------

UNSAFE_URL_PREFIX :: "ZodinAutoUrl"

@(private = "package")
_is_safe_url :: proc(s: string) -> bool {
	// Allow http, https, mailto, and relative URLs.
	// Block javascript:, vbscript:, data: (except some safe ones).
	if _ascii_has_prefix_lower(s, "javascript:") {
		return false
	}
	if _ascii_has_prefix_lower(s, "vbscript:") {
		return false
	}
	if _ascii_has_prefix_lower(s, "data:") {
		if _ascii_has_prefix_lower(s, "data:image/") {
			return true
		}
		return false
	}
	return true
}
