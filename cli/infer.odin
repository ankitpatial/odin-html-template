package cli

import "core:fmt"
import "core:os"
import "core:strings"

import ohtml "../"

// ---------------------------------------------------------------------------
// Type inference — walk template AST and infer struct definitions
// ---------------------------------------------------------------------------

Usage_Context :: enum {
	Text_Output,
	If_Condition,
	Range_Collection,
	With_Value,
	Printf_String,
	Printf_Int,
	Printf_Float,
	Cmp_Int,
	Cmp_Float,
	Cmp_String,
	Len_Arg,
	Index_Arg,
}

Field_Usage :: struct {
	name:     string,
	contexts: [dynamic]Usage_Context,
	children: map[string]^Field_Usage,
	dot_used: bool, // {{.}} used directly inside range body
}

Scope :: struct {
	fields:    map[string]^Field_Usage,
	name_hint: string, // e.g. "Home" for root, "Products" for range element
}

Infer_Context :: struct {
	scope_stack:   [dynamic]^Scope,
	template_name: string,
	all_tmpls:     ^ohtml.Template,
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

// infer_from_template walks the template AST and returns inferred struct
// definitions that can be added to a Type_Registry.
infer_from_template :: proc(
	tmpl: ^ohtml.Template,
	template_name: string,
) -> (
	root_type: string,
	structs: [dynamic]Parsed_Struct,
) {
	ctx: Infer_Context
	ctx.template_name = template_name
	ctx.all_tmpls = tmpl
	ctx.scope_stack = make([dynamic]^Scope)
	defer delete(ctx.scope_stack)

	// Title-case the template name for the root struct
	root_hint := _title_case(template_name)
	root_type = strings.concatenate({root_hint, "Data"})

	// Push root scope
	root_scope := _new_scope(root_hint)
	append(&ctx.scope_stack, root_scope)

	// Walk the main template tree
	if tmpl.tree != nil && tmpl.tree.root != nil {
		_infer_walk_list(&ctx, tmpl.tree.root)
	}

	// Build struct definitions from the collected field usages
	structs = _build_structs(&ctx, root_scope, root_type)

	// Clean up scopes (the field data is consumed by _build_structs)
	_scope_destroy(root_scope)

	return
}

// extract_field_hints scans raw template source for @type_of directives.
// Format (in an HTML comment):
//   <!--
//   @type_of(field_name) type_str
//   -->
extract_field_hints :: proc(src: string) -> map[string]string {
	hints := make(map[string]string)
	MARKER :: "@type_of("
	s := src
	for {
		idx := strings.index(s, MARKER)
		if idx < 0 {
			break
		}
		rest := s[idx + len(MARKER):]
		// Find closing paren
		paren := strings.index(rest, ")")
		if paren < 0 {
			s = rest
			continue
		}
		name := strings.trim_space(rest[:paren])
		after := strings.trim_left_space(rest[paren + 1:])
		// Extract type_str — first non-whitespace token on the rest of the line
		type_fields := strings.fields(after)
		if len(type_fields) >= 1 && len(name) > 0 {
			type_str := type_fields[0]
			hints[name] = type_str
		}
		s = rest[paren + 1:]
	}
	return hints
}

// emit_types_file writes a _types.odin file with all inferred struct definitions.
emit_types_file :: proc(
	dest_dir: string,
	pkg_name: string,
	ohtml_import: string,
	all_structs: []Parsed_Struct,
) -> bool {
	e: Emitter
	emitter_init(&e)
	defer emitter_destroy(&e)

	emit_line(&e, fmt.aprintf("package %s", pkg_name))
	emit_newline(&e)

	for s in all_structs {
		emit_line(&e, fmt.aprintf("%s :: struct {{", s.name))
		indent(&e)
		for f in s.fields {
			emit_line(&e, fmt.aprintf("%s: %s,", f.name, f.type_str))
		}
		dedent(&e)
		emit_line(&e, "}")
		emit_newline(&e)
	}

	output := emitter_to_string(&e)
	path := _join_path(dest_dir, "types_gen.odin")
	ok := os_write_file(path, output)
	if !ok {
		fmt.eprintfln("Error: could not write %s", path)
	}
	return ok
}

// ---------------------------------------------------------------------------
// AST walking — collect field usages
// ---------------------------------------------------------------------------

_current_scope :: proc(ctx: ^Infer_Context) -> ^Scope {
	return ctx.scope_stack[len(ctx.scope_stack) - 1]
}

_push_scope :: proc(ctx: ^Infer_Context, name_hint: string) -> ^Scope {
	s := _new_scope(name_hint)
	append(&ctx.scope_stack, s)
	return s
}

_pop_scope :: proc(ctx: ^Infer_Context) -> ^Scope {
	return pop(&ctx.scope_stack)
}

_infer_walk_list :: proc(ctx: ^Infer_Context, list: ^ohtml.List_Node) {
	if list == nil {
		return
	}
	for node in list.nodes {
		_infer_walk_node(ctx, node)
	}
}

_infer_walk_node :: proc(ctx: ^Infer_Context, node: ohtml.Node) {
	switch n in node {
	case ^ohtml.List_Node:
		_infer_walk_list(ctx, n)
	case ^ohtml.Action_Node:
		_infer_action(ctx, n)
	case ^ohtml.If_Node:
		_infer_if(ctx, n)
	case ^ohtml.Range_Node:
		_infer_range(ctx, n)
	case ^ohtml.With_Node:
		_infer_with(ctx, n)
	case ^ohtml.Template_Node:
		_infer_template_call(ctx, n)
	case ^ohtml.Block_Node:
		_infer_block(ctx, n)
	case ^ohtml.Text_Node,
	     ^ohtml.Comment_Node,
	     ^ohtml.Break_Node,
	     ^ohtml.Continue_Node,
	     ^ohtml.Dot_Node,
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
	// Not walked directly at statement level
	case nil:
	}
}

_infer_action :: proc(ctx: ^Infer_Context, n: ^ohtml.Action_Node) {
	if n.pipe == nil {
		return
	}
	// Check for variable declarations — still record usage from the RHS
	_infer_pipe_fields(ctx, n.pipe, .Text_Output)
}

_infer_if :: proc(ctx: ^Infer_Context, n: ^ohtml.If_Node) {
	// The pipe expression is a condition
	_infer_pipe_fields(ctx, n.pipe, .If_Condition)
	_infer_walk_list(ctx, n.list)
	_infer_walk_list(ctx, n.else_list)
}

_infer_range :: proc(ctx: ^Infer_Context, n: ^ohtml.Range_Node) {
	// The pipe expression is a collection
	field_name := _pipe_field_name(n.pipe)
	if len(field_name) > 0 {
		_record_usage(ctx, field_name, .Range_Collection)
	}

	// Push a child scope for the range body
	hint := _title_case(field_name) if len(field_name) > 0 else "Item"
	child_scope := _push_scope(ctx, hint)

	_infer_walk_list(ctx, n.list)

	_pop_scope(ctx)

	// Attach the child scope's fields to the parent's field usage
	if len(field_name) > 0 {
		parent := _current_scope(ctx)
		fu := _get_or_create_field(parent, field_name)
		// Merge child scope fields into the field's children
		for name, child_fu in child_scope.fields {
			fu.children[name] = child_fu
		}
		// Check if dot was used directly
		fu.dot_used = child_scope.fields[""] != nil || _scope_has_dot_usage(child_scope)
	}

	// Walk else branch in parent scope
	_infer_walk_list(ctx, n.else_list)

	// Don't destroy child scope — its fields are now owned by the parent's Field_Usage.children
	free(child_scope)
}

_infer_with :: proc(ctx: ^Infer_Context, n: ^ohtml.With_Node) {
	field_name := _pipe_field_name(n.pipe)
	if len(field_name) > 0 {
		_record_usage(ctx, field_name, .With_Value)
	}

	// Push a child scope
	hint := _title_case(field_name) if len(field_name) > 0 else "Value"
	child_scope := _push_scope(ctx, hint)

	_infer_walk_list(ctx, n.list)

	_pop_scope(ctx)

	// Attach children
	if len(field_name) > 0 {
		parent := _current_scope(ctx)
		fu := _get_or_create_field(parent, field_name)
		for name, child_fu in child_scope.fields {
			fu.children[name] = child_fu
		}
	}

	_infer_walk_list(ctx, n.else_list)
	free(child_scope)
}

_infer_template_call :: proc(ctx: ^Infer_Context, n: ^ohtml.Template_Node) {
	// Look up sub-template and walk it in the current scope
	sub := ohtml.template_lookup(ctx.all_tmpls, n.name)
	if sub != nil && sub.tree != nil && sub.tree.root != nil {
		_infer_walk_list(ctx, sub.tree.root)
	}
}

_infer_block :: proc(ctx: ^Infer_Context, n: ^ohtml.Block_Node) {
	// Block is like a template call — look up the defined template
	sub := ohtml.template_lookup(ctx.all_tmpls, n.name)
	if sub != nil && sub.tree != nil && sub.tree.root != nil {
		_infer_walk_list(ctx, sub.tree.root)
	}
}

// ---------------------------------------------------------------------------
// Pipeline field extraction — determine what fields are accessed and how
// ---------------------------------------------------------------------------

_infer_pipe_fields :: proc(
	ctx: ^Infer_Context,
	pipe: ^ohtml.Pipe_Node,
	default_ctx: Usage_Context,
) {
	if pipe == nil || len(pipe.cmds) == 0 {
		return
	}

	for cmd in pipe.cmds {
		_infer_cmd_fields(ctx, cmd, default_ctx)
	}
}

_infer_cmd_fields :: proc(
	ctx: ^Infer_Context,
	cmd: ^ohtml.Command_Node,
	default_ctx: Usage_Context,
) {
	if len(cmd.args) == 0 {
		return
	}

	first := cmd.args[0]

	// Check if the first arg is an identifier (function call)
	if ident, ok := first.(^ohtml.Identifier_Node); ok {
		switch ident.ident {
		case "printf":
			_infer_printf(ctx, cmd.args[1:])
			return
		case "print", "println":
			for arg in cmd.args[1:] {
				_record_node_usage(ctx, arg, .Text_Output)
			}
			return
		case "eq", "ne":
			_infer_comparison(ctx, cmd.args[1:])
			return
		case "lt", "le", "gt", "ge":
			_infer_comparison(ctx, cmd.args[1:])
			return
		case "len":
			for arg in cmd.args[1:] {
				_record_node_usage(ctx, arg, .Len_Arg)
			}
			return
		case "index":
			if len(cmd.args) > 1 {
				_record_node_usage(ctx, cmd.args[1], .Index_Arg)
			}
			return
		case "not", "and", "or":
			for arg in cmd.args[1:] {
				_record_node_usage(ctx, arg, .If_Condition)
			}
			return
		case "html", "js", "urlquery":
			for arg in cmd.args[1:] {
				_record_node_usage(ctx, arg, .Text_Output)
			}
			return
		}
		// Escape functions starting with '_' — skip them, record args
		if len(ident.ident) > 0 && ident.ident[0] == '_' {
			return
		}
	}

	// Not a function call — record field/dot accesses with default context
	for arg in cmd.args {
		_record_node_usage(ctx, arg, default_ctx)
	}
}

_infer_printf :: proc(ctx: ^Infer_Context, args: []ohtml.Node) {
	if len(args) == 0 {
		return
	}

	// First arg should be the format string
	fmt_str := ""
	if str, ok := args[0].(^ohtml.String_Node); ok {
		fmt_str = str.text
	}

	if len(fmt_str) == 0 {
		// No format string — record everything as text
		for arg in args {
			_record_node_usage(ctx, arg, .Text_Output)
		}
		return
	}

	// Parse format verbs and match to subsequent args
	verbs := _parse_format_verbs(fmt_str)
	defer delete(verbs)

	arg_idx := 1 // skip format string
	for verb in verbs {
		if arg_idx >= len(args) {
			break
		}
		uctx: Usage_Context
		switch verb {
		case 'd', 'x', 'X', 'o', 'b':
			uctx = .Printf_Int
		case 'f', 'e', 'E', 'g', 'G':
			uctx = .Printf_Float
		case 's', 'q':
			uctx = .Printf_String
		case 'v':
			uctx = .Text_Output
		case:
			uctx = .Text_Output
		}
		_record_node_usage(ctx, args[arg_idx], uctx)
		arg_idx += 1
	}

	// Any remaining args
	for i in arg_idx ..< len(args) {
		_record_node_usage(ctx, args[i], .Text_Output)
	}
}

_parse_format_verbs :: proc(fmt_str: string) -> [dynamic]u8 {
	verbs := make([dynamic]u8)
	i := 0
	for i < len(fmt_str) {
		if fmt_str[i] == '%' {
			i += 1
			// Skip flags: -, +, #, 0, space
			for i < len(fmt_str) && _is_fmt_flag(fmt_str[i]) {
				i += 1
			}
			// Skip width
			for i < len(fmt_str) && fmt_str[i] >= '0' && fmt_str[i] <= '9' {
				i += 1
			}
			// Skip precision
			if i < len(fmt_str) && fmt_str[i] == '.' {
				i += 1
				for i < len(fmt_str) && fmt_str[i] >= '0' && fmt_str[i] <= '9' {
					i += 1
				}
			}
			// The verb
			if i < len(fmt_str) {
				if fmt_str[i] != '%' { 	// %% is literal
					append(&verbs, fmt_str[i])
				}
				i += 1
			}
		} else {
			i += 1
		}
	}
	return verbs
}

_is_fmt_flag :: proc(ch: u8) -> bool {
	return ch == '-' || ch == '+' || ch == '#' || ch == '0' || ch == ' '
}

_infer_comparison :: proc(ctx: ^Infer_Context, args: []ohtml.Node) {
	// In Go template's eq/lt/gt etc, first arg is compared to subsequent ones.
	// If any arg is a literal, we can infer the type of the field args.
	literal_ctx := _detect_literal_type(args)

	for arg in args {
		_record_node_usage(ctx, arg, literal_ctx)
	}
}

_detect_literal_type :: proc(args: []ohtml.Node) -> Usage_Context {
	for arg in args {
		if num, ok := arg.(^ohtml.Number_Node); ok {
			// The parser sets is_int=true AND is_float=true for integers like 42.
			// Use the original text to distinguish: "10.0" has a dot → float, "42" doesn't → int.
			if _text_looks_float(num.text) {
				return .Cmp_Float
			}
			return .Cmp_Int
		}
		if _, ok := arg.(^ohtml.String_Node); ok {
			return .Cmp_String
		}
	}
	return .If_Condition // no literal — can't infer
}

_text_looks_float :: proc(text: string) -> bool {
	for ch in text {
		if ch == '.' || ch == 'e' || ch == 'E' {
			return true
		}
	}
	return false
}

// ---------------------------------------------------------------------------
// Recording field usages
// ---------------------------------------------------------------------------

_record_node_usage :: proc(ctx: ^Infer_Context, node: ohtml.Node, uctx: Usage_Context) {
	#partial switch n in node {
	case ^ohtml.Field_Node:
		if len(n.ident) > 0 {
			_record_usage(ctx, n.ident[0], uctx)
		}
	case ^ohtml.Dot_Node:
		// Dot used directly — mark in current scope
		scope := _current_scope(ctx)
		scope.fields[""] = nil // sentinel for dot_used
	case ^ohtml.Variable_Node:
		// $var — can't infer struct field from this
		return
	case ^ohtml.Pipe_Node:
		_infer_pipe_fields(ctx, n, uctx)
	}
}

_record_usage :: proc(ctx: ^Infer_Context, field_name: string, uctx: Usage_Context) {
	scope := _current_scope(ctx)
	fu := _get_or_create_field(scope, field_name)
	append(&fu.contexts, uctx)
}

// ---------------------------------------------------------------------------
// Scope and field helpers
// ---------------------------------------------------------------------------

_new_scope :: proc(name_hint: string) -> ^Scope {
	s := new(Scope)
	s.fields = make(map[string]^Field_Usage)
	s.name_hint = name_hint
	return s
}

_scope_destroy :: proc(s: ^Scope) {
	for _, fu in s.fields {
		_field_usage_destroy(fu)
	}
	delete(s.fields)
	free(s)
}

_field_usage_destroy :: proc(fu: ^Field_Usage) {
	if fu == nil {
		return
	}
	delete(fu.contexts)
	for _, child in fu.children {
		_field_usage_destroy(child)
	}
	delete(fu.children)
	free(fu)
}

_get_or_create_field :: proc(scope: ^Scope, name: string) -> ^Field_Usage {
	if fu, ok := scope.fields[name]; ok && fu != nil {
		return fu
	}
	fu := new(Field_Usage)
	fu.name = name
	fu.children = make(map[string]^Field_Usage)
	fu.contexts = make([dynamic]Usage_Context)
	scope.fields[name] = fu
	return fu
}

_scope_has_dot_usage :: proc(scope: ^Scope) -> bool {
	_, has_empty := scope.fields[""]
	return has_empty
}

_pipe_field_name :: proc(pipe: ^ohtml.Pipe_Node) -> string {
	if pipe == nil || len(pipe.cmds) == 0 {
		return ""
	}
	cmd := pipe.cmds[0]
	if len(cmd.args) == 0 {
		return ""
	}
	if field, ok := cmd.args[0].(^ohtml.Field_Node); ok {
		if len(field.ident) > 0 {
			return field.ident[0]
		}
	}
	return ""
}

// ---------------------------------------------------------------------------
// Building struct definitions from collected field usages
// ---------------------------------------------------------------------------

_build_structs :: proc(
	ctx: ^Infer_Context,
	root_scope: ^Scope,
	root_name: string,
) -> [dynamic]Parsed_Struct {
	all_structs := make([dynamic]Parsed_Struct)
	_build_struct_from_scope(ctx, root_scope, root_name, &all_structs)
	return all_structs
}

_build_struct_from_scope :: proc(
	ctx: ^Infer_Context,
	scope: ^Scope,
	struct_name: string,
	out: ^[dynamic]Parsed_Struct,
) {
	ps := Parsed_Struct {
		name   = struct_name,
		fields = make([dynamic]Parsed_Field),
	}

	for name, fu in scope.fields {
		if len(name) == 0 || fu == nil {
			continue // skip dot sentinel
		}

		type_str := _resolve_field_type_str(ctx, fu, struct_name, name, out)
		append(&ps.fields, Parsed_Field{name = name, type_str = type_str})
	}

	append(out, ps)
}

_resolve_field_type_str :: proc(
	ctx: ^Infer_Context,
	fu: ^Field_Usage,
	parent_struct: string,
	field_name: string,
	out: ^[dynamic]Parsed_Struct,
) -> string {
	has_range := false
	has_with := false
	has_if_only := true // true until we see a non-if context
	has_len := false
	has_index := false

	best_type := "string" // default

	for uctx in fu.contexts {
		switch uctx {
		case .Printf_Int, .Cmp_Int:
			return "int" // highest priority
		case .Printf_Float, .Cmp_Float:
			return "f64"
		case .Printf_String, .Cmp_String:
			best_type = "string"
			has_if_only = false
		case .Range_Collection:
			has_range = true
			has_if_only = false
		case .With_Value:
			has_with = true
			has_if_only = false
		case .Len_Arg:
			has_len = true
			has_if_only = false
		case .Index_Arg:
			has_index = true
			has_if_only = false
		case .Text_Output:
			has_if_only = false
		case .If_Condition:
		// Keep has_if_only as-is
		}
	}

	// index implies collection; len alone doesn't (len works on strings too)
	if has_index {
		has_range = true
	}

	// Has children → struct (from range or with)
	// Count only real children (non-empty keys with non-nil values)
	real_child_count := 0
	for name, child in fu.children {
		if len(name) > 0 && child != nil {
			real_child_count += 1
		}
	}
	has_children := real_child_count > 0

	if has_range {
		if has_children {
			// Generate a named element struct
			elem_name := fmt.aprintf(
				"%s%sItem",
				_strip_data_suffix(parent_struct),
				_title_case(field_name),
			)
			_build_child_struct(ctx, fu, elem_name, out)
			return fmt.aprintf("[]%s", elem_name)
		}
		// Range with dot used directly or no children → []string
		return "[]string"
	}

	if has_with && has_children {
		elem_name := fmt.aprintf(
			"%s%sItem",
			_strip_data_suffix(parent_struct),
			_title_case(field_name),
		)
		_build_child_struct(ctx, fu, elem_name, out)
		return elem_name
	}

	// If only used in if conditions and nowhere else → bool
	if has_if_only && len(fu.contexts) > 0 {
		return "bool"
	}

	return best_type
}

_build_child_struct :: proc(
	ctx: ^Infer_Context,
	fu: ^Field_Usage,
	struct_name: string,
	out: ^[dynamic]Parsed_Struct,
) {
	child_scope := _new_scope("")
	child_scope.fields = fu.children
	_build_struct_from_scope(ctx, child_scope, struct_name, out)
	// Don't destroy child_scope — it doesn't own the fields (fu owns them)
	free(child_scope)
}

// ---------------------------------------------------------------------------
// String helpers
// ---------------------------------------------------------------------------

_title_case :: proc(s: string) -> string {
	if len(s) == 0 {
		return ""
	}
	b := strings.builder_make_len_cap(0, len(s))
	capitalize_next := true
	for ch in s {
		if ch == '_' || ch == '-' || ch == '/' || ch == '\\' || ch == '.' {
			capitalize_next = true
		} else if capitalize_next {
			if ch >= 'a' && ch <= 'z' {
				strings.write_byte(&b, u8(ch) - 32)
			} else {
				strings.write_byte(&b, u8(ch))
			}
			capitalize_next = false
		} else {
			strings.write_byte(&b, u8(ch))
			capitalize_next = false
		}
	}
	return strings.to_string(b)
}

_strip_data_suffix :: proc(name: string) -> string {
	if strings.has_suffix(name, "Data") {
		return name[:len(name) - 4]
	}
	return name
}

// os_write_file writes string content to a file path.
os_write_file :: proc(path: string, content: string) -> bool {
	return os.write_entire_file(path, transmute([]u8)content)
}
