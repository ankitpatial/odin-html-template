package cli

import "core:fmt"
import "core:os"
import "core:strings"

import ohtml "../"

// ---------------------------------------------------------------------------
// CLI — compile HTML templates to Odin source code
//
// Walks -src directory for .html files. Each file may use @include("path")
// directives in HTML comments to pull in layouts/partials. Includes are
// resolved relative to the including file and concatenated before parsing.
// ---------------------------------------------------------------------------

main :: proc() {
	src_dir: string
	dest_dir: string
	struct_files: [dynamic]string
	pkg_name: string
	ohtml_import: string

	args := os.args[1:]
	i := 0
	for i < len(args) {
		arg := args[i]
		if _consume_flag(arg, "-src", &src_dir) ||
		   _consume_flag(arg, "-dest", &dest_dir) ||
		   _consume_flag(arg, "-pkg", &pkg_name) ||
		   _consume_flag(arg, "-ohtml-import", &ohtml_import) {
			i += 1
			continue
		}
		if strings.has_prefix(arg, "-struct-file=") {
			append(&struct_files, arg[len("-struct-file="):])
			i += 1
			continue
		}
		fmt.eprintfln("Unknown argument: %s", arg)
		_print_usage()
		os.exit(1)
	}
	defer delete(struct_files)

	if len(dest_dir) == 0 {
		fmt.eprintln("Error: -dest is required")
		_print_usage()
		os.exit(1)
	}

	if len(src_dir) == 0 {
		fmt.eprintln("Error: -src is required")
		_print_usage()
		os.exit(1)
	}

	if len(pkg_name) == 0 {
		pkg_name = _dir_name(dest_dir)
	}

	if len(ohtml_import) == 0 {
		ohtml_import = "ohtml:."
	}

	// Parse struct definitions
	registry: Type_Registry
	registry_init(&registry)
	defer registry_destroy(&registry)

	struct_sources: [dynamic][]u8
	defer {
		for src in struct_sources {
			delete(src)
		}
		delete(struct_sources)
	}
	for sf in struct_files {
		src_bytes, ok := os.read_entire_file_from_filename(sf)
		if !ok {
			fmt.eprintfln("Error: could not read struct file: %s", sf)
			os.exit(1)
		}
		parse_struct_files(&registry, {string(src_bytes)})
		append(&struct_sources, src_bytes)
	}

	// Ensure destination directory exists
	if !os.exists(dest_dir) {
		err := os.make_directory(dest_dir)
		if err != nil {
			fmt.eprintfln("Error: could not create dest directory: %s", dest_dir)
			os.exit(1)
		}
	}

	use_inference := len(struct_files) == 0

	_run_auto_mode(src_dir, dest_dir, pkg_name, ohtml_import, &registry, use_inference)
}

// ---------------------------------------------------------------------------
// Auto mode — walk src, resolve @include directives, generate
// ---------------------------------------------------------------------------

_run_auto_mode :: proc(
	src_dir: string,
	dest_dir: string,
	pkg_name: string,
	ohtml_import: string,
	registry: ^Type_Registry,
	use_inference: bool,
) {
	html_files := _find_html_files(src_dir)
	defer delete(html_files)

	if len(html_files) == 0 {
		fmt.eprintln("No .html files found in", src_dir)
		return
	}

	all_inferred: [dynamic]Parsed_Struct
	defer {
		for &s in all_inferred {
			delete(s.fields)
		}
		delete(all_inferred)
	}

	all_helpers: Helper_Flags

	total := 0
	errors := 0

	for file_info in html_files {
		src_bytes, rok := os.read_entire_file_from_filename(file_info.full_path)
		if !rok {
			fmt.eprintfln("Error: could not read %s", file_info.full_path)
			errors += 1
			total += 1
			continue
		}

		src_content := string(src_bytes)

		// Resolve @include directives recursively
		visited := make(map[string]bool)
		defer delete(visited)
		combined, cok := _resolve_includes(file_info.full_path, src_content, &visited)
		delete(src_bytes)
		if !cok {
			errors += 1
			total += 1
			continue
		}
		defer delete(combined)

		out_name := _strip_ext(file_info.rel_path)
		proc_name := _proc_name_from_name(out_name)
		out_file := _output_path_from_name(dest_dir, out_name)

		ok := _process_entry_template(
			combined,
			file_info.full_path,
			proc_name,
			out_name,
			out_file,
			pkg_name,
			ohtml_import,
			registry,
			use_inference,
			&all_inferred,
			&all_helpers,
		)
		total += 1
		if !ok {
			errors += 1
		} else {
			fmt.printfln("  %s -> %s (%s)", file_info.rel_path, out_file, proc_name)
		}
	}

	if use_inference && len(all_inferred) > 0 {
		emit_types_file(dest_dir, pkg_name, ohtml_import, all_inferred[:])
		fmt.printfln("  -> %s/types_gen.odin (%d structs)", dest_dir, len(all_inferred))
	}

	// Generate helpers.odin with ohtml imports
	_emit_helpers_file(dest_dir, pkg_name, &all_helpers)

	fmt.printfln("Generated %d files (%d errors)", total - errors, errors)
}

// ---------------------------------------------------------------------------
// @include resolution
// ---------------------------------------------------------------------------

// _extract_includes scans an HTML comment block for @include("path") directives.
// Returns paths in the order they appear.
_extract_includes :: proc(content: string) -> [dynamic]string {
	includes := make([dynamic]string)

	// Only scan inside <!-- ... --> comment blocks
	s := content
	for {
		cstart := strings.index(s, "<!--")
		if cstart < 0 {break}
		s = s[cstart + 4:]

		cend := strings.index(s, "-->")
		comment := s[:cend] if cend >= 0 else s

		// Scan for @include("...") within this comment
		c := comment
		for {
			MARKER :: "@include(\""
			idx := strings.index(c, MARKER)
			if idx < 0 {break}
			c = c[idx + len(MARKER):]

			// Find closing quote
			qend := strings.index(c, "\"")
			if qend < 0 {break}

			path := strings.trim_space(c[:qend])
			if len(path) > 0 {
				append(&includes, path)
			}
			c = c[qend + 1:]
		}

		if cend < 0 {break}
		s = s[cend + 3:]
	}

	return includes
}

// _resolve_includes recursively resolves @include directives and concatenates
// included content before the including file's content. Detects circular includes.
_resolve_includes :: proc(
	file_path: string,
	content: string,
	visited: ^map[string]bool,
) -> (
	string,
	bool,
) {
	if file_path in visited^ {
		fmt.eprintfln("Error: circular @include detected: %s", file_path)
		return "", false
	}
	visited[file_path] = true

	includes := _extract_includes(content)
	defer delete(includes)

	if len(includes) == 0 {
		return strings.clone(content), true
	}

	file_dir := _parent_dir(file_path)
	parts := make([dynamic]string)
	defer delete(parts)

	for inc_rel in includes {
		inc_path := _normalize_path(file_dir, inc_rel)
		defer delete(inc_path)

		inc_bytes, rok := os.read_entire_file_from_filename(inc_path)
		if !rok {
			fmt.eprintfln("Error: could not read @include(\"%s\") from %s", inc_rel, file_path)
			for p in parts {delete(p)}
			return "", false
		}
		inc_content := string(inc_bytes)

		resolved, ok := _resolve_includes(inc_path, inc_content, visited)
		delete(inc_bytes)
		if !ok {
			for p in parts {delete(p)}
			return "", false
		}
		append(&parts, resolved)
	}

	// Included content first, then this file's content last
	append(&parts, strings.clone(content))

	result := strings.concatenate(parts[:])
	for p in parts {delete(p)}
	return result, true
}

// _normalize_path joins a base directory with a relative path, resolving ".." segments.
_normalize_path :: proc(base_dir: string, rel: string) -> string {
	joined := strings.concatenate({base_dir, "/", rel})
	defer delete(joined)

	is_abs := len(joined) > 0 && joined[0] == '/'

	// Split into segments and resolve ".."
	segments := make([dynamic]string)
	defer delete(segments)

	remaining := joined
	for {
		slash := strings.index(remaining, "/")
		if slash < 0 {
			if len(remaining) > 0 && remaining != "." {
				if remaining == ".." {
					if len(segments) > 0 {
						pop(&segments)
					}
				} else {
					append(&segments, remaining)
				}
			}
			break
		}
		seg := remaining[:slash]
		remaining = remaining[slash + 1:]
		if seg == ".." {
			if len(segments) > 0 {
				pop(&segments)
			}
		} else if seg != "." && len(seg) > 0 {
			append(&segments, seg)
		}
	}

	result := strings.join(segments[:], "/")
	if is_abs {
		abs := strings.concatenate({"/", result})
		delete(result)
		return abs
	}
	return result
}

// _parent_dir returns the directory portion of a file path.
_parent_dir :: proc(path: string) -> string {
	slash := strings.last_index_any(path, "/\\")
	if slash < 0 {
		return "."
	}
	return path[:slash]
}

// ---------------------------------------------------------------------------
// Template processing
// ---------------------------------------------------------------------------

_process_entry_template :: proc(
	combined: string,
	entry_path: string,
	proc_name: string,
	template_name: string,
	out_file: string,
	pkg_name: string,
	ohtml_import: string,
	registry: ^Type_Registry,
	use_inference: bool,
	all_inferred: ^[dynamic]Parsed_Struct,
	all_helpers: ^Helper_Flags,
) -> bool {
	// Parse
	tmpl_name := _strip_ext(_base_name(entry_path))
	t := ohtml.template_new(tmpl_name)
	defer ohtml.template_destroy(t)

	_, parse_err := ohtml.template_parse(t, combined)
	if parse_err.kind != .None {
		fmt.eprintfln("Parse error in %s: %s", entry_path, parse_err.msg)
		if parse_err.msg != "" {delete(parse_err.msg)}
		return false
	}

	// Escape analysis
	esc_err := ohtml.escape_template(t)
	if esc_err.kind != .None {
		fmt.eprintfln("Escape error in %s: %s", entry_path, esc_err.msg)
		if esc_err.msg != "" {delete(esc_err.msg)}
		return false
	}

	// Determine data type — use @type directive or inference
	data_type := _extract_type_directive_from_source(combined)

	if len(data_type) == 0 && use_inference {
		root_type, inferred := infer_from_template(t, template_name)

		hints := extract_field_hints(combined)
		defer delete(hints)
		_apply_field_hints(registry, &inferred, hints)

		data_type = strings.clone(root_type)

		for &s in inferred {
			cloned := Parsed_Struct {
				name   = strings.clone(s.name),
				fields = make([dynamic]Parsed_Field),
			}
			for f in s.fields {
				append(
					&cloned.fields,
					Parsed_Field {
						name = strings.clone(f.name),
						type_str = strings.clone(f.type_str),
					},
				)
			}

			ps := new(Parsed_Struct)
			ps.name = cloned.name
			ps.fields = make([dynamic]Parsed_Field)
			for f in cloned.fields {
				append(&ps.fields, f)
			}
			registry.structs[ps.name] = ps

			append(all_inferred, cloned)
		}

		for &s in inferred {
			delete(s.fields)
		}
		delete(inferred)
	}

	if len(data_type) == 0 {
		fmt.eprintfln("Warning: no type for %s, skipping", entry_path)
		return false
	}

	// Generate code
	e: Emitter
	emitter_init(&e)
	defer emitter_destroy(&e)

	g: Gen_Context
	gen_init(&g, registry, pkg_name, ohtml_import)
	defer gen_destroy(&g)

	generate_template(&g, &e, t, proc_name, data_type)

	_merge_helpers(all_helpers, &g.helpers)

	output := emitter_to_string(&e)
	wok := os.write_entire_file(out_file, transmute([]u8)output)
	if !wok {
		fmt.eprintfln("Error: could not write %s", out_file)
		return false
	}

	return true
}

// _apply_field_hints overrides inferred field types with @field hints.
// Hints are applied to the root struct (the last one, since children are appended first).
_apply_field_hints :: proc(
	registry: ^Type_Registry,
	inferred: ^[dynamic]Parsed_Struct,
	hints: map[string]string,
) {
	if len(hints) == 0 || len(inferred) == 0 {
		return
	}
	root := &inferred[len(inferred) - 1]
	for &f in root.fields {
		if hint, ok := hints[f.name]; ok {
			f.type_str = hint
		}
	}
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

_consume_flag :: proc(arg: string, prefix: string, out: ^string) -> bool {
	full_prefix := strings.concatenate({prefix, "="})
	defer delete(full_prefix)
	if strings.has_prefix(arg, full_prefix) {
		out^ = arg[len(full_prefix):]
		return true
	}
	return false
}

// ---------------------------------------------------------------------------
// Helpers file generation
// ---------------------------------------------------------------------------

_merge_helpers :: proc(dst: ^Helper_Flags, src: ^Helper_Flags) {
	if src.html_escape {dst.html_escape = true}
	if src.html_nospace_escape {dst.html_nospace_escape = true}
	if src.js_escape {dst.js_escape = true}
	if src.css_escape {dst.css_escape = true}
	if src.url_filter {dst.url_filter = true}
	if src.url_query_escape {dst.url_query_escape = true}
	if src.write_int {dst.write_int = true}
	if src.write_uint {dst.write_uint = true}
}

_emit_helpers_file :: proc(dest_dir: string, pkg_name: string, helpers: ^Helper_Flags) {
	// Check if any helpers are needed
	needs_helpers :=
		helpers.html_escape ||
		helpers.html_nospace_escape ||
		helpers.js_escape ||
		helpers.css_escape ||
		helpers.url_filter ||
		helpers.url_query_escape ||
		helpers.write_int ||
		helpers.write_uint
	if !needs_helpers {
		return
	}

	// Determine which shared constants are needed
	needs_hex_upper := helpers.js_escape || helpers.url_query_escape
	needs_hex_lower := helpers.css_escape || helpers.html_nospace_escape

	b := strings.builder_make_len_cap(0, 8192)
	defer strings.builder_destroy(&b)

	fmt.sbprintf(&b, "package %s\n\n", pkg_name)
	strings.write_string(&b, "import \"core:strings\"\n\n")

	// Shared hex digit tables
	if needs_hex_upper {
		strings.write_string(
			&b,
			"@(rodata)\nHEX_UPPER := [16]u8{'0','1','2','3','4','5','6','7','8','9','A','B','C','D','E','F'}\n\n",
		)
	}
	if needs_hex_lower {
		strings.write_string(
			&b,
			"@(rodata)\nHEX_LOWER := [16]u8{'0','1','2','3','4','5','6','7','8','9','a','b','c','d','e','f'}\n\n",
		)
	}

	if helpers.html_escape {
		strings.write_string(
			&b,
			`html_escape :: proc(s: string) -> string {
	for i in 0 ..< len(s) {
		switch s[i] {
		case '&', '<', '>', '"', '\'':
			return html_escape_slow(s, i)
		}
	}
	return s
}

@(private="file")
html_escape_slow :: proc(s: string, start: int) -> string {
	b: strings.Builder
	strings.builder_init_len_cap(&b, 0, len(s) + len(s) / 8)
	last := 0
	strings.write_string(&b, s[:start])
	last = start
	for i in start ..< len(s) {
		repl: string
		switch s[i] {
		case '&':  repl = "&amp;"
		case '<':  repl = "&lt;"
		case '>':  repl = "&gt;"
		case '"':  repl = "&#34;"
		case '\'': repl = "&#39;"
		case:      continue
		}
		strings.write_string(&b, s[last:i])
		strings.write_string(&b, repl)
		last = i + 1
	}
	strings.write_string(&b, s[last:])
	return strings.to_string(b)
}

`,
		)
	}

	if helpers.html_nospace_escape {
		strings.write_string(
			&b,
			"html_nospace_escape :: proc(s: string) -> string {\n" +
			"\tfor i in 0 ..< len(s) {\n" +
			"\t\tswitch s[i] {\n" +
			"\t\tcase '&', '<', '>', '\"', '\\'', '\\t', '\\n', '\\r', '\\f', ' ', '=', '`':\n" +
			"\t\t\treturn html_nospace_escape_slow(s, i)\n" +
			"\t\t}\n" +
			"\t}\n" +
			"\treturn s\n" +
			"}\n" +
			"\n" +
			"@(private=\"file\")\n" +
			"html_nospace_escape_slow :: proc(s: string, start: int) -> string {\n" +
			"\tb := strings.builder_make_len_cap(0, len(s) + len(s) / 8)\n" +
			"\tlast := start\n" +
			"\tstrings.write_string(&b, s[:start])\n" +
			"\tfor i in start ..< len(s) {\n" +
			"\t\trepl: string\n" +
			"\t\tswitch s[i] {\n" +
			"\t\tcase '&':  repl = \"&amp;\"\n" +
			"\t\tcase '<':  repl = \"&lt;\"\n" +
			"\t\tcase '>':  repl = \"&gt;\"\n" +
			"\t\tcase '\"':  repl = \"&#34;\"\n" +
			"\t\tcase '\\'': repl = \"&#39;\"\n" +
			"\t\tcase '\\t', '\\n', '\\r', '\\f', ' ':\n" +
			"\t\t\tstrings.write_string(&b, s[last:i])\n" +
			"\t\t\tn := int(s[i])\n" +
			"\t\t\tstrings.write_string(&b, \"&#x\")\n" +
			"\t\t\tstrings.write_byte(&b, HEX_LOWER[(n >> 4) & 0xf])\n" +
			"\t\t\tstrings.write_byte(&b, HEX_LOWER[n & 0xf])\n" +
			"\t\t\tstrings.write_byte(&b, ';')\n" +
			"\t\t\tlast = i + 1\n" +
			"\t\t\tcontinue\n" +
			"\t\tcase '=':  repl = \"&#61;\"\n" +
			"\t\tcase '`':  repl = \"&#96;\"\n" +
			"\t\tcase:      continue\n" +
			"\t\t}\n" +
			"\t\tstrings.write_string(&b, s[last:i])\n" +
			"\t\tstrings.write_string(&b, repl)\n" +
			"\t\tlast = i + 1\n" +
			"\t}\n" +
			"\tstrings.write_string(&b, s[last:])\n" +
			"\treturn strings.to_string(b)\n" +
			"}\n\n",
		)
	}

	if helpers.js_escape {
		strings.write_string(
			&b,
			`js_escape :: proc(s: string) -> string {
	for i in 0 ..< len(s) {
		switch s[i] {
		case '\\', '\'', '"', '<', '>', '&', '=', '\n', '\r', '\t', 0:
			return js_escape_slow(s, i)
		case:
			if s[i] < 0x20 { return js_escape_slow(s, i) }
		}
	}
	return s
}

@(private="file")
js_escape_slow :: proc(s: string, start: int) -> string {
	b: strings.Builder
	strings.builder_init_len_cap(&b, 0, len(s) + len(s) / 4)
	last := start
	strings.write_string(&b, s[:start])
	for i in start ..< len(s) {
		repl: string
		switch s[i] {
		case '\\': repl = "\\\\"
		case '\'': repl = "\\'"
		case '"':  repl = "\\\""
		case '<':  repl = "\\u003C"
		case '>':  repl = "\\u003E"
		case '&':  repl = "\\u0026"
		case '=':  repl = "\\u003D"
		case '\n': repl = "\\n"
		case '\r': repl = "\\r"
		case '\t': repl = "\\t"
		case 0:    repl = "\\u0000"
		case:
			if s[i] < 0x20 {
				strings.write_string(&b, s[last:i])
				n := int(s[i])
				strings.write_string(&b, "\\u")
				strings.write_byte(&b, HEX_UPPER[(n >> 12) & 0xf])
				strings.write_byte(&b, HEX_UPPER[(n >> 8) & 0xf])
				strings.write_byte(&b, HEX_UPPER[(n >> 4) & 0xf])
				strings.write_byte(&b, HEX_UPPER[n & 0xf])
				last = i + 1
			}
			continue
		}
		strings.write_string(&b, s[last:i])
		strings.write_string(&b, repl)
		last = i + 1
	}
	strings.write_string(&b, s[last:])
	return strings.to_string(b)
}

`,
		)
	}

	if helpers.css_escape {
		strings.write_string(
			&b,
			`css_escape :: proc(s: string) -> string {
	for i in 0 ..< len(s) {
		ch := s[i]
		if !((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9')) {
			return css_escape_slow(s, i)
		}
	}
	return s
}

@(private="file")
css_escape_slow :: proc(s: string, start: int) -> string {
	b: strings.Builder
	strings.builder_init_len_cap(&b, 0, len(s) * 2)
	strings.write_string(&b, s[:start])
	last := start
	for ch, i in s[start:] {
		idx := i + start
		if (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9') {
			continue
		}
		strings.write_string(&b, s[last:idx])
		n := int(ch)
		strings.write_byte(&b, '\\')
		strings.write_byte(&b, HEX_LOWER[(n >> 20) & 0xf])
		strings.write_byte(&b, HEX_LOWER[(n >> 16) & 0xf])
		strings.write_byte(&b, HEX_LOWER[(n >> 12) & 0xf])
		strings.write_byte(&b, HEX_LOWER[(n >> 8) & 0xf])
		strings.write_byte(&b, HEX_LOWER[(n >> 4) & 0xf])
		strings.write_byte(&b, HEX_LOWER[n & 0xf])
		rune_len := 1
		c := u32(ch)
		if c >= 0x80 { rune_len = 2 }
		if c >= 0x800 { rune_len = 3 }
		if c >= 0x10000 { rune_len = 4 }
		last = idx + rune_len
	}
	strings.write_string(&b, s[last:])
	return strings.to_string(b)
}

`,
		)
	}

	if helpers.url_filter {
		strings.write_string(
			&b,
			`url_filter :: proc(s: string) -> string {
	if url_is_safe(s) { return s }
	return "#ZodinAutoUrl"
}

@(private="file")
url_is_safe :: proc(s: string) -> bool {
	lo := proc(s: string, prefix: string) -> bool {
		if len(s) < len(prefix) { return false }
		for i in 0 ..< len(prefix) {
			c := s[i]
			if c >= 'A' && c <= 'Z' { c += 32 }
			if c != prefix[i] { return false }
		}
		return true
	}
	if lo(s, "javascript:") { return false }
	if lo(s, "vbscript:") { return false }
	if lo(s, "data:") {
		if lo(s, "data:image/") { return true }
		return false
	}
	return true
}

`,
		)
	}

	if helpers.url_query_escape {
		strings.write_string(
			&b,
			`url_query_escape :: proc(s: string) -> string {
	for i in 0 ..< len(s) {
		ch := s[i]
		is_safe := (ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z') ||
			(ch >= '0' && ch <= '9') || ch == '-' || ch == '_' || ch == '.' || ch == '~'
		if !is_safe { return url_query_escape_slow(s, i) }
	}
	return s
}

@(private="file")
url_query_escape_slow :: proc(s: string, start: int) -> string {
	b: strings.Builder
	strings.builder_init_len_cap(&b, 0, len(s) + len(s) / 2)
	last := start
	strings.write_string(&b, s[:start])
	for i in start ..< len(s) {
		ch := s[i]
		is_safe := (ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z') ||
			(ch >= '0' && ch <= '9') || ch == '-' || ch == '_' || ch == '.' || ch == '~'
		if is_safe {
			continue
		}
		strings.write_string(&b, s[last:i])
		strings.write_byte(&b, '%')
		strings.write_byte(&b, HEX_UPPER[ch >> 4])
		strings.write_byte(&b, HEX_UPPER[ch & 0xf])
		last = i + 1
	}
	strings.write_string(&b, s[last:])
	return strings.to_string(b)
}

`,
		)
	}

	if helpers.write_int {
		strings.write_string(
			&b,
			`write_int :: proc(buf: []u8, val: i64) -> string {
	if val == 0 {
		buf[len(buf) - 1] = '0'
		return string(buf[len(buf) - 1:])
	}
	neg := val < 0
	n := val if !neg else -val
	i := len(buf)
	for n > 0 {
		i -= 1
		buf[i] = u8('0' + n % 10)
		n /= 10
	}
	if neg {
		i -= 1
		buf[i] = '-'
	}
	return string(buf[i:])
}

`,
		)
	}

	if helpers.write_uint {
		strings.write_string(
			&b,
			`write_uint :: proc(buf: []u8, val: u64) -> string {
	if val == 0 {
		buf[len(buf) - 1] = '0'
		return string(buf[len(buf) - 1:])
	}
	n := val
	i := len(buf)
	for n > 0 {
		i -= 1
		buf[i] = u8('0' + n % 10)
		n /= 10
	}
	return string(buf[i:])
}

`,
		)
	}

	output := strings.to_string(b)
	path := _join_path(dest_dir, "helpers.odin")
	wok := os.write_entire_file(path, transmute([]u8)output)
	if !wok {
		fmt.eprintfln("Error: could not write %s", path)
	} else {
		fmt.printfln("  -> %s", path)
	}
}

_print_usage :: proc() {
	fmt.eprintln("Usage:")
	fmt.eprintln("  ohtml -src=<dir> -dest=<dir> [options]")
	fmt.eprintln()
	fmt.eprintln("Options:")
	fmt.eprintln("  -src=<dir>           Source directory containing .html template files")
	fmt.eprintln("  -dest=<dir>          Destination directory for generated .odin files")
	fmt.eprintln("  -struct-file=<file>  Odin source file with struct definitions (repeatable)")
	fmt.eprintln(
		"  -pkg=<name>          Package name for generated files (default: dest dir name)",
	)
	fmt.eprintln("  -ohtml-import=<path> Import path for ohtml package (default: \"ohtml:.\")")
}

Src_File :: struct {
	full_path: string,
	rel_path:  string,
}

// ---------------------------------------------------------------------------
// Type directive extraction
// ---------------------------------------------------------------------------

_extract_type_directive_from_source :: proc(src: string) -> string {
	MARKER :: "@type "
	idx := strings.index(src, MARKER)
	if idx < 0 {
		return ""
	}

	prefix := src[:idx]
	comment_start := strings.last_index(prefix, "/*")
	if comment_start < 0 {
		return ""
	}

	rest := src[idx + len(MARKER):]
	end := 0
	for end < len(rest) {
		ch := rest[end]
		if ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r' || ch == '*' {
			break
		}
		end += 1
	}
	if end == 0 {
		return ""
	}
	return rest[:end]
}

// ---------------------------------------------------------------------------
// File discovery
// ---------------------------------------------------------------------------

_find_html_files :: proc(dir: string) -> [dynamic]Src_File {
	files := make([dynamic]Src_File)
	dh, derr := os.open(dir)
	if derr != nil {
		return files
	}
	base_info, fierr := os.fstat(dh)
	os.close(dh)
	base_abs := base_info.fullpath if fierr == nil else dir
	_walk_dir(base_abs, dir, &files)
	if fierr == nil {
		os.file_info_delete(base_info)
	}
	return files
}

_walk_dir :: proc(base_dir: string, current_dir: string, files: ^[dynamic]Src_File) {
	dh, derr := os.open(current_dir)
	if derr != nil {
		return
	}
	defer os.close(dh)

	entries, _ := os.read_dir(dh, -1)
	defer os.file_info_slice_delete(entries)

	for entry in entries {
		full := entry.fullpath
		if entry.is_dir {
			_walk_dir(base_dir, full, files)
		} else if strings.has_suffix(entry.name, ".html") {
			rel := full
			if strings.has_prefix(full, base_dir) {
				rel = full[len(base_dir):]
			}
			if len(rel) > 0 && (rel[0] == '/' || rel[0] == '\\') {
				rel = rel[1:]
			}
			append(files, Src_File{full_path = strings.clone(full), rel_path = strings.clone(rel)})
		}
	}
}

// ---------------------------------------------------------------------------
// Path helpers
// ---------------------------------------------------------------------------

_proc_name_from_path :: proc(rel_path: string) -> string {
	name := _strip_ext(rel_path)
	return _proc_name_from_name(name)
}

_proc_name_from_name :: proc(name: string) -> string {
	b := strings.builder_make_len_cap(0, len(name) + 8)
	strings.write_string(&b, "render_")
	for ch in name {
		switch ch {
		case '/', '\\', '-', '.':
			strings.write_byte(&b, '_')
		case:
			strings.write_byte(&b, u8(ch))
		}
	}
	return strings.to_string(b)
}

_output_path :: proc(dest_dir: string, rel_path: string) -> string {
	name := _strip_ext(rel_path)
	return _output_path_from_name(dest_dir, name)
}

_output_path_from_name :: proc(dest_dir: string, name: string) -> string {
	b := strings.builder_make_len_cap(0, len(dest_dir) + len(name) + 8)
	strings.write_string(&b, dest_dir)
	if len(dest_dir) > 0 && dest_dir[len(dest_dir) - 1] != '/' {
		strings.write_byte(&b, '/')
	}
	for ch in name {
		switch ch {
		case '/', '\\', '-':
			strings.write_byte(&b, '_')
		case:
			strings.write_byte(&b, u8(ch))
		}
	}
	strings.write_string(&b, ".odin")
	return strings.to_string(b)
}

_strip_ext :: proc(path: string) -> string {
	dot := strings.last_index(path, ".")
	if dot < 0 {
		return path
	}
	return path[:dot]
}

_dir_name :: proc(path: string) -> string {
	p := strings.trim_right(path, "/\\")
	if slash := strings.last_index_any(p, "/\\"); slash >= 0 {
		return p[slash + 1:]
	}
	return p
}

_base_name :: proc(path: string) -> string {
	if slash := strings.last_index_any(path, "/\\"); slash >= 0 {
		return path[slash + 1:]
	}
	return path
}

_join_path :: proc(dir: string, file: string) -> string {
	if len(dir) == 0 || dir == "." {
		return file
	}
	b := strings.builder_make_len_cap(0, len(dir) + 1 + len(file))
	strings.write_string(&b, dir)
	if dir[len(dir) - 1] != '/' && dir[len(dir) - 1] != '\\' {
		strings.write_byte(&b, '/')
	}
	strings.write_string(&b, file)
	return strings.to_string(b)
}
