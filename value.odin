package ohtml

import "base:runtime"
import "core:fmt"
import "core:io"
import "core:reflect"


// ---------------------------------------------------------------------------
// Indirection — follow pointers to get the concrete value
// ---------------------------------------------------------------------------

// indirect follows pointers until a non-pointer value is reached.
// Returns the dereferenced value and whether it was nil.
indirect :: proc(val: any) -> (result: any, is_nil: bool) {
	v := val
	for {
		if v == nil {
			return v, true
		}
		ti := type_info_of(v.id)
		#partial switch info in ti.variant {
		case runtime.Type_Info_Pointer:
			ptr := (^rawptr)(v.data)^
			if ptr == nil {
				return v, true
			}
			v = any{ptr, info.elem.id}
		case:
			return v, false
		}
	}
}

// ---------------------------------------------------------------------------
// Truthiness
// ---------------------------------------------------------------------------

// Value_Kind classifies an any value for truthiness and comparison.
Value_Kind :: enum {
	Invalid,
	Bool,
	Int,
	Uint,
	Float,
	String,
	Complex,
}

// is_true reports whether val is 'true', in the sense of not being the zero
// of its type. The second return value reports whether the value's truth
// could be determined at all.
is_true :: proc(val: any) -> (truth: bool, ok: bool) {
	if val == nil {
		return false, true
	}

	ti := reflect.type_info_base(type_info_of(val.id))

	#partial switch info in ti.variant {
	case runtime.Type_Info_Boolean:
		truth = (^bool)(val.data)^
		ok = true
	case runtime.Type_Info_Integer:
		if info.signed {
			truth = _read_int(val.data, ti.size) != 0
		} else {
			truth = _read_uint(val.data, ti.size) != 0
		}
		ok = true
	case runtime.Type_Info_Float:
		truth = _read_float(val.data, ti.size) != 0
		ok = true
	case runtime.Type_Info_String:
		s := _read_string(val)
		truth = len(s) > 0
		ok = true
	case runtime.Type_Info_Pointer:
		ptr := (^rawptr)(val.data)^
		truth = ptr != nil
		ok = true
	case runtime.Type_Info_Slice:
		raw := (^runtime.Raw_Slice)(val.data)^
		truth = raw.len > 0
		ok = true
	case runtime.Type_Info_Dynamic_Array:
		raw := (^runtime.Raw_Dynamic_Array)(val.data)^
		truth = raw.len > 0
		ok = true
	case runtime.Type_Info_Array:
		truth = info.count > 0
		ok = true
	case runtime.Type_Info_Map:
		raw := (^runtime.Raw_Map)(val.data)^
		truth = runtime.map_len(raw) > 0
		ok = true
	case runtime.Type_Info_Struct:
		// Structs are always true (like Go).
		truth = true
		ok = true
	case runtime.Type_Info_Enum:
		// Treat enums like their backing integer.
		backing := reflect.type_info_core(ti)
		#partial switch bi in backing.variant {
		case runtime.Type_Info_Integer:
			if bi.signed {
				truth = _read_int(val.data, backing.size) != 0
			} else {
				truth = _read_uint(val.data, backing.size) != 0
			}
			ok = true
		case:
			ok = false
		}
	case runtime.Type_Info_Union:
		// A union is true if it has a non-nil variant.
		tag := reflect.get_union_variant(val)
		truth = tag != nil
		ok = true
	case:
		// Unknown type — cannot determine truthiness.
		ok = false
	}
	return
}

// ---------------------------------------------------------------------------
// Comparison
// ---------------------------------------------------------------------------

basic_kind :: proc(val: any) -> (Value_Kind, Error) {
	if val == nil {
		return .Invalid, {}
	}
	ti := reflect.type_info_base(type_info_of(val.id))

	#partial switch info in ti.variant {
	case runtime.Type_Info_Boolean:
		return .Bool, {}
	case runtime.Type_Info_Integer:
		if info.signed {
			return .Int, {}
		}
		return .Uint, {}
	case runtime.Type_Info_Float:
		return .Float, {}
	case runtime.Type_Info_String:
		return .String, {}
	case runtime.Type_Info_Complex:
		return .Complex, {}
	case runtime.Type_Info_Enum:
		backing := reflect.type_info_core(ti)
		#partial switch bi in backing.variant {
		case runtime.Type_Info_Integer:
			if bi.signed {
				return .Int, {}
			}
			return .Uint, {}
		}
	case runtime.Type_Info_Rune:
		return .Int, {}
	}

	return .Invalid, Error{kind = .Bad_Comparison_Type, msg = "invalid type for comparison"}
}

// compare_values compares two values using the given operation.
compare_values :: proc(op: string, a: any, b: any) -> (bool, Error) {
	switch op {
	case "eq":
		return compare_eq(a, b)
	case "ne":
		result, err := compare_eq(a, b)
		return !result, err
	case "lt":
		return compare_lt(a, b)
	case "le":
		lt_result, lt_err := compare_lt(a, b)
		if lt_result || lt_err.kind != .None {
			return lt_result, lt_err
		}
		return compare_eq(a, b)
	case "gt":
		le_result, le_err := compare_values("le", a, b)
		if le_err.kind != .None {
			return false, le_err
		}
		return !le_result, {}
	case "ge":
		lt_result, lt_err := compare_lt(a, b)
		if lt_err.kind != .None {
			return false, lt_err
		}
		return !lt_result, {}
	}
	return false, Error {
		kind = .Bad_Comparison_Type,
		msg = fmt.aprintf("unknown comparison op: %s", op),
	}
}

compare_eq :: proc(a: any, b: any) -> (bool, Error) {
	k1, _ := basic_kind(a)
	k2, _ := basic_kind(b)

	// Promote to common numeric kind when types differ.
	if k1 != k2 {
		// Int/Float or Uint/Float — promote both to f64.
		if (k1 == .Float && (k2 == .Int || k2 == .Uint)) ||
		   ((k1 == .Int || k1 == .Uint) && k2 == .Float) {
			return _any_to_f64(a) == _any_to_f64(b), {}
		}
		// Int/Uint cross-comparison.
		if k1 == .Int && k2 == .Uint {
			ai := _any_to_i64(a)
			bu := _any_to_u64(b)
			return ai >= 0 && u64(ai) == bu, {}
		}
		if k1 == .Uint && k2 == .Int {
			au := _any_to_u64(a)
			bi := _any_to_i64(b)
			return bi >= 0 && au == u64(bi), {}
		}
		return false, Error{kind = .Bad_Comparison_Type, msg = "incompatible types for comparison"}
	}

	switch k1 {
	case .Bool:
		return (^bool)(a.data)^ == (^bool)(b.data)^, {}
	case .Int:
		return _any_to_i64(a) == _any_to_i64(b), {}
	case .Uint:
		return _any_to_u64(a) == _any_to_u64(b), {}
	case .Float:
		return _any_to_f64(a) == _any_to_f64(b), {}
	case .String:
		return _read_string(a) == _read_string(b), {}
	case .Complex:
		return false, Error{kind = .Bad_Comparison_Type, msg = "complex comparison not supported"}
	case .Invalid:
		// Both nil.
		return a == nil && b == nil, {}
	}
	return false, Error{kind = .Bad_Comparison_Type, msg = "invalid type for comparison"}
}

compare_lt :: proc(a: any, b: any) -> (bool, Error) {
	k1, err1 := basic_kind(a)
	if err1.kind != .None {
		return false, err1
	}
	k2, err2 := basic_kind(b)
	if err2.kind != .None {
		return false, err2
	}

	// Promote to common numeric kind when types differ.
	if k1 != k2 {
		// Int/Float or Uint/Float — promote both to f64.
		if (k1 == .Float && (k2 == .Int || k2 == .Uint)) ||
		   ((k1 == .Int || k1 == .Uint) && k2 == .Float) {
			return _any_to_f64(a) < _any_to_f64(b), {}
		}
		// Int/Uint cross-comparison.
		if k1 == .Int && k2 == .Uint {
			ai := _any_to_i64(a)
			bu := _any_to_u64(b)
			return ai < 0 || u64(ai) < bu, {}
		}
		if k1 == .Uint && k2 == .Int {
			au := _any_to_u64(a)
			bi := _any_to_i64(b)
			return bi >= 0 && au < u64(bi), {}
		}
		return false, Error{kind = .Bad_Comparison_Type, msg = "incompatible types for comparison"}
	}

	switch k1 {
	case .Bool, .Complex:
		return false, Error{kind = .Bad_Comparison_Type, msg = "invalid type for comparison"}
	case .Int:
		return _any_to_i64(a) < _any_to_i64(b), {}
	case .Uint:
		return _any_to_u64(a) < _any_to_u64(b), {}
	case .Float:
		return _any_to_f64(a) < _any_to_f64(b), {}
	case .String:
		return _read_string(a) < _read_string(b), {}
	case .Invalid:
		return false, Error{kind = .Bad_Comparison_Type, msg = "invalid type for comparison"}
	}
	return false, Error{kind = .Bad_Comparison_Type, msg = "invalid type for comparison"}
}

// ---------------------------------------------------------------------------
// Print value — write an any to a writer
// ---------------------------------------------------------------------------

print_value :: proc(w: io.Writer, val: any) -> io.Error {
	v, is_nil := indirect(val)
	if is_nil || v == nil {
		_, err := io.write_string(w, "<no value>")
		return err
	}
	// Fast path for common types — avoids fmt.wprintf format string parsing.
	ti := reflect.type_info_base(type_info_of(v.id))
	#partial switch info in ti.variant {
	case runtime.Type_Info_String:
		_, err := io.write_string(w, _read_string(v))
		return err
	case runtime.Type_Info_Boolean:
		_, err := io.write_string(w, (^bool)(v.data)^ ? "true" : "false")
		return err
	case runtime.Type_Info_Integer:
	// Fall through to fmt for integers — still faster than format-string parsing
	// since we use a specific format.
	case runtime.Type_Info_Float:
	// Fall through to fmt
	}
	fmt.wprintf(w, "%v", v)
	return nil
}

// sprint_value converts any value to a string.
sprint_value :: proc(val: any) -> string {
	v, is_nil := indirect(val)
	if is_nil || v == nil {
		return "<no value>"
	}
	// Check if it's already a string.
	ti := reflect.type_info_base(type_info_of(v.id))
	#partial switch _ in ti.variant {
	case runtime.Type_Info_String:
		return _read_string(v)
	}
	return fmt.aprintf("%v", v)
}

// ---------------------------------------------------------------------------
// Boxing — heap-allocate values so they survive as `any`
// ---------------------------------------------------------------------------

// box_int allocates an int on the heap and returns it as `any`.
box_int :: proc(n: int) -> any {
	p := new(int)
	p^ = n
	return p^
}

// box_i64 allocates an i64 on the heap and returns it as `any`.
box_i64 :: proc(n: i64) -> any {
	p := new(i64)
	p^ = n
	return p^
}

// box_f64 allocates an f64 on the heap and returns it as `any`.
box_f64 :: proc(n: f64) -> any {
	p := new(f64)
	p^ = n
	return p^
}

// box_bool allocates a bool on the heap and returns it as `any`.
box_bool :: proc(b: bool) -> any {
	p := new(bool)
	p^ = b
	return p^
}

// box_string allocates a string on the heap and returns it as `any`.
box_string :: proc(s: string) -> any {
	p := new(string)
	p^ = s
	return p^
}

// ---------------------------------------------------------------------------
// Internal helpers — read typed data from `any`
// ---------------------------------------------------------------------------

@(private = "package")
_read_int :: proc(data: rawptr, size: int) -> i64 {
	switch size {
	case 1:
		return i64((^i8)(data)^)
	case 2:
		return i64((^i16)(data)^)
	case 4:
		return i64((^i32)(data)^)
	case 8:
		return (^i64)(data)^
	}
	return 0
}

@(private = "package")
_read_uint :: proc(data: rawptr, size: int) -> u64 {
	switch size {
	case 1:
		return u64((^u8)(data)^)
	case 2:
		return u64((^u16)(data)^)
	case 4:
		return u64((^u32)(data)^)
	case 8:
		return (^u64)(data)^
	}
	return 0
}

@(private = "package")
_read_float :: proc(data: rawptr, size: int) -> f64 {
	switch size {
	case 4:
		return f64((^f32)(data)^)
	case 8:
		return (^f64)(data)^
	}
	return 0
}

@(private = "package")
_read_string :: proc(val: any) -> string {
	ti := reflect.type_info_base(type_info_of(val.id))
	#partial switch info in ti.variant {
	case runtime.Type_Info_String:
		if info.is_cstring {
			cs := (^cstring)(val.data)^
			return string(cs)
		}
		return (^string)(val.data)^
	}
	return ""
}

@(private = "package")
_any_to_i64 :: proc(val: any) -> i64 {
	ti := reflect.type_info_base(type_info_of(val.id))
	#partial switch info in ti.variant {
	case runtime.Type_Info_Integer:
		return _read_int(val.data, ti.size)
	case runtime.Type_Info_Enum:
		backing := reflect.type_info_core(ti)
		return _read_int(val.data, backing.size)
	case runtime.Type_Info_Rune:
		return i64((^rune)(val.data)^)
	}
	return 0
}

@(private = "package")
_any_to_u64 :: proc(val: any) -> u64 {
	ti := reflect.type_info_base(type_info_of(val.id))
	#partial switch info in ti.variant {
	case runtime.Type_Info_Integer:
		return _read_uint(val.data, ti.size)
	case runtime.Type_Info_Enum:
		backing := reflect.type_info_core(ti)
		return _read_uint(val.data, backing.size)
	}
	return 0
}

@(private = "package")
_any_to_f64 :: proc(val: any) -> f64 {
	ti := reflect.type_info_base(type_info_of(val.id))
	#partial switch info in ti.variant {
	case runtime.Type_Info_Float:
		return _read_float(val.data, ti.size)
	case runtime.Type_Info_Integer:
		if info.signed {
			return f64(_any_to_i64(val))
		}
		return f64(_any_to_u64(val))
	}
	return 0
}
