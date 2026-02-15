package cli

import "core:fmt"
import "core:os"
import "core:strings"

import ohtml "../"

// ---------------------------------------------------------------------------
// CLI — compile HTML templates to Odin source code
//
// Walks -src directory for .html files. Auto-detects layouts (files with
// {{block}}) vs pages (files with {{define}}) vs standalone templates.
// Pages are combined with their matching layout before code generation.
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
// Auto mode — walk src, classify files, match pages to layouts, generate
// ---------------------------------------------------------------------------

File_Kind :: enum {
	Standalone, // No {{block}} or {{define}} — self-contained template
	Layout, // Has {{block}} but no {{define}} — provides structure
	Page, // Has {{define}} — overrides layout blocks
}

Classified_File :: struct {
	src:          Src_File,
	kind:         File_Kind,
	block_names:  [dynamic]string,
	define_names: [dynamic]string,
	content:      []u8,
}

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

	// Classify all files
	classified := make([dynamic]Classified_File)
	defer {
		for &cf in classified {
			delete(cf.block_names)
			delete(cf.define_names)
			delete(cf.content)
		}
		delete(classified)
	}

	for file_info in html_files {
		cf, ok := _classify_file(file_info)
		if !ok {
			continue
		}
		append(&classified, cf)
	}

	// Separate into layouts, pages, standalones
	layouts: [dynamic]int
	pages: [dynamic]int
	standalones: [dynamic]int
	defer delete(layouts)
	defer delete(pages)
	defer delete(standalones)

	for cf, idx in classified {
		switch cf.kind {
		case .Layout:
			append(&layouts, idx)
		case .Page:
			append(&pages, idx)
		case .Standalone:
			append(&standalones, idx)
		}
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

	// Process pages — combine with matching layout
	for page_idx in pages {
		page := &classified[page_idx]
		layout_idx := _match_page_to_layout(page, classified[:], layouts[:])

		if layout_idx < 0 {
			fmt.eprintfln("Warning: no matching layout for %s, skipping", page.src.rel_path)
			errors += 1
			total += 1
			continue
		}

		layout := &classified[layout_idx]
		out_name := _strip_ext(page.src.rel_path)
		proc_name := _proc_name_from_name(out_name)
		out_file := _output_path_from_name(dest_dir, out_name)

		ok := _process_combined_template(
			layout.src.full_path,
			page.src.full_path,
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
			fmt.printfln(
				"  %s + %s -> %s (%s)",
				layout.src.rel_path,
				page.src.rel_path,
				out_file,
				proc_name,
			)
		}
	}

	// Process standalone templates
	for sa_idx in standalones {
		sa := &classified[sa_idx]
		ok := _process_template(
			sa.src.full_path,
			sa.src.rel_path,
			src_dir,
			dest_dir,
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
// File classification
// ---------------------------------------------------------------------------

_classify_file :: proc(file_info: Src_File) -> (Classified_File, bool) {
	content, ok := os.read_entire_file_from_filename(file_info.full_path)
	if !ok {
		fmt.eprintfln("Error: could not read %s", file_info.full_path)
		return {}, false
	}

	blocks, defines := _scan_template_names(string(content))

	kind: File_Kind
	if len(defines) > 0 {
		kind = .Page
	} else if len(blocks) > 0 {
		kind = .Layout
	} else {
		kind = .Standalone
	}

	return Classified_File {
			src = file_info,
			kind = kind,
			block_names = blocks,
			define_names = defines,
			content = content,
		},
		true
}

// _scan_template_names scans template source text for {{block "name"}} and
// {{define "name"}} directives. Skips raw string regions ({{`...`}}) to
// avoid false positives from display text.
_scan_template_names :: proc(src: string) -> (blocks: [dynamic]string, defines: [dynamic]string) {
	blocks = make([dynamic]string)
	defines = make([dynamic]string)

	i := 0
	for i < len(src) - 1 {
		// Look for {{
		if src[i] != '{' || src[i + 1] != '{' {
			i += 1
			continue
		}
		i += 2 // skip {{

		// Skip whitespace and trim markers
		for i < len(src) && (src[i] == ' ' || src[i] == '\t' || src[i] == '-') {
			i += 1
		}

		// Check for raw string: {{`...`}}
		if i < len(src) && src[i] == '`' {
			// Skip until `}}
			i += 1
			for i < len(src) - 2 {
				if src[i] == '`' && src[i + 1] == '}' && src[i + 2] == '}' {
					i += 3
					break
				}
				i += 1
			}
			continue
		}

		// Check for "block " or "define "
		is_block := false
		is_define := false
		if i + 6 <= len(src) && src[i:i + 6] == "block " {
			is_block = true
			i += 6
		} else if i + 7 <= len(src) && src[i:i + 7] == "define " {
			is_define = true
			i += 7
		} else {
			continue
		}

		// Skip whitespace
		for i < len(src) && (src[i] == ' ' || src[i] == '\t') {
			i += 1
		}

		// Extract quoted name
		if i >= len(src) || src[i] != '"' {
			continue
		}
		i += 1 // skip opening "
		name_start := i
		for i < len(src) && src[i] != '"' {
			i += 1
		}
		if i >= len(src) {
			continue
		}
		name := src[name_start:i]
		i += 1 // skip closing "

		if is_block {
			append(&blocks, name)
		} else if is_define {
			append(&defines, name)
		}
	}

	return
}

// _match_page_to_layout finds the best matching layout for a page by comparing
// define names against block names. Returns the index into classified, or -1.
_match_page_to_layout :: proc(
	page: ^Classified_File,
	classified: []Classified_File,
	layout_indices: []int,
) -> int {
	if len(layout_indices) == 0 {
		return -1
	}

	best_idx := -1
	best_score: f64 = 0

	for li in layout_indices {
		layout := &classified[li]
		if len(layout.block_names) == 0 {
			continue
		}

		// Count how many of the layout's blocks are defined by this page
		matches := 0
		for bn in layout.block_names {
			for dn in page.define_names {
				if bn == dn {
					matches += 1
					break
				}
			}
		}

		if matches == 0 {
			continue
		}

		// Score = fraction of layout blocks matched
		score := f64(matches) / f64(len(layout.block_names))
		if score > best_score {
			best_score = score
			best_idx = li
		}
	}

	return best_idx
}

_process_combined_template :: proc(
	layout_path: string,
	page_path: string,
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
	layout_bytes, lok := os.read_entire_file_from_filename(layout_path)
	if !lok {
		fmt.eprintfln("Error: could not read %s", layout_path)
		return false
	}
	defer delete(layout_bytes)

	page_bytes, pok := os.read_entire_file_from_filename(page_path)
	if !pok {
		fmt.eprintfln("Error: could not read %s", page_path)
		return false
	}
	defer delete(page_bytes)

	// Combine layout + page (same as interpreter's cache_load)
	combined := strings.concatenate({string(layout_bytes), string(page_bytes)})
	defer delete(combined)

	// Parse
	tmpl_name := _strip_ext(_base_name(page_path))
	t := ohtml.template_new(tmpl_name)
	defer ohtml.template_destroy(t)

	_, parse_err := ohtml.template_parse(t, combined)
	if parse_err.kind != .None {
		fmt.eprintfln("Parse error in %s + %s: %s", layout_path, page_path, parse_err.msg)
		if parse_err.msg != "" {delete(parse_err.msg)}
		return false
	}

	// Escape analysis
	esc_err := ohtml.escape_template(t)
	if esc_err.kind != .None {
		fmt.eprintfln("Escape error in %s + %s: %s", layout_path, page_path, esc_err.msg)
		if esc_err.msg != "" {delete(esc_err.msg)}
		return false
	}

	// Determine data type — use @type directive or inference
	data_type := _extract_type_directive_from_source(combined)

	if len(data_type) == 0 && use_inference {
		// Infer types from template field usage
		root_type, inferred := infer_from_template(t, template_name)

		// Apply @field hints from template source
		hints := extract_field_hints(combined)
		defer delete(hints)
		_apply_field_hints(registry, &inferred, hints)

		// Clone all strings — they point into template memory which will be freed
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

			// Add to registry
			ps := new(Parsed_Struct)
			ps.name = cloned.name
			ps.fields = make([dynamic]Parsed_Field)
			for f in cloned.fields {
				append(&ps.fields, f)
			}
			registry.structs[ps.name] = ps

			// Add to collected inferred types
			append(all_inferred, cloned)
		}

		// Clean up the original inferred data (points to template memory)
		for &s in inferred {
			delete(s.fields)
		}
		delete(inferred)
	}

	if len(data_type) == 0 {
		fmt.eprintfln("Warning: no type for %s + %s, skipping", layout_path, page_path)
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

	// Accumulate helper usage
	_merge_helpers(all_helpers, &g.helpers)

	// Write output
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
	// Root struct is the last one (children are built before parent in _build_struct_from_scope)
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
			"@(rodata)\n_HEX_UPPER := [16]u8{'0','1','2','3','4','5','6','7','8','9','A','B','C','D','E','F'}\n\n",
		)
	}
	if needs_hex_lower {
		strings.write_string(
			&b,
			"@(rodata)\n_HEX_LOWER := [16]u8{'0','1','2','3','4','5','6','7','8','9','a','b','c','d','e','f'}\n\n",
		)
	}

	if helpers.html_escape {
		strings.write_string(
			&b,
			`_ohtml_html_escape :: proc(s: string) -> string {
	for i in 0 ..< len(s) {
		switch s[i] {
		case '&', '<', '>', '"', '\'':
			return _html_escape_slow(s, i)
		}
	}
	return s
}

@(private="file")
_html_escape_slow :: proc(s: string, start: int) -> string {
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
			"_ohtml_html_nospace_escape :: proc(s: string) -> string {\n" +
			"\tfor i in 0 ..< len(s) {\n" +
			"\t\tswitch s[i] {\n" +
			"\t\tcase '&', '<', '>', '\"', '\\'', '\\t', '\\n', '\\r', '\\f', ' ', '=', '`':\n" +
			"\t\t\treturn _html_nospace_escape_slow(s, i)\n" +
			"\t\t}\n" +
			"\t}\n" +
			"\treturn s\n" +
			"}\n" +
			"\n" +
			"@(private=\"file\")\n" +
			"_html_nospace_escape_slow :: proc(s: string, start: int) -> string {\n" +
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
			"\t\t\tstrings.write_byte(&b, _HEX_LOWER[(n >> 4) & 0xf])\n" +
			"\t\t\tstrings.write_byte(&b, _HEX_LOWER[n & 0xf])\n" +
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
			`_ohtml_js_escape :: proc(s: string) -> string {
	for i in 0 ..< len(s) {
		switch s[i] {
		case '\\', '\'', '"', '<', '>', '&', '=', '\n', '\r', '\t', 0:
			return _js_escape_slow(s, i)
		case:
			if s[i] < 0x20 { return _js_escape_slow(s, i) }
		}
	}
	return s
}

@(private="file")
_js_escape_slow :: proc(s: string, start: int) -> string {
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
				strings.write_byte(&b, _HEX_UPPER[(n >> 12) & 0xf])
				strings.write_byte(&b, _HEX_UPPER[(n >> 8) & 0xf])
				strings.write_byte(&b, _HEX_UPPER[(n >> 4) & 0xf])
				strings.write_byte(&b, _HEX_UPPER[n & 0xf])
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
			`_ohtml_css_escape :: proc(s: string) -> string {
	for i in 0 ..< len(s) {
		ch := s[i]
		if !((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9')) {
			return _css_escape_slow(s, i)
		}
	}
	return s
}

@(private="file")
_css_escape_slow :: proc(s: string, start: int) -> string {
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
		strings.write_byte(&b, _HEX_LOWER[(n >> 20) & 0xf])
		strings.write_byte(&b, _HEX_LOWER[(n >> 16) & 0xf])
		strings.write_byte(&b, _HEX_LOWER[(n >> 12) & 0xf])
		strings.write_byte(&b, _HEX_LOWER[(n >> 8) & 0xf])
		strings.write_byte(&b, _HEX_LOWER[(n >> 4) & 0xf])
		strings.write_byte(&b, _HEX_LOWER[n & 0xf])
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
			`_ohtml_url_filter :: proc(s: string) -> string {
	if _url_is_safe(s) { return s }
	return "#ZodinAutoUrl"
}

@(private="file")
_url_is_safe :: proc(s: string) -> bool {
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
			`_ohtml_url_query_escape :: proc(s: string) -> string {
	for i in 0 ..< len(s) {
		ch := s[i]
		is_safe := (ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z') ||
			(ch >= '0' && ch <= '9') || ch == '-' || ch == '_' || ch == '.' || ch == '~'
		if !is_safe { return _url_query_escape_slow(s, i) }
	}
	return s
}

@(private="file")
_url_query_escape_slow :: proc(s: string, start: int) -> string {
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
		strings.write_byte(&b, _HEX_UPPER[ch >> 4])
		strings.write_byte(&b, _HEX_UPPER[ch & 0xf])
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
			`_ohtml_write_int :: proc(buf: []u8, val: i64) -> string {
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
			`_ohtml_write_uint :: proc(buf: []u8, val: u64) -> string {
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

// ---------------------------------------------------------------------------
// Template processing (auto mode)
// ---------------------------------------------------------------------------

Src_File :: struct {
	full_path: string,
	rel_path:  string,
}

_process_template :: proc(
	full_path: string,
	rel_path: string,
	src_dir: string,
	dest_dir: string,
	pkg_name: string,
	ohtml_import: string,
	registry: ^Type_Registry,
	use_inference: bool,
	all_inferred: ^[dynamic]Parsed_Struct,
	all_helpers: ^Helper_Flags,
) -> bool {
	src_bytes, ok := os.read_entire_file_from_filename(full_path)
	if !ok {
		fmt.eprintfln("Error: could not read %s", full_path)
		return false
	}
	src := string(src_bytes)
	defer delete(src_bytes)

	proc_name := _proc_name_from_path(rel_path)
	out_file := _output_path(dest_dir, rel_path)

	tmpl_name := _strip_ext(rel_path)
	t := ohtml.template_new(tmpl_name)
	defer ohtml.template_destroy(t)

	_, parse_err := ohtml.template_parse(t, src)
	if parse_err.kind != .None {
		fmt.eprintfln("Parse error in %s: %s", full_path, parse_err.msg)
		if parse_err.msg != "" {delete(parse_err.msg)}
		return false
	}

	esc_err := ohtml.escape_template(t)
	if esc_err.kind != .None {
		fmt.eprintfln("Escape error in %s: %s", full_path, esc_err.msg)
		if esc_err.msg != "" {delete(esc_err.msg)}
		return false
	}

	// Determine data type — use @type directive or inference
	data_type := _extract_type_directive_from_source(src)

	if len(data_type) == 0 && use_inference {
		root_type, inferred := infer_from_template(t, tmpl_name)

		hints := extract_field_hints(src)
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
		fmt.eprintfln("Warning: no @type directive in %s, skipping", full_path)
		return false
	}

	e: Emitter
	emitter_init(&e)
	defer emitter_destroy(&e)

	g: Gen_Context
	gen_init(&g, registry, pkg_name, ohtml_import)
	defer gen_destroy(&g)

	generate_template(&g, &e, t, proc_name, data_type)

	// Accumulate helper usage
	_merge_helpers(all_helpers, &g.helpers)

	output := emitter_to_string(&e)
	wok := os.write_entire_file(out_file, transmute([]u8)output)
	if !wok {
		fmt.eprintfln("Error: could not write %s", out_file)
		return false
	}

	fmt.printfln("  %s -> %s (%s)", rel_path, out_file, proc_name)
	return true
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
