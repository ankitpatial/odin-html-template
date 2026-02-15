package cli

import "core:strings"

// ---------------------------------------------------------------------------
// Struct parser — parse Odin struct definitions from source files
// ---------------------------------------------------------------------------

// Parsed_Field represents a single field in a struct.
Parsed_Field :: struct {
	name:     string,
	type_str: string,
}

// Parsed_Struct represents a parsed Odin struct definition.
Parsed_Struct :: struct {
	name:   string,
	fields: [dynamic]Parsed_Field,
}

// Type_Registry maps struct names to their parsed definitions.
Type_Registry :: struct {
	structs: map[string]^Parsed_Struct,
}

registry_init :: proc(r: ^Type_Registry) {
	r.structs = make(map[string]^Parsed_Struct)
}

registry_destroy :: proc(r: ^Type_Registry) {
	for _, s in r.structs {
		delete(s.fields)
		free(s)
	}
	delete(r.structs)
}

// parse_struct_file parses all struct definitions from an Odin source file.
parse_struct_files :: proc(r: ^Type_Registry, sources: []string) {
	for src in sources {
		_parse_structs_from_source(r, src)
	}
}

_parse_structs_from_source :: proc(r: ^Type_Registry, source: string) {
	lines := strings.split_lines(source)
	defer delete(lines)

	i := 0
	for i < len(lines) {
		line := strings.trim_space(lines[i])

		// Look for: Name :: struct {
		if struct_name, ok := _parse_struct_header(line); ok {
			ps := new(Parsed_Struct)
			ps.name = struct_name
			i += 1

			// Parse fields until closing brace.
			for i < len(lines) {
				field_line := strings.trim_space(lines[i])
				i += 1

				if field_line == "}" || strings.has_prefix(field_line, "}") {
					break
				}

				if len(field_line) == 0 || strings.has_prefix(field_line, "//") {
					continue
				}

				// Parse field: "name: type,"
				if field, fok := _parse_field_line(field_line); fok {
					append(&ps.fields, field)
				}
			}

			r.structs[ps.name] = ps
			continue
		}
		i += 1
	}
}

// _parse_struct_header checks if a line is "Name :: struct {" or "Name :: struct {"
// Returns the struct name if found.
_parse_struct_header :: proc(line: string) -> (string, bool) {
	// Find "::" separator
	idx := strings.index(line, "::")
	if idx < 0 {
		return "", false
	}

	name := strings.trim_space(line[:idx])
	rest := strings.trim_space(line[idx + 2:])

	// Rest should start with "struct"
	if !strings.has_prefix(rest, "struct") {
		return "", false
	}

	after_struct := strings.trim_space(rest[6:])
	if !strings.has_prefix(after_struct, "{") {
		return "", false
	}

	if len(name) == 0 {
		return "", false
	}

	return name, true
}

// _parse_field_line parses "name: type," or "name: type"
_parse_field_line :: proc(line: string) -> (Parsed_Field, bool) {
	// Find the colon separator
	colon_idx := strings.index(line, ":")
	if colon_idx < 0 {
		return {}, false
	}

	name := strings.trim_space(line[:colon_idx])
	rest := strings.trim_space(line[colon_idx + 1:])

	// Skip "using" fields like "using branch: Branch_Node"
	if strings.has_prefix(name, "using ") {
		return {}, false
	}

	// Remove trailing comma and inline comments
	type_str := rest
	if comma_idx := strings.index(type_str, ","); comma_idx >= 0 {
		type_str = strings.trim_space(type_str[:comma_idx])
	}
	if comment_idx := strings.index(type_str, "//"); comment_idx >= 0 {
		type_str = strings.trim_space(type_str[:comment_idx])
	}

	if len(name) == 0 || len(type_str) == 0 {
		return {}, false
	}

	return Parsed_Field{name = name, type_str = type_str}, true
}
