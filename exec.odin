package ohtml

import "base:runtime"
import "core:fmt"
import "core:io"
import "core:reflect"
import "core:strings"

// ---------------------------------------------------------------------------
// Execution state
// ---------------------------------------------------------------------------

MAX_EXEC_DEPTH :: 1_000

Exec_Variable :: struct {
	name:  string,
	value: any,
}

Exec_State :: struct {
	tmpl:        ^Template,
	wr:          io.Writer,
	node:        Node, // current node for error reporting
	vars:        [dynamic]Exec_Variable,
	depth:       int,
	range_depth: int,
}

// ---------------------------------------------------------------------------
// Variable stack
// ---------------------------------------------------------------------------

exec_push :: proc(s: ^Exec_State, name: string, value: any) {
	append(&s.vars, Exec_Variable{name, value})
}

exec_mark :: proc(s: ^Exec_State) -> int {
	return len(s.vars)
}

exec_pop :: proc(s: ^Exec_State, mark: int) {
	resize(&s.vars, mark)
}

exec_set_var :: proc(s: ^Exec_State, name: string, value: any) {
	#reverse for &v in s.vars {
		if v.name == name {
			v.value = value
			return
		}
	}
}

exec_set_top_var :: proc(s: ^Exec_State, n: int, value: any) {
	idx := len(s.vars) - n
	if idx >= 0 && idx < len(s.vars) {
		s.vars[idx].value = value
	}
}

exec_var_value :: proc(s: ^Exec_State, name: string) -> (any, Error) {
	#reverse for v in s.vars {
		if v.name == name {
			return v.value, {}
		}
	}
	return nil, exec_error(s, .Undefined_Variable, "undefined variable: %s", name)
}

// ---------------------------------------------------------------------------
// Error helpers
// ---------------------------------------------------------------------------

exec_error :: proc(s: ^Exec_State, kind: Error_Kind, format: string, args: ..any) -> Error {
	msg := fmt.aprintf(format, ..args)
	name := s.tmpl != nil ? s.tmpl.name : ""
	return Error{kind = kind, msg = msg, name = name}
}

// ---------------------------------------------------------------------------
// Walk — dispatch on node type
// ---------------------------------------------------------------------------

walk :: proc(s: ^Exec_State, dot: any, node: Node) -> Error {
	s.node = node

	switch n in node {
	case ^List_Node:
		for child in n.nodes {
			err := walk(s, dot, child)
			if err.kind != .None {
				return err
			}
		}
	case ^Text_Node:
		_, werr := io.write(s.wr, n.text)
		if werr != nil {
			return exec_error(s, .Write_Error, "write error")
		}
	case ^Action_Node:
		val, err := eval_pipeline(s, dot, n.pipe)
		if err.kind != .None {
			return err
		}
		// If the pipeline has no declarations, print the result.
		if n.pipe != nil && len(n.pipe.decl) == 0 {
			perr := print_value(s.wr, val)
			if perr != nil {
				return exec_error(s, .Write_Error, "write error")
			}
		}
	case ^If_Node:
		return walk_if_or_with(s, dot, n.pipe, n.list, n.else_list, false)
	case ^With_Node:
		return walk_if_or_with(s, dot, n.pipe, n.list, n.else_list, true)
	case ^Range_Node:
		return walk_range(s, dot, n)
	case ^Template_Node:
		return walk_template(s, dot, n)
	case ^Block_Node:
		return walk_template(
			s,
			dot,
			&Template_Node{pos = n.pos, line = n.line, name = n.name, pipe = n.pipe},
		)
	case ^Comment_Node:
	// Comments are no-ops.
	case ^Break_Node:
		return Error{kind = .Break_Signal}
	case ^Continue_Node:
		return Error{kind = .Continue_Signal}
	case ^Dot_Node,
	     ^Nil_Node,
	     ^Bool_Node,
	     ^Number_Node,
	     ^String_Node,
	     ^Field_Node,
	     ^Variable_Node,
	     ^Identifier_Node,
	     ^Chain_Node,
	     ^Pipe_Node,
	     ^Command_Node:
		return exec_error(s, .Execution_Failed, "unexpected node type in walk")
	case nil:
	// nil node — skip.
	}
	return {}
}

// ---------------------------------------------------------------------------
// If / With
// ---------------------------------------------------------------------------

walk_if_or_with :: proc(
	s: ^Exec_State,
	dot: any,
	pipe: ^Pipe_Node,
	list: ^List_Node,
	else_list: ^List_Node,
	is_with: bool,
) -> Error {
	val, err := eval_pipeline(s, dot, pipe)
	if err.kind != .None {
		return err
	}
	truth, _ := is_true(val)
	if truth {
		if is_with {
			return walk(s, val, list)
		}
		return walk(s, dot, list)
	} else if else_list != nil {
		return walk(s, dot, else_list)
	}
	return {}
}

// ---------------------------------------------------------------------------
// Range
// ---------------------------------------------------------------------------

walk_range :: proc(s: ^Exec_State, dot: any, r: ^Range_Node) -> Error {
	val, err := eval_pipeline(s, dot, r.pipe)
	if err.kind != .None {
		return err
	}

	mark := exec_mark(s)
	defer exec_pop(s, mark)

	// Push placeholder variables for range declarations.
	if r.pipe != nil {
		for v in r.pipe.decl {
			exec_push(s, v.ident[0], nil)
		}
	}

	val_deref, is_nil := indirect(val)
	if is_nil || val_deref == nil {
		if r.else_list != nil {
			return walk(s, dot, r.else_list)
		}
		return {}
	}

	ti := reflect.type_info_base(type_info_of(val_deref.id))
	ran := false

	#partial switch info in ti.variant {
	case runtime.Type_Info_Array, runtime.Type_Info_Slice, runtime.Type_Info_Dynamic_Array:
		n := reflect.length(val_deref)
		if n == 0 {
			if r.else_list != nil {
				return walk(s, dot, r.else_list)
			}
			return {}
		}
		for i in 0 ..< n {
			elem := reflect.index(val_deref, i)
			rerr := _range_one_iteration(s, r, i, elem, mark)
			if rerr.kind == .Break_Signal {
				break
			}
			if rerr.kind != .None && rerr.kind != .Continue_Signal {
				return rerr
			}
		}
		ran = true

	case runtime.Type_Info_Map:
		it: int
		count := 0
		for {
			k, v, ok := reflect.iterate_map(val_deref, &it)
			if !ok {
				break
			}
			rerr := _range_one_iteration(s, r, k, v, mark)
			if rerr.kind == .Break_Signal {
				break
			}
			if rerr.kind != .None && rerr.kind != .Continue_Signal {
				return rerr
			}
			count += 1
		}
		ran = count > 0

	case runtime.Type_Info_String:
		str := _read_string(val_deref)
		if len(str) == 0 {
			if r.else_list != nil {
				return walk(s, dot, r.else_list)
			}
			return {}
		}
		i := 0
		for ch in str {
			rerr := _range_one_iteration(s, r, i, ch, mark)
			if rerr.kind == .Break_Signal {
				break
			}
			if rerr.kind != .None && rerr.kind != .Continue_Signal {
				return rerr
			}
			i += 1
		}
		ran = true

	case runtime.Type_Info_Integer:
		// Range over integer (Go 1.22+).
		n: int
		if info.signed {
			n = int(_read_int(val_deref.data, ti.size))
		} else {
			n = int(_read_uint(val_deref.data, ti.size))
		}
		for i in 0 ..< n {
			rerr := _range_one_iteration(s, r, i, i, mark)
			if rerr.kind == .Break_Signal {
				break
			}
			if rerr.kind != .None && rerr.kind != .Continue_Signal {
				return rerr
			}
		}
		ran = n > 0

	case:
		return exec_error(s, .Not_Iterable, "range can't iterate over %v", val_deref)
	}

	if !ran && r.else_list != nil {
		return walk(s, dot, r.else_list)
	}
	return {}
}

@(private = "package")
_range_one_iteration :: proc(
	s: ^Exec_State,
	r: ^Range_Node,
	index: any,
	elem: any,
	mark: int,
) -> Error {
	// Set range variables.
	if r.pipe != nil {
		ndecl := len(r.pipe.decl)
		if ndecl > 0 {
			if r.pipe.is_assign {
				if ndecl > 1 {
					// $k, $v := range ...
					exec_set_var(s, _var_name(r.pipe.decl[0]), index)
					exec_set_var(s, _var_name(r.pipe.decl[1]), elem)
				} else {
					exec_set_var(s, _var_name(r.pipe.decl[0]), elem)
				}
			} else {
				// $v := range ... (non-assign uses top-of-stack)
				exec_set_top_var(s, 1, elem)
				if ndecl > 1 {
					exec_set_top_var(s, 2, index)
				}
			}
		}
	}

	inner_mark := exec_mark(s)
	defer exec_pop(s, inner_mark)

	return walk(s, elem, r.list)
}

// ---------------------------------------------------------------------------
// Template call
// ---------------------------------------------------------------------------

walk_template :: proc(s: ^Exec_State, dot: any, t: ^Template_Node) -> Error {
	s.depth += 1
	defer {s.depth -= 1}
	if s.depth > MAX_EXEC_DEPTH {
		return exec_error(s, .Max_Depth_Exceeded, "max template depth exceeded")
	}

	// Look up the template by name.
	tmpl := template_lookup(s.tmpl, t.name)
	if tmpl == nil {
		return exec_error(s, .Undefined_Template, "template %q not defined", t.name)
	}

	// Evaluate the data pipeline if present.
	data := dot
	if t.pipe != nil {
		val, err := eval_pipeline(s, dot, t.pipe)
		if err.kind != .None {
			return err
		}
		data = val
	}

	// Execute the called template with a fresh variable scope.
	new_state := Exec_State {
		tmpl  = tmpl,
		wr    = s.wr,
		depth = s.depth,
	}
	exec_push(&new_state, "$", data)
	defer delete(new_state.vars)

	if tmpl.tree == nil || tmpl.tree.root == nil {
		return {}
	}
	return walk(&new_state, data, tmpl.tree.root)
}

// ---------------------------------------------------------------------------
// Pipeline evaluation
// ---------------------------------------------------------------------------

eval_pipeline :: proc(s: ^Exec_State, dot: any, pipe: ^Pipe_Node) -> (any, Error) {
	if pipe == nil {
		return nil, {}
	}

	value: any
	for cmd in pipe.cmds {
		val, err := eval_command(s, dot, cmd, value)
		if err.kind != .None {
			return nil, err
		}
		value = val
	}

	// Assign to declared variables.
	for v in pipe.decl {
		if pipe.is_assign {
			exec_set_var(s, v.ident[0], value)
		} else {
			exec_push(s, v.ident[0], value)
		}
	}

	return value, {}
}

// ---------------------------------------------------------------------------
// Command evaluation
// ---------------------------------------------------------------------------

eval_command :: proc(s: ^Exec_State, dot: any, cmd: ^Command_Node, final: any) -> (any, Error) {
	if len(cmd.args) == 0 {
		return nil, exec_error(s, .Empty_Command, "empty command")
	}

	first := cmd.args[0]

	#partial switch n in first {
	case ^Field_Node:
		return eval_field_node(s, dot, n, cmd.args[:], final)
	case ^Chain_Node:
		return eval_chain_node(s, dot, n, cmd.args[:], final)
	case ^Identifier_Node:
		return eval_function(s, dot, n.ident, cmd.args[:], final)
	case ^Pipe_Node:
		return eval_pipeline(s, dot, n)
	case ^Variable_Node:
		return eval_variable_node(s, dot, n, cmd.args[:], final)
	case ^Dot_Node:
		return dot, {}
	case ^Nil_Node:
		return nil, exec_error(s, .Execution_Failed, "nil is not a command")
	case ^Bool_Node:
		return n.val, {}
	case ^Number_Node:
		return _number_value(n), {}
	case ^String_Node:
		return n.text, {}
	}
	return nil, exec_error(s, .Execution_Failed, "can't evaluate command")
}

// ---------------------------------------------------------------------------
// Field evaluation — .Field or .Field.Sub.Chain
// ---------------------------------------------------------------------------

eval_field_node :: proc(
	s: ^Exec_State,
	dot: any,
	field: ^Field_Node,
	args: []Node,
	final: any,
) -> (
	any,
	Error,
) {
	return eval_field_chain(s, dot, dot, field.ident, args, final)
}

eval_field_chain :: proc(
	s: ^Exec_State,
	dot: any,
	receiver: any,
	ident: []string,
	args: []Node,
	final: any,
) -> (
	any,
	Error,
) {
	n := len(ident)
	r := receiver
	for i in 0 ..< n - 1 {
		val, err := eval_field(s, dot, ident[i], r)
		if err.kind != .None {
			return nil, err
		}
		r = val
	}
	// Last field may have args (function call) or final (piped value).
	if n > 0 {
		return eval_field_with_args(s, dot, ident[n - 1], r, args, final)
	}
	return r, {}
}

// eval_field accesses a struct field or map key by name.
eval_field :: proc(s: ^Exec_State, dot: any, name: string, receiver: any) -> (any, Error) {
	val, is_nil := indirect(receiver)
	if is_nil || val == nil {
		return nil, exec_error(s, .Nil_Pointer, "nil pointer evaluating .%s", name)
	}

	ti := reflect.type_info_base(type_info_of(val.id))
	#partial switch info in ti.variant {
	case runtime.Type_Info_Struct:
		field_val := reflect.struct_field_value_by_name(val, name, allow_using = true)
		if field_val != nil {
			return field_val, {}
		}
	case runtime.Type_Info_Map:
		// Look up name as string key.
		result := _map_index_by_name(val, name)
		return result, {}
	}

	return nil, exec_error(s, .Cant_Index, "can't evaluate field %q in type %v", name, val.id)
}

// eval_field_with_args is like eval_field but supports piped final values.
// For now, struct fields with extra args are an error (Odin has no methods on structs).
eval_field_with_args :: proc(
	s: ^Exec_State,
	dot: any,
	name: string,
	receiver: any,
	args: []Node,
	final: any,
) -> (
	any,
	Error,
) {
	// If there are extra args or a piped final, it's an error for plain fields.
	has_args := len(args) > 1 || final != nil
	val, err := eval_field(s, dot, name, receiver)
	if err.kind != .None {
		return nil, err
	}
	if has_args {
		// Check if the field value is a function.
		fn, ok := val.(Template_Func)
		if ok {
			return eval_call(s, dot, fn, args, final)
		}
		return nil, exec_error(s, .Not_A_Function, "%s has arguments but is not a function", name)
	}
	return val, {}
}

// ---------------------------------------------------------------------------
// Chain evaluation — (expr).Field.Sub
// ---------------------------------------------------------------------------

eval_chain_node :: proc(
	s: ^Exec_State,
	dot: any,
	chain: ^Chain_Node,
	args: []Node,
	final: any,
) -> (
	any,
	Error,
) {
	// Evaluate the base expression of the chain.
	val, err := eval_arg(s, dot, chain.node)
	if err.kind != .None {
		return nil, err
	}
	return eval_field_chain(s, dot, val, chain.field[:], args, final)
}

// ---------------------------------------------------------------------------
// Variable evaluation
// ---------------------------------------------------------------------------

eval_variable_node :: proc(
	s: ^Exec_State,
	dot: any,
	v: ^Variable_Node,
	args: []Node,
	final: any,
) -> (
	any,
	Error,
) {
	value, err := exec_var_value(s, v.ident[0])
	if err.kind != .None {
		return nil, err
	}
	if len(v.ident) == 1 {
		return value, {}
	}
	return eval_field_chain(s, dot, value, v.ident[1:], args, final)
}

// ---------------------------------------------------------------------------
// Function evaluation
// ---------------------------------------------------------------------------

eval_function :: proc(
	s: ^Exec_State,
	dot: any,
	name: string,
	args: []Node,
	final: any,
) -> (
	any,
	Error,
) {
	// Look up in template's func map first, then builtins.
	fn: Template_Func
	found := false

	if s.tmpl != nil && s.tmpl.common != nil {
		for fm in s.tmpl.common.func_maps {
			if f, ok := fm[name]; ok {
				fn = f
				found = true
				break
			}
		}
	}

	if !found {
		f, ok := find_builtin(name)
		if ok {
			fn = f
			found = true
		}
	}

	if !found {
		return nil, exec_error(s, .Undefined_Function, "function %q not defined", name)
	}

	return eval_call(s, dot, fn, args, final)
}

// eval_call evaluates a function call with arguments.
eval_call :: proc(
	s: ^Exec_State,
	dot: any,
	fn: Template_Func,
	args: []Node,
	final: any,
) -> (
	any,
	Error,
) {
	// Build the argument list: skip first arg (it's the function name node),
	// evaluate the rest, then append final (piped value) if present.
	// Use a small stack buffer for the common case (most calls have <= 8 args).
	arg_start := 1 if len(args) > 0 else 0
	n_args := len(args) - arg_start + (1 if final != nil else 0)

	buf: [8]any
	call_args: []any
	dyn_args: [dynamic]any
	if n_args <= len(buf) {
		idx := 0
		for i in arg_start ..< len(args) {
			val, err := eval_arg(s, dot, args[i])
			if err.kind != .None {
				return nil, err
			}
			buf[idx] = val
			idx += 1
		}
		if final != nil {
			buf[idx] = final
			idx += 1
		}
		call_args = buf[:idx]
	} else {
		for i in arg_start ..< len(args) {
			val, err := eval_arg(s, dot, args[i])
			if err.kind != .None {
				delete(dyn_args)
				return nil, err
			}
			append(&dyn_args, val)
		}
		if final != nil {
			append(&dyn_args, final)
		}
		call_args = dyn_args[:]
		defer delete(dyn_args)
	}

	result, fn_err := fn(call_args)
	if fn_err.kind != .None {
		return nil, fn_err
	}
	return result, {}
}

// eval_arg evaluates a single argument node to a value.
eval_arg :: proc(s: ^Exec_State, dot: any, node: Node) -> (any, Error) {
	#partial switch n in node {
	case ^Dot_Node:
		return dot, {}
	case ^Nil_Node:
		return nil, {}
	case ^Bool_Node:
		return n.val, {}
	case ^Number_Node:
		return _number_value(n), {}
	case ^String_Node:
		return n.text, {}
	case ^Field_Node:
		return eval_field_chain(s, dot, dot, n.ident, nil, nil)
	case ^Variable_Node:
		return eval_variable_node(s, dot, n, nil, nil)
	case ^Pipe_Node:
		return eval_pipeline(s, dot, n)
	case ^Identifier_Node:
		return eval_function(s, dot, n.ident, nil, nil)
	case ^Chain_Node:
		return eval_chain_node(s, dot, n, nil, nil)
	}
	return nil, exec_error(s, .Execution_Failed, "can't evaluate argument")
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

@(private = "package")
_number_value :: proc(n: ^Number_Node) -> any {
	if n.is_int {
		return box_i64(n.int_val)
	}
	if n.is_uint {
		p := new(u64)
		p^ = n.uint_val
		return p^
	}
	if n.is_float {
		return box_f64(n.float_val)
	}
	return box_int(0)
}

@(private = "package")
_var_name :: proc(v: ^Variable_Node) -> string {
	if v == nil {
		return ""
	}
	return v.ident[0]
}

// _map_index_by_name looks up a string key in a map using reflect iteration.
@(private = "package")
_map_index_by_name :: proc(m: any, name: string) -> any {
	it: int
	for {
		k, v, ok := reflect.iterate_map(m, &it)
		if !ok {
			break
		}
		// Compare the key as a string.
		key_str := _read_string(k)
		if key_str == name {
			return v
		}
	}
	return nil
}
