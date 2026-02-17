package cli

import "core:strings"

// ---------------------------------------------------------------------------
// Type information — classify parsed types for code generation
// ---------------------------------------------------------------------------

Type_Kind :: enum {
	Unknown,
	String,
	Bool,
	Int, // i8..i64, int
	Uint, // u8..u64, uint
	Float, // f32, f64
	Named, // A struct type reference
	Slice, // []T
	Array, // [N]T
	Dynamic, // [dynamic]T
	Pointer, // ^T
	Maybe, // Maybe(T)
}

Type_Info :: struct {
	kind:      Type_Kind,
	name:      string, // for Named types, the struct name
	elem_type: string, // for Slice/Array/Dynamic/Pointer, the element type string
}

// classify_type determines the Type_Kind from a type string.
classify_type :: proc(type_str: string) -> Type_Info {
	s := strings.trim_space(type_str)

	// Pointer: ^T
	if len(s) > 0 && s[0] == '^' {
		return Type_Info{kind = .Pointer, elem_type = s[1:]}
	}

	// Dynamic array: [dynamic]T
	if strings.has_prefix(s, "[dynamic]") {
		return Type_Info{kind = .Dynamic, elem_type = s[9:]}
	}

	// Slice: []T
	if strings.has_prefix(s, "[]") {
		return Type_Info{kind = .Slice, elem_type = s[2:]}
	}

	// Fixed array: [N]T
	if len(s) > 0 && s[0] == '[' {
		if close := strings.index(s, "]"); close > 0 {
			return Type_Info{kind = .Array, elem_type = s[close + 1:]}
		}
	}

	// Basic types
	switch s {
	case "string":
		return Type_Info{kind = .String}
	case "bool":
		return Type_Info{kind = .Bool}
	case "int", "i8", "i16", "i32", "i64":
		return Type_Info{kind = .Int}
	case "uint", "u8", "u16", "u32", "u64":
		return Type_Info{kind = .Uint}
	case "f32", "f64":
		return Type_Info{kind = .Float}
	}

	// Safe_* types from ohtml
	switch s {
	case "ohtml.Safe_HTML", "Safe_HTML":
		return Type_Info{kind = .String, name = "Safe_HTML"}
	case "ohtml.Safe_CSS", "Safe_CSS":
		return Type_Info{kind = .String, name = "Safe_CSS"}
	case "ohtml.Safe_URL", "Safe_URL":
		return Type_Info{kind = .String, name = "Safe_URL"}
	case "ohtml.Safe_JS", "Safe_JS":
		return Type_Info{kind = .String, name = "Safe_JS"}
	case "ohtml.Safe_JS_Str", "Safe_JS_Str":
		return Type_Info{kind = .String, name = "Safe_JS_Str"}
	case "ohtml.Safe_HTML_Attr", "Safe_HTML_Attr":
		return Type_Info{kind = .String, name = "Safe_HTML_Attr"}
	case "ohtml.Safe_Srcset", "Safe_Srcset":
		return Type_Info{kind = .String, name = "Safe_Srcset"}
	}

	// Maybe: Maybe(T)
	if strings.has_prefix(s, "Maybe(") && strings.has_suffix(s, ")") {
		inner := s[6:len(s) - 1]
		return Type_Info{kind = .Maybe, name = s, elem_type = inner}
	}

	// Otherwise it's a named type (struct reference)
	return Type_Info{kind = .Named, name = s}
}

// resolve_field_type resolves a field name on a struct and returns its type info.
resolve_field_type :: proc(
	registry: ^Type_Registry,
	struct_name: string,
	field_name: string,
) -> (
	Type_Info,
	bool,
) {
	ps, found := registry.structs[struct_name]
	if !found {
		return {}, false
	}
	for f in ps.fields {
		if f.name == field_name {
			return classify_type(f.type_str), true
		}
	}
	return {}, false
}

// resolve_field_chain resolves a chain of field names (e.g. ["product", "name"])
// starting from a base struct type and returns the final type info.
resolve_field_chain :: proc(
	registry: ^Type_Registry,
	base_struct: string,
	fields: []string,
) -> (
	Type_Info,
	bool,
) {
	current_struct := base_struct
	for i in 0 ..< len(fields) {
		ti, ok := resolve_field_type(registry, current_struct, fields[i])
		if !ok {
			return {}, false
		}
		if i < len(fields) - 1 {
			// Intermediate field must be a named (struct) type.
			// For Maybe types, unwrap to get the inner type.
			if ti.kind == .Maybe {
				inner := classify_type(ti.elem_type)
				if inner.kind == .Named {
					current_struct = inner.name
				} else {
					return {}, false
				}
			} else if ti.kind == .Named {
				current_struct = ti.name
			} else {
				return {}, false
			}
		} else {
			return ti, true
		}
	}
	return {}, false
}

// is_numeric returns true if the type is an integer, uint, or float.
is_numeric :: proc(ti: Type_Info) -> bool {
	return ti.kind == .Int || ti.kind == .Uint || ti.kind == .Float
}

// is_safe_type returns true if the type is a Safe_* content type.
is_safe_type :: proc(ti: Type_Info) -> bool {
	if ti.kind != .String {
		return false
	}
	switch ti.name {
	case "Safe_HTML",
	     "Safe_CSS",
	     "Safe_URL",
	     "Safe_JS",
	     "Safe_JS_Str",
	     "Safe_HTML_Attr",
	     "Safe_Srcset":
		return true
	}
	return false
}

// needs_html_escape returns true if the type produces output that may contain HTML special chars.
needs_html_escape :: proc(ti: Type_Info) -> bool {
	// Numeric and bool types never produce HTML-special characters.
	if ti.kind == .Bool || is_numeric(ti) {
		return false
	}
	// Safe_HTML is already trusted.
	if ti.name == "Safe_HTML" {
		return false
	}
	return true
}
