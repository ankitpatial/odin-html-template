package cli

import "core:fmt"
import "core:strings"

import ohtml "../"

// ---------------------------------------------------------------------------
// Generator — walks the escaped AST and emits Odin source code
// ---------------------------------------------------------------------------

Gen_Context :: struct {
	registry:     ^Type_Registry,
	emitter:      ^Emitter,
	// Stack of dot types — push on range/with, pop on exit
	dot_stack:    [dynamic]string, // struct name at each level
	type_stack:   [dynamic]Type_Info, // full type info at each level
	// Stack of dot expressions — what code to emit for "."
	expr_stack:   [dynamic]string, // e.g. "data", "_dot_1"
	// Buffer counter for int formatting
	buf_count:    int,
	// Template name for sub-template proc generation
	tmpl_name:    string,
	// Collected sub-template procs
	sub_procs:    [dynamic]string,
	// Package name for the generated code
	pkg_name:     string,
	// Import path for ohtml
	ohtml_import: string,
	// All templates in the set (for template/block calls)
	all_tmpls:    ^ohtml.Template,
	// Whether the generated code uses "core:fmt"
	uses_fmt:     bool,
	// Which ohtml helpers are used (accumulated across all templates)
	helpers:      Helper_Flags,
}

Helper_Flags :: struct {
	html_escape:         bool,
	html_nospace_escape: bool,
	js_escape:           bool,
	css_escape:          bool,
	url_filter:          bool,
	url_query_escape:    bool,
	write_int:           bool,
	write_uint:          bool,
}

gen_init :: proc(
	g: ^Gen_Context,
	registry: ^Type_Registry,
	pkg_name: string,
	ohtml_import: string,
) {
	g.registry = registry
	g.pkg_name = pkg_name
	g.ohtml_import = ohtml_import
	g.dot_stack = make([dynamic]string)
	g.type_stack = make([dynamic]Type_Info)
	g.expr_stack = make([dynamic]string)
	g.sub_procs = make([dynamic]string)
}

gen_destroy :: proc(g: ^Gen_Context) {
	delete(g.dot_stack)
	delete(g.type_stack)
	delete(g.expr_stack)
	for s in g.sub_procs {
		delete(s)
	}
	delete(g.sub_procs)
}

current_dot_type :: proc(g: ^Gen_Context) -> string {
	if len(g.dot_stack) > 0 {
		return g.dot_stack[len(g.dot_stack) - 1]
	}
	return ""
}

current_dot_type_info :: proc(g: ^Gen_Context) -> Type_Info {
	if len(g.type_stack) > 0 {
		return g.type_stack[len(g.type_stack) - 1]
	}
	return Type_Info{kind = .Named}
}

current_dot_expr :: proc(g: ^Gen_Context) -> string {
	if len(g.expr_stack) > 0 {
		return g.expr_stack[len(g.expr_stack) - 1]
	}
	return "data"
}

push_dot :: proc(g: ^Gen_Context, type_name: string, expr: string, ti: Type_Info = {}) {
	append(&g.dot_stack, type_name)
	append(&g.type_stack, ti)
	append(&g.expr_stack, expr)
}

pop_dot :: proc(g: ^Gen_Context) {
	if len(g.dot_stack) > 0 {
		pop(&g.dot_stack)
		pop(&g.type_stack)
		pop(&g.expr_stack)
	}
}

// ---------------------------------------------------------------------------
// Generate a complete .odin file for a template
// ---------------------------------------------------------------------------

generate_template :: proc(
	g: ^Gen_Context,
	e: ^Emitter,
	tmpl: ^ohtml.Template,
	proc_name: string,
	data_type: string,
) {
	g.emitter = e
	g.all_tmpls = tmpl
	g.tmpl_name = proc_name
	g.uses_fmt = false

	// Push initial dot
	push_dot(g, data_type, "data", Type_Info{kind = .Named, name = data_type})
	defer pop_dot(g)

	// Generate the body into a separate emitter first, so we know if fmt is used.
	body_e: Emitter
	emitter_init(&body_e)
	defer emitter_destroy(&body_e)

	g.emitter = &body_e

	// Main render proc
	emit_line(&body_e, fmt.aprintf("%s :: proc(w: io.Writer, data: ^%s) {{", proc_name, data_type))
	indent(&body_e)

	// Walk the AST
	if tmpl.tree != nil && tmpl.tree.root != nil {
		gen_list(g, tmpl.tree.root)
	}

	dedent(&body_e)
	emit_line(&body_e, "}")

	// Emit any sub-template procs collected during generation
	for sub in g.sub_procs {
		emit_newline(&body_e)
		emit_raw(&body_e, sub)
	}

	// Now emit the file header into the real emitter, with conditional fmt import.
	g.emitter = e
	emit_line(e, fmt.aprintf("package %s", g.pkg_name))
	emit_newline(e)
	emit_line(e, "import \"core:io\"")
	if g.uses_fmt {
		emit_line(e, "import \"core:fmt\"")
	}
	emit_newline(e)

	// Append the body
	emit_raw(e, emitter_to_string(&body_e))
}

// ---------------------------------------------------------------------------
// AST node generators
// ---------------------------------------------------------------------------

gen_list :: proc(g: ^Gen_Context, list: ^ohtml.List_Node) {
	if list == nil {
		return
	}
	for node in list.nodes {
		gen_node(g, node)
	}
}

gen_node :: proc(g: ^Gen_Context, node: ohtml.Node) {
	e := g.emitter

	switch n in node {
	case ^ohtml.List_Node:
		gen_list(g, n)
	case ^ohtml.Text_Node:
		gen_text(g, n)
	case ^ohtml.Action_Node:
		gen_action(g, n)
	case ^ohtml.If_Node:
		gen_if(g, n)
	case ^ohtml.Range_Node:
		gen_range(g, n)
	case ^ohtml.With_Node:
		gen_with(g, n)
	case ^ohtml.Template_Node:
		gen_template_call(g, n)
	case ^ohtml.Block_Node:
		gen_block(g, n)
	case ^ohtml.Comment_Node:
	// Comments produce no output
	case ^ohtml.Break_Node:
		emit_line(e, "break")
	case ^ohtml.Continue_Node:
		emit_line(e, "continue")
	case ^ohtml.Dot_Node,
	     ^ohtml.Nil_Node,
	     ^ohtml.Bool_Node,
	     ^ohtml.Number_Node,
	     ^ohtml.String_Node,
	     ^ohtml.Field_Node,
	     ^ohtml.Variable_Node,
	     ^ohtml.Identifier_Node,
	     ^ohtml.Chain_Node,
	     ^ohtml.Pipe_Node,
	     ^ohtml.Command_Node:
	// These are handled via eval paths, not directly walked
	case nil:
	}
}

// ---------------------------------------------------------------------------
// Text node — emit io.write_string for raw HTML text
// ---------------------------------------------------------------------------

gen_text :: proc(g: ^Gen_Context, n: ^ohtml.Text_Node) {
	e := g.emitter
	text := _minify_html_text(string(n.text))
	if len(text) == 0 {
		return
	}
	emit_indent(e)
	emit_raw(e, "io.write_string(w, ")
	emit_raw(e, escape_string_literal(text))
	emit_raw(e, ")\n")
}

// _minify_html_text collapses whitespace in static HTML text at compile time.
// - Strips <!-- ... --> comment blocks (including directive comments)
// - Collapses runs of whitespace (spaces/tabs/newlines) to a single space
// - Trims leading and trailing whitespace
_minify_html_text :: proc(s: string) -> string {
	// Strip HTML comments
	stripped := _strip_html_comments(s)
	defer if stripped != s {delete(stripped)}

	// Collapse whitespace runs to single space
	b := strings.builder_make_len_cap(0, len(stripped))
	in_ws := false
	for i in 0 ..< len(stripped) {
		ch := stripped[i]
		if ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r' {
			if !in_ws {
				strings.write_byte(&b, ' ')
				in_ws = true
			}
		} else {
			strings.write_byte(&b, ch)
			in_ws = false
		}
	}

	result := strings.trim_space(strings.to_string(b))
	return result
}

// _strip_html_comments removes <!-- ... --> blocks from text.
_strip_html_comments :: proc(s: string) -> string {
	if !strings.contains(s, "<!--") {
		return s
	}

	b := strings.builder_make_len_cap(0, len(s))
	rest := s
	for {
		idx := strings.index(rest, "<!--")
		if idx < 0 {
			strings.write_string(&b, rest)
			break
		}
		strings.write_string(&b, rest[:idx])
		rest = rest[idx:]
		end := strings.index(rest, "-->")
		if end < 0 {
			break // unclosed comment, drop the rest
		}
		rest = rest[end + 3:]
	}
	return strings.to_string(b)
}

// ---------------------------------------------------------------------------
// Action node — evaluate pipeline, write result with escaping
// ---------------------------------------------------------------------------

gen_action :: proc(g: ^Gen_Context, n: ^ohtml.Action_Node) {
	if n.pipe == nil || len(n.pipe.cmds) == 0 {
		return
	}

	e := g.emitter

	// Check if the pipeline has variable declarations
	has_decl := len(n.pipe.decl) > 0

	if has_decl {
		// Variable assignment: $x := expr
		expr, expr_type := gen_pipeline_expr(g, n.pipe)
		for v in n.pipe.decl {
			var_name := _odin_var_name(v.ident[0])
			emit_indent(e)
			if n.pipe.is_assign {
				emit_raw(e, fmt.aprintf("%s = %s\n", var_name, expr))
			} else {
				type_str := _odin_type_for(expr_type)
				emit_raw(e, fmt.aprintf("%s : %s = %s\n", var_name, type_str, expr))
			}
		}
	} else {
		// Print the result: evaluate and write
		gen_pipeline_write(g, n.pipe)
	}
}

// ---------------------------------------------------------------------------
// Pipeline expression generation
// ---------------------------------------------------------------------------

// gen_pipeline_expr evaluates a pipeline and returns the Odin expression string
// and the resolved type info.
gen_pipeline_expr :: proc(g: ^Gen_Context, pipe: ^ohtml.Pipe_Node) -> (string, Type_Info) {
	if pipe == nil || len(pipe.cmds) == 0 {
		return "nil", Type_Info{}
	}

	// For multi-command pipelines, chain them: each command's output feeds the next
	expr: string
	ti: Type_Info
	for cmd, i in pipe.cmds {
		prev_expr := expr if i > 0 else ""
		expr, ti = gen_command_expr(g, cmd, prev_expr)
	}
	return expr, ti
}

// gen_pipeline_write evaluates a pipeline and writes its output to the writer.
gen_pipeline_write :: proc(g: ^Gen_Context, pipe: ^ohtml.Pipe_Node) {
	if pipe == nil || len(pipe.cmds) == 0 {
		return
	}

	e := g.emitter
	num_cmds := len(pipe.cmds)

	// Separate escape commands from the "real" commands.
	// Escape commands are injected by escape_template and start with '_'.
	first_esc := num_cmds
	for i in 0 ..< num_cmds {
		cmd := pipe.cmds[i]
		if len(cmd.args) == 1 {
			if ident, ok := cmd.args[0].(^ohtml.Identifier_Node); ok {
				if len(ident.ident) > 0 && ident.ident[0] == '_' {
					first_esc = i
					break
				}
			}
		}
	}

	// Evaluate the non-escape portion of the pipeline
	expr: string
	ti: Type_Info
	for i in 0 ..< first_esc {
		prev := expr if i > 0 else ""
		expr, ti = gen_command_expr(g, pipe.cmds[i], prev)
	}

	// Collect escape function names
	escapers: [dynamic]string
	defer delete(escapers)
	for i in first_esc ..< num_cmds {
		cmd := pipe.cmds[i]
		if len(cmd.args) == 1 {
			if ident, ok := cmd.args[0].(^ohtml.Identifier_Node); ok {
				append(&escapers, ident.ident)
			}
		}
	}

	// Write the expression with appropriate escaping
	_write_escaped_expr(g, expr, ti, escapers[:])
}

// gen_command_expr evaluates a single command and returns the Odin expression.
// pipe_val is the piped-in value from the previous command (empty if first).
gen_command_expr :: proc(
	g: ^Gen_Context,
	cmd: ^ohtml.Command_Node,
	pipe_val: string,
) -> (
	string,
	Type_Info,
) {
	if len(cmd.args) == 0 {
		return "nil", Type_Info{}
	}

	first := cmd.args[0]

	#partial switch n in first {
	case ^ohtml.Dot_Node:
		return current_dot_expr(g), current_dot_type_info(g)
	case ^ohtml.Nil_Node:
		return "nil", Type_Info{}
	case ^ohtml.Bool_Node:
		return "true" if n.val else "false", Type_Info{kind = .Bool}
	case ^ohtml.Number_Node:
		return n.text, _number_type_info(n)
	case ^ohtml.String_Node:
		return escape_string_literal(n.text), Type_Info{kind = .String}
	case ^ohtml.Field_Node:
		return gen_field_expr(g, n.ident)
	case ^ohtml.Variable_Node:
		return gen_variable_expr(g, n)
	case ^ohtml.Identifier_Node:
		return gen_func_call_expr(g, n.ident, cmd.args[1:], pipe_val)
	case ^ohtml.Pipe_Node:
		return gen_pipeline_expr(g, n)
	case ^ohtml.Chain_Node:
		return gen_chain_expr(g, n)
	}
	return "nil", Type_Info{}
}

// gen_field_expr generates a field access expression like "data.name" or "_dot_1.field"
gen_field_expr :: proc(g: ^Gen_Context, ident: []string) -> (string, Type_Info) {
	dot := current_dot_expr(g)
	dot_type := current_dot_type(g)

	if len(ident) == 0 {
		return dot, Type_Info{kind = .Named, name = dot_type}
	}

	b := strings.builder_make_len_cap(0, 64)
	strings.write_string(&b, dot)
	for field in ident {
		strings.write_byte(&b, '.')
		strings.write_string(&b, field)
	}

	// Resolve the type
	ti, ok := resolve_field_chain(g.registry, dot_type, ident)
	if !ok {
		ti = Type_Info {
			kind = .Unknown,
		}
	}

	return strings.to_string(b), ti
}

// gen_variable_expr generates a variable reference expression
gen_variable_expr :: proc(g: ^Gen_Context, v: ^ohtml.Variable_Node) -> (string, Type_Info) {
	name := v.ident[0]
	if name == "$" {
		// $ refers to root data
		if len(v.ident) == 1 {
			return "data", Type_Info {
				kind = .Named,
				name = g.dot_stack[0] if len(g.dot_stack) > 0 else "",
			}
		}
		// $.Field.Sub...
		b := strings.builder_make_len_cap(0, 64)
		strings.write_string(&b, "data")
		for field in v.ident[1:] {
			strings.write_byte(&b, '.')
			strings.write_string(&b, field)
		}
		root_type := g.dot_stack[0] if len(g.dot_stack) > 0 else ""
		ti, ok := resolve_field_chain(g.registry, root_type, v.ident[1:])
		if !ok {
			ti = Type_Info {
				kind = .Unknown,
			}
		}
		return strings.to_string(b), ti
	}

	odin_name := _odin_var_name(name)
	if len(v.ident) == 1 {
		return odin_name, Type_Info{kind = .Unknown}
	}

	// $var.Field.Sub...
	b := strings.builder_make_len_cap(0, 64)
	strings.write_string(&b, odin_name)
	for field in v.ident[1:] {
		strings.write_byte(&b, '.')
		strings.write_string(&b, field)
	}
	return strings.to_string(b), Type_Info{kind = .Unknown}
}

// gen_chain_expr generates (expr).Field1.Field2
gen_chain_expr :: proc(g: ^Gen_Context, chain: ^ohtml.Chain_Node) -> (string, Type_Info) {
	base_expr, _ := gen_arg_expr(g, chain.node)

	b := strings.builder_make_len_cap(0, 64)
	strings.write_string(&b, base_expr)
	for field in chain.field {
		strings.write_byte(&b, '.')
		strings.write_string(&b, field)
	}
	return strings.to_string(b), Type_Info{kind = .Unknown}
}

// gen_func_call_expr generates a builtin function call expression
gen_func_call_expr :: proc(
	g: ^Gen_Context,
	name: string,
	args: []ohtml.Node,
	pipe_val: string,
) -> (
	string,
	Type_Info,
) {
	switch name {
	case "len":
		arg := _get_single_arg(g, args, pipe_val)
		return fmt.aprintf("len(%s)", arg), Type_Info{kind = .Int}
	case "index":
		if len(args) >= 2 {
			collection, _ := gen_arg_expr(g, args[0])
			index_expr, _ := gen_arg_expr(g, args[1])
			return fmt.aprintf("%s[%s]", collection, index_expr), Type_Info{kind = .Unknown}
		}
	case "eq":
		return _gen_comparison(g, "==", args, pipe_val)
	case "ne":
		return _gen_comparison(g, "!=", args, pipe_val)
	case "lt":
		return _gen_comparison(g, "<", args, pipe_val)
	case "le":
		return _gen_comparison(g, "<=", args, pipe_val)
	case "gt":
		return _gen_comparison(g, ">", args, pipe_val)
	case "ge":
		return _gen_comparison(g, ">=", args, pipe_val)
	case "not":
		arg_expr, arg_ti := _get_single_arg_with_type(g, args, pipe_val)
		not_expr := _gen_not_expr(arg_expr, arg_ti)
		return not_expr, Type_Info{kind = .Bool}
	case "and":
		return _gen_logic_op(g, "&&", args, pipe_val)
	case "or":
		return _gen_logic_op(g, "||", args, pipe_val)
	case "print":
		return _gen_print_call(g, args, pipe_val, "aprint")
	case "printf":
		return _gen_printf_call(g, args, pipe_val)
	case "println":
		return _gen_print_call(g, args, pipe_val, "aprintln")
	case "html":
		arg := _get_single_arg(g, args, pipe_val)
		g.helpers.html_escape = true
		return fmt.aprintf("html_escape(%s)", arg), Type_Info{kind = .String}
	case "js":
		arg := _get_single_arg(g, args, pipe_val)
		g.helpers.js_escape = true
		return fmt.aprintf("js_escape(%s)", arg), Type_Info{kind = .String}
	case "urlquery":
		arg := _get_single_arg(g, args, pipe_val)
		g.helpers.url_query_escape = true
		return fmt.aprintf("url_query_escape(%s)", arg), Type_Info{kind = .String}
	}

	// Unknown function — generate fmt.aprintf fallback
	return fmt.aprintf("nil /* unknown func: %s */", name), Type_Info{kind = .Unknown}
}

// gen_arg_expr evaluates a single argument node to an expression string.
gen_arg_expr :: proc(g: ^Gen_Context, node: ohtml.Node) -> (string, Type_Info) {
	#partial switch n in node {
	case ^ohtml.Dot_Node:
		return current_dot_expr(g), current_dot_type_info(g)
	case ^ohtml.Nil_Node:
		return "nil", Type_Info{}
	case ^ohtml.Bool_Node:
		return "true" if n.val else "false", Type_Info{kind = .Bool}
	case ^ohtml.Number_Node:
		return n.text, _number_type_info(n)
	case ^ohtml.String_Node:
		return escape_string_literal(n.text), Type_Info{kind = .String}
	case ^ohtml.Field_Node:
		return gen_field_expr(g, n.ident)
	case ^ohtml.Variable_Node:
		return gen_variable_expr(g, n)
	case ^ohtml.Identifier_Node:
		return gen_func_call_expr(g, n.ident, nil, "")
	case ^ohtml.Pipe_Node:
		return gen_pipeline_expr(g, n)
	case ^ohtml.Chain_Node:
		return gen_chain_expr(g, n)
	}
	return "nil", Type_Info{}
}

// ---------------------------------------------------------------------------
// If/else generation
// ---------------------------------------------------------------------------

gen_if :: proc(g: ^Gen_Context, n: ^ohtml.If_Node) {
	e := g.emitter
	cond_expr := _gen_truth_expr(g, n.pipe)

	emit_indent(e)
	emit_raw(e, fmt.aprintf("if %s {{\n", cond_expr))
	indent(e)
	gen_list(g, n.list)
	dedent(e)

	if n.else_list != nil {
		emit_line(e, "} else {")
		indent(e)
		gen_list(g, n.else_list)
		dedent(e)
	}
	emit_line(e, "}")
}

// ---------------------------------------------------------------------------
// Range generation
// ---------------------------------------------------------------------------

gen_range :: proc(g: ^Gen_Context, n: ^ohtml.Range_Node) {
	e := g.emitter

	// Evaluate the collection expression
	collection_expr, collection_ti := gen_pipeline_expr(g, n.pipe)

	// Determine element type for the dot inside the range
	elem_type := ""
	elem_ti := Type_Info {
		kind = .Unknown,
	}
	if collection_ti.kind == .Slice ||
	   collection_ti.kind == .Array ||
	   collection_ti.kind == .Dynamic {
		elem_ti = classify_type(collection_ti.elem_type)
		if elem_ti.kind == .Named {
			elem_type = elem_ti.name
		}
	}

	// Determine variable names from range declarations
	has_key := false
	has_val := false
	key_var := "_"
	val_var := "_"
	if n.pipe != nil && len(n.pipe.decl) > 0 {
		ndecl := len(n.pipe.decl)
		if ndecl == 1 {
			val_var = _odin_var_name(n.pipe.decl[0].ident[0])
			has_val = true
		} else if ndecl >= 2 {
			key_var = _odin_var_name(n.pipe.decl[0].ident[0])
			val_var = _odin_var_name(n.pipe.decl[1].ident[0])
			has_key = true
			has_val = true
		}
	}

	// Emit: if len(collection) > 0 { for ... } else { ... }
	has_else := n.else_list != nil

	if has_else {
		emit_indent(e)
		emit_raw(e, fmt.aprintf("if len(%s) > 0 {{\n", collection_expr))
		indent(e)
	}

	// Generate the for loop
	dot_var := val_var
	if !has_val {
		dot_var = fresh_temp(e)
	}

	emit_indent(e)
	if has_key && has_val {
		emit_raw(e, fmt.aprintf("for %s, %s in %s {{\n", dot_var, key_var, collection_expr))
	} else if has_val {
		emit_raw(e, fmt.aprintf("for %s in %s {{\n", dot_var, collection_expr))
	} else {
		emit_raw(e, fmt.aprintf("for %s in %s {{\n", dot_var, collection_expr))
	}
	indent(e)

	// Push new dot context for the range body
	push_dot(g, elem_type, dot_var, elem_ti)
	gen_list(g, n.list)
	pop_dot(g)

	dedent(e)
	emit_line(e, "}")

	if has_else {
		dedent(e)
		emit_line(e, "} else {")
		indent(e)
		gen_list(g, n.else_list)
		dedent(e)
		emit_line(e, "}")
	}
}

// ---------------------------------------------------------------------------
// With generation
// ---------------------------------------------------------------------------

gen_with :: proc(g: ^Gen_Context, n: ^ohtml.With_Node) {
	e := g.emitter

	// Evaluate the with expression
	expr, ti := gen_pipeline_expr(g, n.pipe)

	// For struct types (Named), the value is always "truthy" — just scope the dot.
	// For other types, generate a truthiness check.
	is_struct := ti.kind == .Named

	if !is_struct {
		cond := _gen_truth_expr(g, n.pipe)
		emit_indent(e)
		emit_raw(e, fmt.aprintf("if %s {{\n", cond))
		indent(e)
	}

	// Push new dot context
	new_type := ti.name if ti.kind == .Named else ""
	push_dot(g, new_type, expr, ti)
	gen_list(g, n.list)
	pop_dot(g)

	if !is_struct {
		dedent(e)

		if n.else_list != nil {
			emit_line(e, "} else {")
			indent(e)
			gen_list(g, n.else_list)
			dedent(e)
		}
		emit_line(e, "}")
	}
}

// ---------------------------------------------------------------------------
// Template call generation
// ---------------------------------------------------------------------------

gen_template_call :: proc(g: ^Gen_Context, n: ^ohtml.Template_Node) {
	e := g.emitter

	// Look up the sub-template
	sub_tmpl := ohtml.template_lookup(g.all_tmpls, n.name)
	if sub_tmpl == nil || sub_tmpl.tree == nil || sub_tmpl.tree.root == nil {
		emit_indent(e)
		emit_raw(e, fmt.aprintf("// template %q not found\n", n.name))
		return
	}

	// Determine the data expression for the call
	data_expr := current_dot_expr(g)
	if n.pipe != nil && len(n.pipe.cmds) > 0 {
		data_expr, _ = gen_pipeline_expr(g, n.pipe)
	}

	// Generate an inline expansion of the sub-template (simpler than a separate proc)
	emit_indent(e)
	emit_raw(e, fmt.aprintf("// {{template %q}}\n", n.name))

	// For sub-templates, we inline their content with the current dot
	old_dot_type := current_dot_type(g)
	old_dot_expr := current_dot_expr(g)

	// If data_expr changed, push a new context
	if data_expr != old_dot_expr {
		push_dot(g, old_dot_type, data_expr, current_dot_type_info(g))
		gen_list(g, sub_tmpl.tree.root)
		pop_dot(g)
	} else {
		gen_list(g, sub_tmpl.tree.root)
	}
}

// ---------------------------------------------------------------------------
// Block generation
// ---------------------------------------------------------------------------

gen_block :: proc(g: ^Gen_Context, n: ^ohtml.Block_Node) {
	// A block is like a template call — look up the defined template
	tmpl_node := ohtml.Template_Node {
		pos  = n.pos,
		line = n.line,
		name = n.name,
		pipe = n.pipe,
	}
	gen_template_call(g, &tmpl_node)
}

// ---------------------------------------------------------------------------
// Escaping — write expression with appropriate escape functions
// ---------------------------------------------------------------------------

_write_escaped_expr :: proc(g: ^Gen_Context, expr: string, ti: Type_Info, escapers: []string) {
	e := g.emitter

	// Determine the write strategy based on type
	switch ti.kind {
	case .String:
		if is_safe_type(ti) {
			// Safe types bypass escaping
			emit_indent(e)
			emit_raw(e, fmt.aprintf("io.write_string(w, string(%s))\n", expr))
			return
		}
		_write_string_with_escapers(g, expr, escapers)
	case .Int:
		// Integers never need HTML escaping — unique buffer per call
		buf_name := fmt.aprintf("buf_%d", g.buf_count)
		g.buf_count += 1
		emit_indent(e)
		emit_raw(e, fmt.aprintf("%s: [32]u8\n", buf_name))
		emit_indent(e)
		g.helpers.write_int = true
		emit_raw(e, fmt.aprintf("io.write_string(w, write_int(%s[:], i64(%s)))\n", buf_name, expr))
	case .Uint:
		buf_name := fmt.aprintf("buf_%d", g.buf_count)
		g.buf_count += 1
		emit_indent(e)
		emit_raw(e, fmt.aprintf("%s: [32]u8\n", buf_name))
		emit_indent(e)
		g.helpers.write_uint = true
		emit_raw(
			e,
			fmt.aprintf("io.write_string(w, write_uint(%s[:], u64(%s)))\n", buf_name, expr),
		)
	case .Float:
		g.uses_fmt = true
		emit_indent(e)
		emit_raw(e, fmt.aprintf("fmt.wprintf(w, \"%%v\", %s)\n", expr))
	case .Bool:
		emit_indent(e)
		emit_raw(e, fmt.aprintf("io.write_string(w, \"true\" if %s else \"false\")\n", expr))
	case .Named:
		// Named type — could be a struct, write with field access
		g.uses_fmt = true
		_write_string_with_escapers(g, fmt.aprintf("fmt.aprintf(\"%%v\", %s)", expr), escapers)
	case .Slice, .Array, .Dynamic:
		g.uses_fmt = true
		_write_string_with_escapers(g, fmt.aprintf("fmt.aprintf(\"%%v\", %s)", expr), escapers)
	case .Pointer:
		g.uses_fmt = true
		_write_string_with_escapers(g, fmt.aprintf("fmt.aprintf(\"%%v\", %s)", expr), escapers)
	case .Unknown:
		// Unknown type — use fmt fallback with escaping
		_write_unknown_with_escapers(g, expr, escapers)
	}
}

_write_string_with_escapers :: proc(g: ^Gen_Context, expr: string, escapers: []string) {
	e := g.emitter

	if len(escapers) == 0 {
		emit_indent(e)
		emit_raw(e, fmt.aprintf("io.write_string(w, %s)\n", expr))
		return
	}

	// Build the escape chain from inside out
	result := expr
	for esc in escapers {
		result = _escape_call(g, esc, result)
	}

	emit_indent(e)
	emit_raw(e, fmt.aprintf("io.write_string(w, %s)\n", result))
}

_write_unknown_with_escapers :: proc(g: ^Gen_Context, expr: string, escapers: []string) {
	e := g.emitter

	// For unknown types, use fmt.aprintf to get string representation, then escape
	g.uses_fmt = true
	str_expr := fmt.aprintf("fmt.aprintf(\"%%v\", %s)", expr)
	_write_string_with_escapers(g, str_expr, escapers)
}

// _escape_call maps an escape function name to the corresponding helper call.
_escape_call :: proc(g: ^Gen_Context, esc_name: string, expr: string) -> string {
	switch esc_name {
	case "_html_escaper", "_html_attr_escaper":
		g.helpers.html_escape = true
		return fmt.aprintf("html_escape(%s)", expr)
	case "_html_nospace_escaper":
		g.helpers.html_nospace_escape = true
		return fmt.aprintf("html_nospace_escape(%s)", expr)
	case "_js_val_escaper", "_js_str_escaper", "_js_regexp_escaper":
		g.helpers.js_escape = true
		return fmt.aprintf("js_escape(%s)", expr)
	case "_css_val_filter", "_css_escaper":
		g.helpers.css_escape = true
		return fmt.aprintf("css_escape(%s)", expr)
	case "_url_filter":
		g.helpers.url_filter = true
		return fmt.aprintf("url_filter(%s)", expr)
	case "_url_normalizer":
		g.helpers.url_query_escape = true
		return fmt.aprintf("url_query_escape(%s)", expr)
	case "_srcset_filter":
		g.helpers.html_escape = true
		return fmt.aprintf("html_escape(%s)", expr)
	}
	return expr
}

// ---------------------------------------------------------------------------
// Truth expression generation
// ---------------------------------------------------------------------------

_gen_truth_expr :: proc(g: ^Gen_Context, pipe: ^ohtml.Pipe_Node) -> string {
	expr, ti := gen_pipeline_expr(g, pipe)

	#partial switch ti.kind {
	case .Bool:
		return expr
	case .String:
		return fmt.aprintf("len(%s) > 0", expr)
	case .Int, .Uint:
		return fmt.aprintf("%s != 0", expr)
	case .Float:
		return fmt.aprintf("%s != 0", expr)
	case .Slice, .Array, .Dynamic:
		return fmt.aprintf("len(%s) > 0", expr)
	case .Pointer:
		return fmt.aprintf("%s != nil", expr)
	case .Named:
		return "true"
	}
	// Unknown — most likely an int (range index) or similar; use != 0
	return fmt.aprintf("%s != 0", expr)
}

// ---------------------------------------------------------------------------
// Helper functions
// ---------------------------------------------------------------------------

_get_single_arg :: proc(g: ^Gen_Context, args: []ohtml.Node, pipe_val: string) -> string {
	if len(args) > 0 {
		expr, _ := gen_arg_expr(g, args[0])
		return expr
	}
	if pipe_val != "" {
		return pipe_val
	}
	return "nil"
}

_get_single_arg_with_type :: proc(
	g: ^Gen_Context,
	args: []ohtml.Node,
	pipe_val: string,
) -> (
	string,
	Type_Info,
) {
	if len(args) > 0 {
		return gen_arg_expr(g, args[0])
	}
	if pipe_val != "" {
		return pipe_val, Type_Info{kind = .Unknown}
	}
	return "nil", Type_Info{}
}

_gen_not_expr :: proc(expr: string, ti: Type_Info) -> string {
	#partial switch ti.kind {
	case .Bool:
		return fmt.aprintf("!(%s)", expr)
	case .String:
		return fmt.aprintf("len(%s) == 0", expr)
	case .Int, .Uint:
		return fmt.aprintf("%s == 0", expr)
	case .Float:
		return fmt.aprintf("%s == 0", expr)
	case .Slice, .Array, .Dynamic:
		return fmt.aprintf("len(%s) == 0", expr)
	case .Pointer:
		return fmt.aprintf("%s == nil", expr)
	case .Named:
		return "false"
	}
	return fmt.aprintf("%s == 0", expr)
}

_gen_comparison :: proc(
	g: ^Gen_Context,
	op: string,
	args: []ohtml.Node,
	pipe_val: string,
) -> (
	string,
	Type_Info,
) {
	if len(args) < 2 {
		return "false", Type_Info{kind = .Bool}
	}
	lhs, _ := gen_arg_expr(g, args[0])
	rhs, _ := gen_arg_expr(g, args[1])

	// For multi-arg eq (eq .X "a" "b" "c"), generate (X == "a" || X == "b" || X == "c")
	if op == "==" && len(args) > 2 {
		b := strings.builder_make_len_cap(0, 64)
		strings.write_byte(&b, '(')
		for i in 1 ..< len(args) {
			if i > 1 {
				strings.write_string(&b, " || ")
			}
			arg_expr, _ := gen_arg_expr(g, args[i])
			strings.write_string(&b, lhs)
			strings.write_string(&b, " == ")
			strings.write_string(&b, arg_expr)
		}
		strings.write_byte(&b, ')')
		return strings.to_string(b), Type_Info{kind = .Bool}
	}

	return fmt.aprintf("%s %s %s", lhs, op, rhs), Type_Info{kind = .Bool}
}

_gen_logic_op :: proc(
	g: ^Gen_Context,
	op: string,
	args: []ohtml.Node,
	pipe_val: string,
) -> (
	string,
	Type_Info,
) {
	if len(args) == 0 {
		return "false", Type_Info{kind = .Bool}
	}

	b := strings.builder_make_len_cap(0, 64)
	for arg, i in args {
		if i > 0 {
			strings.write_string(&b, fmt.aprintf(" %s ", op))
		}
		expr := _gen_arg_truth(g, arg)
		strings.write_string(&b, expr)
	}
	return strings.to_string(b), Type_Info{kind = .Bool}
}

_gen_arg_truth :: proc(g: ^Gen_Context, node: ohtml.Node) -> string {
	expr, ti := gen_arg_expr(g, node)
	#partial switch ti.kind {
	case .Bool:
		return expr
	case .String:
		return fmt.aprintf("len(%s) > 0", expr)
	case .Int, .Uint:
		return fmt.aprintf("%s != 0", expr)
	case .Float:
		return fmt.aprintf("%s != 0", expr)
	case .Slice, .Array, .Dynamic:
		return fmt.aprintf("len(%s) > 0", expr)
	case .Pointer:
		return fmt.aprintf("%s != nil", expr)
	case .Named:
		return "true"
	}
	return fmt.aprintf("%s != 0", expr)
}

_gen_print_call :: proc(
	g: ^Gen_Context,
	args: []ohtml.Node,
	pipe_val: string,
	fn_name: string,
) -> (
	string,
	Type_Info,
) {
	g.uses_fmt = true
	b := strings.builder_make_len_cap(0, 64)
	strings.write_string(&b, "fmt.")
	strings.write_string(&b, fn_name)
	strings.write_byte(&b, '(')
	for arg, i in args {
		if i > 0 {
			strings.write_string(&b, ", ")
		}
		expr, _ := gen_arg_expr(g, arg)
		strings.write_string(&b, expr)
	}
	if pipe_val != "" {
		if len(args) > 0 {
			strings.write_string(&b, ", ")
		}
		strings.write_string(&b, pipe_val)
	}
	strings.write_byte(&b, ')')
	return strings.to_string(b), Type_Info{kind = .String}
}

_gen_printf_call :: proc(
	g: ^Gen_Context,
	args: []ohtml.Node,
	pipe_val: string,
) -> (
	string,
	Type_Info,
) {
	if len(args) == 0 {
		return `""`, Type_Info{kind = .String}
	}

	g.uses_fmt = true
	b := strings.builder_make_len_cap(0, 64)
	strings.write_string(&b, "fmt.aprintf(")
	for arg, i in args {
		if i > 0 {
			strings.write_string(&b, ", ")
		}
		expr, _ := gen_arg_expr(g, arg)
		strings.write_string(&b, expr)
	}
	if pipe_val != "" {
		if len(args) > 0 {
			strings.write_string(&b, ", ")
		}
		strings.write_string(&b, pipe_val)
	}
	strings.write_byte(&b, ')')
	return strings.to_string(b), Type_Info{kind = .String}
}

_number_type_info :: proc(n: ^ohtml.Number_Node) -> Type_Info {
	if n.is_int {
		return Type_Info{kind = .Int}
	}
	if n.is_uint {
		return Type_Info{kind = .Uint}
	}
	if n.is_float {
		return Type_Info{kind = .Float}
	}
	return Type_Info{kind = .Int}
}

_odin_var_name :: proc(template_var: string) -> string {
	// Convert template variable $x to Odin variable _v_x
	if len(template_var) > 0 && template_var[0] == '$' {
		return fmt.aprintf("_v_%s", template_var[1:])
	}
	return template_var
}

_odin_type_for :: proc(ti: Type_Info) -> string {
	#partial switch ti.kind {
	case .String:
		return "string"
	case .Bool:
		return "bool"
	case .Int:
		return "int"
	case .Uint:
		return "uint"
	case .Float:
		return "f64"
	case .Named:
		return ti.name
	}
	return "string"
}

_looks_like_collection :: proc(expr: string) -> bool {
	// Heuristic: if it ends with a lowercase plural-ish name, assume collection
	return false
}
