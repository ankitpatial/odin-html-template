package ohtml

// ---------------------------------------------------------------------------
// Convenience top-level API
// ---------------------------------------------------------------------------

// render parses and executes a template in one call, with auto-escaping.
// Returns the rendered HTML string.
render :: proc(name: string, text: string, data: any) -> (string, Error) {
	t := template_new(name)
	defer template_destroy(t)

	_, parse_err := template_parse(t, text)
	if parse_err.kind != .None {
		return "", parse_err
	}

	// Run the auto-escaping pass.
	esc_err := escape_template(t)
	if esc_err.kind != .None {
		return "", esc_err
	}

	return execute_to_string(t, data)
}

// render_raw parses and executes a template without auto-escaping.
// Use this only for trusted templates — equivalent to Go's text/template.
render_raw :: proc(name: string, text: string, data: any) -> (string, Error) {
	t := template_new(name)
	defer template_destroy(t)

	_, parse_err := template_parse(t, text)
	if parse_err.kind != .None {
		return "", parse_err
	}

	return execute_to_string(t, data)
}
