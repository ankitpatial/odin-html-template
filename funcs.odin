package ohtml

import "base:runtime"
import "core:fmt"
import "core:reflect"
import "core:strings"

// ---------------------------------------------------------------------------
// Template_Func type and Func_Map — already declared in parse.odin
// Template_Func :: #type proc(args: []any) -> (any, Error)
// Func_Map :: map[string]Template_Func
// ---------------------------------------------------------------------------

// find_builtin looks up a built-in function by name without allocating.
find_builtin :: proc(name: string) -> (Template_Func, bool) {
	switch name {
	case "and":
		return _fn_and, true
	case "or":
		return _fn_or, true
	case "not":
		return _fn_not, true
	case "eq":
		return _fn_eq, true
	case "ne":
		return _fn_ne, true
	case "lt":
		return _fn_lt, true
	case "le":
		return _fn_le, true
	case "gt":
		return _fn_gt, true
	case "ge":
		return _fn_ge, true
	case "print":
		return _fn_print, true
	case "printf":
		return _fn_printf, true
	case "println":
		return _fn_println, true
	case "len":
		return _fn_len, true
	case "index":
		return _fn_index, true
	case "call":
		return _fn_call, true
	case "html":
		return _fn_html_escape, true
	case "js":
		return _fn_js_escape, true
	case "urlquery":
		return _fn_urlquery, true
	}
	return nil, false
}

// ---------------------------------------------------------------------------
// Boolean logic
// ---------------------------------------------------------------------------

// and returns the first false argument, or the last argument.
// In Go templates: {{and .X .Y}} = if .X then .Y else .X
_fn_and :: proc(args: []any) -> (any, Error) {
	if len(args) == 0 {
		return nil, Error{kind = .Wrong_Arg_Count, msg = "and requires at least 1 argument"}
	}
	result: any
	for arg in args {
		truth, _ := is_true(arg)
		result = arg
		if !truth {
			break
		}
	}
	return result, {}
}

// or returns the first true argument, or the last argument.
// In Go templates: {{or .X .Y}} = if .X then .X else .Y
_fn_or :: proc(args: []any) -> (any, Error) {
	if len(args) == 0 {
		return nil, Error{kind = .Wrong_Arg_Count, msg = "or requires at least 1 argument"}
	}
	result: any
	for arg in args {
		truth, _ := is_true(arg)
		result = arg
		if truth {
			break
		}
	}
	return result, {}
}

// not returns the boolean negation of its argument.
_fn_not :: proc(args: []any) -> (any, Error) {
	if len(args) != 1 {
		return nil, Error{kind = .Wrong_Arg_Count, msg = "not requires exactly 1 argument"}
	}
	truth, _ := is_true(args[0])
	return box_bool(!truth), {}
}

// ---------------------------------------------------------------------------
// Comparison functions
// ---------------------------------------------------------------------------

_fn_eq :: proc(args: []any) -> (any, Error) {
	if len(args) < 2 {
		return nil, Error{kind = .No_Comparison, msg = "eq requires at least 2 arguments"}
	}
	for arg in args[1:] {
		result, err := compare_eq(args[0], arg)
		if err.kind != .None {
			return nil, err
		}
		if result {
			return box_bool(true), {}
		}
	}
	return box_bool(false), {}
}

_fn_ne :: proc(args: []any) -> (any, Error) {
	if len(args) != 2 {
		return nil, Error{kind = .No_Comparison, msg = "ne requires exactly 2 arguments"}
	}
	result, err := compare_eq(args[0], args[1])
	if err.kind != .None {
		return nil, err
	}
	return box_bool(!result), {}
}

_fn_lt :: proc(args: []any) -> (any, Error) {
	if len(args) != 2 {
		return nil, Error{kind = .No_Comparison, msg = "lt requires exactly 2 arguments"}
	}
	result, err := compare_lt(args[0], args[1])
	if err.kind != .None {
		return nil, err
	}
	return box_bool(result), {}
}

_fn_le :: proc(args: []any) -> (any, Error) {
	if len(args) != 2 {
		return nil, Error{kind = .No_Comparison, msg = "le requires exactly 2 arguments"}
	}
	lt_result, lt_err := compare_lt(args[0], args[1])
	if lt_err.kind != .None {
		return nil, lt_err
	}
	if lt_result {
		return box_bool(true), {}
	}
	eq_result, eq_err := compare_eq(args[0], args[1])
	if eq_err.kind != .None {
		return nil, eq_err
	}
	return box_bool(eq_result), {}
}

_fn_gt :: proc(args: []any) -> (any, Error) {
	if len(args) != 2 {
		return nil, Error{kind = .No_Comparison, msg = "gt requires exactly 2 arguments"}
	}
	// gt = !(a <= b) = !(a < b || a == b)
	lt_result, lt_err := compare_lt(args[0], args[1])
	if lt_err.kind != .None {
		return nil, lt_err
	}
	if lt_result {
		return box_bool(false), {}
	}
	eq_result, eq_err := compare_eq(args[0], args[1])
	if eq_err.kind != .None {
		return nil, eq_err
	}
	return box_bool(!eq_result), {}
}

_fn_ge :: proc(args: []any) -> (any, Error) {
	if len(args) != 2 {
		return nil, Error{kind = .No_Comparison, msg = "ge requires exactly 2 arguments"}
	}
	lt_result, lt_err := compare_lt(args[0], args[1])
	if lt_err.kind != .None {
		return nil, lt_err
	}
	return box_bool(!lt_result), {}
}

// ---------------------------------------------------------------------------
// Print functions
// ---------------------------------------------------------------------------

_fn_print :: proc(args: []any) -> (any, Error) {
	// Fast path: single arg avoids builder allocation entirely.
	if len(args) == 1 {
		return box_string(sprint_value(args[0])), {}
	}
	b := strings.builder_make_len_cap(0, len(args) * 16)
	for arg, i in args {
		if i > 0 {
			strings.write_byte(&b, ' ')
		}
		_write_any(&b, arg)
	}
	return box_string(strings.to_string(b)), {}
}

_fn_printf :: proc(args: []any) -> (any, Error) {
	if len(args) == 0 {
		return nil, Error{kind = .Wrong_Arg_Count, msg = "printf requires at least 1 argument"}
	}
	format := _arg_to_string(args[0])
	b: strings.Builder
	_simple_printf(&b, format, args[1:])
	return box_string(strings.to_string(b)), {}
}

_fn_println :: proc(args: []any) -> (any, Error) {
	// Fast path: single arg avoids builder allocation.
	if len(args) == 1 {
		s := sprint_value(args[0])
		return box_string(strings.concatenate({s, "\n"})), {}
	}
	b := strings.builder_make_len_cap(0, len(args) * 16)
	for arg, i in args {
		if i > 0 {
			strings.write_byte(&b, ' ')
		}
		_write_any(&b, arg)
	}
	strings.write_byte(&b, '\n')
	return box_string(strings.to_string(b)), {}
}

// ---------------------------------------------------------------------------
// len
// ---------------------------------------------------------------------------

_fn_len :: proc(args: []any) -> (any, Error) {
	if len(args) != 1 {
		return nil, Error{kind = .Wrong_Arg_Count, msg = "len requires exactly 1 argument"}
	}
	val := args[0]
	if val == nil {
		return nil, Error{kind = .Wrong_Arg_Type, msg = "len of nil"}
	}

	n := reflect.length(val)
	if n >= 0 {
		return box_int(n), {}
	}

	return nil, Error{kind = .Wrong_Arg_Type, msg = "len of unsupported type"}
}

// ---------------------------------------------------------------------------
// index — index into arrays, slices, maps
// ---------------------------------------------------------------------------

_fn_index :: proc(args: []any) -> (any, Error) {
	if len(args) < 2 {
		return nil, Error{kind = .Wrong_Arg_Count, msg = "index requires at least 2 arguments"}
	}

	val := args[0]
	for idx_arg in args[1:] {
		if val == nil {
			return nil, Error{kind = .Wrong_Arg_Type, msg = "index of nil"}
		}

		v, _ := indirect(val)
		ti := reflect.type_info_base(type_info_of(v.id))

		#partial switch info in ti.variant {
		case runtime.Type_Info_Map:
			// Map indexing — use reflect to iterate and find key.
			val = _map_index(v, idx_arg)
			continue
		case runtime.Type_Info_Array, runtime.Type_Info_Slice, runtime.Type_Info_Dynamic_Array:
			idx, idx_ok := _arg_to_int(idx_arg)
			if !idx_ok {
				return nil, Error{kind = .Wrong_Arg_Type, msg = "non-integer index"}
			}
			n := reflect.length(v)
			if idx < 0 || idx >= n {
				return nil, Error {
					kind = .Index_Out_Of_Range,
					msg = fmt.aprintf("index out of range: %d (length %d)", idx, n),
				}
			}
			elem := reflect.index(v, idx)
			val = elem
			continue
		case runtime.Type_Info_String:
			idx, idx_ok := _arg_to_int(idx_arg)
			if !idx_ok {
				return nil, Error{kind = .Wrong_Arg_Type, msg = "non-integer index"}
			}
			s := _read_string(v)
			if idx < 0 || idx >= len(s) {
				return nil, Error {
					kind = .Index_Out_Of_Range,
					msg = fmt.aprintf("string index out of range: %d", idx),
				}
			}
			val = s[idx]
			continue
		case:
			return nil, Error{kind = .Wrong_Arg_Type, msg = "index of non-indexable type"}
		}
	}

	return val, {}
}

// ---------------------------------------------------------------------------
// call — call a function value
// ---------------------------------------------------------------------------

_fn_call :: proc(args: []any) -> (any, Error) {
	if len(args) < 1 {
		return nil, Error{kind = .Wrong_Arg_Count, msg = "call requires at least 1 argument"}
	}

	// In Odin, we can't dynamically call arbitrary functions via reflection
	// in the same way Go can. We support calling Template_Func values.
	fn_val := args[0]
	if fn_val == nil {
		return nil, Error{kind = .Wrong_Arg_Type, msg = "call of nil"}
	}

	fn, ok := fn_val.(Template_Func)
	if !ok {
		return nil, Error{kind = .Wrong_Arg_Type, msg = "call of non-function"}
	}

	return fn(args[1:])
}

// ---------------------------------------------------------------------------
// Escaping stubs — html, js, urlquery
// These are minimal implementations. The full versions are in the escape files.
// ---------------------------------------------------------------------------

_fn_html_escape :: proc(args: []any) -> (any, Error) {
	if len(args) != 1 {
		return nil, Error{kind = .Wrong_Arg_Count, msg = "html requires exactly 1 argument"}
	}
	s := _fast_string(args[0])
	return box_string(html_escape_string(s)), {}
}

_fn_js_escape :: proc(args: []any) -> (any, Error) {
	if len(args) != 1 {
		return nil, Error{kind = .Wrong_Arg_Count, msg = "js requires exactly 1 argument"}
	}
	s := _fast_string(args[0])
	return box_string(js_escape_string(s)), {}
}

_fn_urlquery :: proc(args: []any) -> (any, Error) {
	if len(args) != 1 {
		return nil, Error{kind = .Wrong_Arg_Count, msg = "urlquery requires exactly 1 argument"}
	}
	s := _fast_string(args[0])
	return box_string(url_query_escape(s)), {}
}

// _fast_string extracts a string from any without allocating when the value
// is already a string type. Falls back to sprint_value for other types.
@(private = "file")
_fast_string :: proc(val: any) -> string {
	if val == nil {return ""}
	ti := reflect.type_info_base(type_info_of(val.id))
	#partial switch info in ti.variant {
	case runtime.Type_Info_String:
		return _read_string(val)
	}
	return sprint_value(val)
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

// _write_any writes an any value to a string builder, fast-pathing common types.
@(private = "file")
_write_any :: proc(b: ^strings.Builder, val: any) {
	if val == nil {
		strings.write_string(b, "<nil>")
		return
	}
	ti := reflect.type_info_base(type_info_of(val.id))
	#partial switch info in ti.variant {
	case runtime.Type_Info_String:
		strings.write_string(b, _read_string(val))
		return
	case runtime.Type_Info_Boolean:
		strings.write_string(b, (^bool)(val.data)^ ? "true" : "false")
		return
	case runtime.Type_Info_Integer:
		buf: [32]u8
		s: string
		if info.signed {
			s = _itoa(buf[:], _read_int(val.data, ti.size))
		} else {
			s = _utoa(buf[:], _read_uint(val.data, ti.size))
		}
		strings.write_string(b, s)
		return
	}
	fmt.sbprintf(b, "%v", val)
}

@(private = "file")
_arg_to_string :: proc(val: any) -> string {
	if val == nil {
		return ""
	}
	ti := reflect.type_info_base(type_info_of(val.id))
	#partial switch _ in ti.variant {
	case runtime.Type_Info_String:
		return _read_string(val)
	}
	return sprint_value(val)
}

@(private = "file")
_arg_to_int :: proc(val: any) -> (int, bool) {
	if val == nil {
		return 0, false
	}
	ti := reflect.type_info_base(type_info_of(val.id))
	#partial switch info in ti.variant {
	case runtime.Type_Info_Integer:
		if info.signed {
			return int(_read_int(val.data, ti.size)), true
		}
		return int(_read_uint(val.data, ti.size)), true
	case runtime.Type_Info_Enum:
		backing := reflect.type_info_core(ti)
		#partial switch bi in backing.variant {
		case runtime.Type_Info_Integer:
			if bi.signed {
				return int(_read_int(val.data, backing.size)), true
			}
			return int(_read_uint(val.data, backing.size)), true
		}
	}
	return 0, false
}

// _map_index looks up a key in a map using reflect iteration.
@(private = "file")
_map_index :: proc(m: any, key: any) -> any {
	it: int
	for {
		k, v, ok := reflect.iterate_map(m, &it)
		if !ok {
			break
		}
		eq, _ := compare_eq(k, key)
		if eq {
			return v
		}
	}
	return nil
}

// _simple_printf implements a printf-like formatter.
// Collects the full format specifier (flags, width, precision) and delegates
// to fmt.sbprintf so that e.g. "%.2f" or "%04d" work correctly.
@(private = "file")
_simple_printf :: proc(b: ^strings.Builder, format: string, args: []any) {
	arg_idx := 0
	i := 0
	for i < len(format) {
		if format[i] != '%' {
			strings.write_byte(b, format[i])
			i += 1
			continue
		}

		// Remember start of the format specifier.
		spec_start := i
		i += 1 // skip '%'
		if i >= len(format) {
			strings.write_byte(b, '%')
			break
		}

		// Literal %%
		if format[i] == '%' {
			strings.write_byte(b, '%')
			i += 1
			continue
		}

		// Skip flags: '-', '+', ' ', '0', '#'
		for i < len(format) &&
		    (format[i] == '-' ||
				    format[i] == '+' ||
				    format[i] == ' ' ||
				    format[i] == '0' ||
				    format[i] == '#') {
			i += 1
		}
		// Skip width: digits
		for i < len(format) && format[i] >= '0' && format[i] <= '9' {
			i += 1
		}
		// Skip precision: '.' followed by digits
		if i < len(format) && format[i] == '.' {
			i += 1
			for i < len(format) && format[i] >= '0' && format[i] <= '9' {
				i += 1
			}
		}

		if i >= len(format) {
			// Incomplete format spec — write it literally.
			strings.write_string(b, format[spec_start:])
			break
		}

		verb := format[i]
		i += 1

		if arg_idx >= len(args) {
			strings.write_string(b, "%!")
			strings.write_byte(b, verb)
			strings.write_string(b, "(MISSING)")
			continue
		}

		arg := args[arg_idx]
		arg_idx += 1

		// Build the full format string (e.g. "%.2f", "%04d") and delegate to fmt.
		spec := format[spec_start:i]

		switch verb {
		case 's':
			s := _arg_to_string(arg)
			strings.write_string(b, s)
		case 'v', 'd', 'f', 't', 'q', 'x', 'X', 'o', 'b', 'e', 'E', 'g', 'G', 'c':
			fmt.sbprintf(b, spec, arg)
		case:
			// Unknown verb — pass through.
			strings.write_string(b, spec)
			fmt.sbprintf(b, "(%v)", arg)
		}
	}
}
