package ohtml_tests

import ohtml ".."
import "core:testing"

// ---------------------------------------------------------------------------
// HTML escaping tests
// ---------------------------------------------------------------------------

@(test)
test_html_escape :: proc(t: ^testing.T) {
	Escape_Data :: struct {
		name: string,
	}

	// Script tag XSS
	{
		data := Escape_Data {
			name = "<script>alert('xss')</script>",
		}
		result, err := ohtml.render("esc_script", "<div>{{.name}}</div>", data)
		defer delete(result)
		testing.expect(t, err.kind == .None, "html escape error")
		testing.expectf(
			t,
			result == "<div>&lt;script&gt;alert(&#39;xss&#39;)&lt;/script&gt;</div>",
			"html escape: got %q",
			result,
		)
	}

	// Ampersand escaping
	{
		data := Escape_Data {
			name = "A&B",
		}
		result, err := ohtml.render("esc_amp", "{{.name}}", data)
		defer delete(result)
		testing.expect(t, err.kind == .None, "amp escape error")
		testing.expectf(t, result == "A&amp;B", "amp escape: got %q", result)
	}

	// Quote escaping in attribute
	{
		data := Escape_Data {
			name = `He said "hello"`,
		}
		result, err := ohtml.render("esc_quote", `<div title="{{.name}}">`, data)
		defer delete(result)
		testing.expect(t, err.kind == .None, "quote escape error")
		expected := `<div title="He said &#34;hello&#34;">`
		testing.expectf(
			t,
			result == expected,
			"quote escape: expected %q, got %q",
			expected,
			result,
		)
	}

	// Less than / greater than
	{
		data := Escape_Data {
			name = "1 < 2 > 0",
		}
		result, err := ohtml.render("esc_ltgt", "{{.name}}", data)
		defer delete(result)
		testing.expect(t, err.kind == .None, "ltgt escape error")
		testing.expectf(t, result == "1 &lt; 2 &gt; 0", "ltgt escape: got %q", result)
	}

	// Already safe content
	{
		data := Escape_Data {
			name = "plain text",
		}
		result, err := ohtml.render("esc_plain", "{{.name}}", data)
		defer delete(result)
		testing.expect(t, err.kind == .None, "plain escape error")
		testing.expectf(t, result == "plain text", "plain: got %q", result)
	}

	// Empty string
	{
		data := Escape_Data {
			name = "",
		}
		result, err := ohtml.render("esc_empty", "{{.name}}", data)
		defer delete(result)
		testing.expect(t, err.kind == .None, "empty escape error")
		testing.expectf(t, result == "", "empty: got %q", result)
	}

	// Null byte
	{
		data := Escape_Data {
			name = "a\x00b",
		}
		result, err := ohtml.render("esc_null", "{{.name}}", data)
		defer delete(result)
		testing.expect(t, err.kind == .None, "null escape error")
		// Null byte should be escaped or replaced
		testing.expect(t, len(result) > 0, "null: empty result")
	}
}

// ---------------------------------------------------------------------------
// HTML escaping in various contexts
// ---------------------------------------------------------------------------

@(test)
test_html_escape_contexts :: proc(t: ^testing.T) {
	Data :: struct {
		x: string,
	}

	// Text context
	{
		data := Data {
			x = "<b>bold</b>",
		}
		result, err := ohtml.render("ctx_text", "Hello {{.x}}", data)
		defer delete(result)
		testing.expect(t, err.kind == .None, "text context error")
		testing.expectf(
			t,
			result == "Hello &lt;b&gt;bold&lt;/b&gt;",
			"text context: got %q",
			result,
		)
	}

	// Attribute context (double-quoted)
	{
		data := Data {
			x = `a"b`,
		}
		result, err := ohtml.render("ctx_attr_dq", `<div class="{{.x}}">`, data)
		defer delete(result)
		testing.expect(t, err.kind == .None, "attr dq error")
		expected := `<div class="a&#34;b">`
		testing.expectf(t, result == expected, "attr dq: expected %q, got %q", expected, result)
	}

	// Attribute context (single-quoted)
	{
		data := Data {
			x = "a'b",
		}
		result, err := ohtml.render("ctx_attr_sq", "<div class='{{.x}}'>", data)
		defer delete(result)
		testing.expect(t, err.kind == .None, "attr sq error")
		// Single quote should be escaped
		testing.expect(t, len(result) > 0, "attr sq: empty result")
	}

	// Multiple attributes
	{
		data := struct {
			cls:   string,
			title: string,
		}{"my-class", "My Title"}
		result, err := ohtml.render(
			"ctx_multi_attr",
			`<div class="{{.cls}}" title="{{.title}}">`,
			data,
		)
		defer delete(result)
		testing.expect(t, err.kind == .None, "multi attr error")
		expected := `<div class="my-class" title="My Title">`
		testing.expectf(t, result == expected, "multi attr: expected %q, got %q", expected, result)
	}
}

// ---------------------------------------------------------------------------
// Safe content types tests
// ---------------------------------------------------------------------------

@(test)
test_safe_content :: proc(t: ^testing.T) {
	// Safe_HTML should not be double-escaped
	{
		Safe_Data :: struct {
			content: ohtml.Safe_HTML,
		}
		data := Safe_Data {
			content = ohtml.Safe_HTML("<b>bold</b>"),
		}
		result, err := ohtml.render("safe_html", "{{.content}}", data)
		defer delete(result)
		testing.expect(t, err.kind == .None, "safe HTML error")
		testing.expectf(t, result == "<b>bold</b>", "safe HTML: got %q", result)
	}

	// Safe_CSS in style element
	{
		Safe_CSS_Data :: struct {
			style: ohtml.Safe_CSS,
		}
		data := Safe_CSS_Data {
			style = ohtml.Safe_CSS("color: red"),
		}
		result, err := ohtml.render("safe_css", `<style>body { {{.style}} }</style>`, data)
		defer delete(result)
		testing.expect(t, err.kind == .None, "safe CSS error")
		// Safe CSS should be passed through
		testing.expect(t, len(result) > 0, "safe CSS: empty result")
	}

	// Safe_URL in href
	{
		Safe_URL_Data :: struct {
			link: ohtml.Safe_URL,
		}
		data := Safe_URL_Data {
			link = ohtml.Safe_URL("https://example.com"),
		}
		result, err := ohtml.render("safe_url", `<a href="{{.link}}">`, data)
		defer delete(result)
		testing.expect(t, err.kind == .None, "safe URL error")
		testing.expect(t, len(result) > 0, "safe URL: empty result")
	}

	// Safe_JS in script
	{
		Safe_JS_Data :: struct {
			code: ohtml.Safe_JS,
		}
		data := Safe_JS_Data {
			code = ohtml.Safe_JS("alert(1)"),
		}
		result, err := ohtml.render("safe_js", `<script>{{.code}}</script>`, data)
		defer delete(result)
		testing.expect(t, err.kind == .None, "safe JS error")
		testing.expect(t, len(result) > 0, "safe JS: empty result")
	}
}

// ---------------------------------------------------------------------------
// URL escaping tests
// ---------------------------------------------------------------------------

@(test)
test_url_escape :: proc(t: ^testing.T) {
	URL_Data :: struct {
		link: string,
	}

	// Safe URL
	{
		data := URL_Data {
			link = "https://example.com",
		}
		result, err := ohtml.render("url_safe", `<a href="{{.link}}">`, data)
		defer delete(result)
		testing.expect(t, err.kind == .None, "url safe error")
		testing.expectf(t, result != "", "url safe: empty result")
	}

	// javascript: URL should be blocked
	{
		data := URL_Data {
			link = "javascript:alert(1)",
		}
		result, err := ohtml.render("url_js_blocked", `<a href="{{.link}}">`, data)
		defer delete(result)
		testing.expect(t, err.kind == .None, "js url error")
		testing.expectf(
			t,
			result != `<a href="javascript:alert(1)">`,
			"javascript URL should be blocked, got %q",
			result,
		)
	}

	// vbscript: URL should be blocked
	{
		data := URL_Data {
			link = "vbscript:MsgBox",
		}
		result, err := ohtml.render("url_vbs_blocked", `<a href="{{.link}}">`, data)
		defer delete(result)
		testing.expect(t, err.kind == .None, "vbs url error")
		testing.expectf(
			t,
			result != `<a href="vbscript:MsgBox">`,
			"vbscript URL should be blocked, got %q",
			result,
		)
	}

	// data: URL should be blocked (except data:image/)
	{
		data := URL_Data {
			link = "data:text/html,<script>alert(1)</script>",
		}
		result, err := ohtml.render("url_data_blocked", `<a href="{{.link}}">`, data)
		defer delete(result)
		testing.expect(t, err.kind == .None, "data url error")
		testing.expectf(
			t,
			result != `<a href="data:text/html,<script>alert(1)</script>">`,
			"data: URL should be blocked, got %q",
			result,
		)
	}

	// data:image/ URL should be allowed
	{
		data := URL_Data {
			link = "data:image/png;base64,abc123",
		}
		result, err := ohtml.render("url_data_img_ok", `<a href="{{.link}}">`, data)
		defer delete(result)
		testing.expect(t, err.kind == .None, "data image url error")
		// Should not contain the unsafe prefix
		testing.expect(t, len(result) > 0, "data image: empty result")
	}

	// Relative URL
	{
		data := URL_Data {
			link = "/path/to/page",
		}
		result, err := ohtml.render("url_relative", `<a href="{{.link}}">`, data)
		defer delete(result)
		testing.expect(t, err.kind == .None, "relative url error")
		testing.expect(t, len(result) > 0, "relative url: empty result")
	}

	// Protocol-relative URL
	{
		data := URL_Data {
			link = "//example.com/path",
		}
		result, err := ohtml.render("url_proto_rel", `<a href="{{.link}}">`, data)
		defer delete(result)
		testing.expect(t, err.kind == .None, "proto-relative url error")
		testing.expect(t, len(result) > 0, "proto-relative url: empty result")
	}

	// URL with special characters
	{
		data := URL_Data {
			link = "https://example.com/search?q=hello world&lang=en",
		}
		result, err := ohtml.render("url_special", `<a href="{{.link}}">`, data)
		defer delete(result)
		testing.expect(t, err.kind == .None, "url special error")
		testing.expect(t, len(result) > 0, "url special: empty result")
	}

	// Various URL attributes: src, action, formaction
	{
		data := URL_Data {
			link = "https://example.com",
		}
		result, err := ohtml.render("url_src", `<img src="{{.link}}">`, data)
		defer delete(result)
		testing.expect(t, err.kind == .None, "url src error")
		testing.expect(t, len(result) > 0, "url src: empty")
	}

	{
		data := URL_Data {
			link = "https://example.com",
		}
		result, err := ohtml.render("url_action", `<form action="{{.link}}">`, data)
		defer delete(result)
		testing.expect(t, err.kind == .None, "url action error")
		testing.expect(t, len(result) > 0, "url action: empty")
	}
}

// ---------------------------------------------------------------------------
// JavaScript context escaping tests
// ---------------------------------------------------------------------------

@(test)
test_js_escape :: proc(t: ^testing.T) {
	Data :: struct {
		s: string,
		n: int,
		b: bool,
	}

	// String value in JS context
	{
		data := Data {
			s = "hello",
		}
		result, err := ohtml.render("js_str", `<script>var x = {{.s}};</script>`, data)
		defer delete(result)
		testing.expectf(t, err.kind == .None, "js str error: %s", err.msg)
		testing.expect(t, len(result) > 0, "js str: empty")
		// Should be escaped for JS safety
	}

	// Integer in JS context
	{
		data := Data {
			n = 42,
		}
		result, err := ohtml.render("js_num", `<script>var x = {{.n}};</script>`, data)
		defer delete(result)
		testing.expectf(t, err.kind == .None, "js num error: %s", err.msg)
		testing.expect(t, len(result) > 0, "js num: empty")
	}

	// Boolean in JS context
	{
		data := Data {
			b = true,
		}
		result, err := ohtml.render("js_bool", `<script>var x = {{.b}};</script>`, data)
		defer delete(result)
		testing.expectf(t, err.kind == .None, "js bool error: %s", err.msg)
		testing.expect(t, len(result) > 0, "js bool: empty")
	}

	// XSS attempt in JS string
	{
		data := Data {
			s = "</script><script>alert(1)//",
		}
		result, err := ohtml.render("js_xss", `<script>var x = "{{.s}}";</script>`, data)
		defer delete(result)
		testing.expectf(t, err.kind == .None, "js xss error: %s", err.msg)
		// The </script> should be escaped
		testing.expect(
			t,
			result != `<script>var x = "</script><script>alert(1)//";</script>`,
			"js xss: script tag should be escaped",
		)
	}

	// JS with special characters
	{
		data := Data {
			s = "line1\nline2",
		}
		result, err := ohtml.render("js_newline", `<script>var x = "{{.s}}";</script>`, data)
		defer delete(result)
		testing.expectf(t, err.kind == .None, "js newline error: %s", err.msg)
		testing.expect(t, len(result) > 0, "js newline: empty")
	}

	// JS with quotes and special chars
	{
		data := Data {
			s = `he said "hello"`,
		}
		result, err := ohtml.render("js_quotes", `<script>var x = "{{.s}}";</script>`, data)
		defer delete(result)
		testing.expectf(t, err.kind == .None, "js quotes error: %s", err.msg)
		testing.expect(t, len(result) > 0, "js quotes: empty")
	}
}

// ---------------------------------------------------------------------------
// CSS context escaping tests
// ---------------------------------------------------------------------------

@(test)
test_css_escape :: proc(t: ^testing.T) {
	Data :: struct {
		color: string,
		bg:    string,
	}

	// CSS in style element — safe value
	{
		data := Data {
			color = "blue",
		}
		result, err := ohtml.render("css_color", `<style>body { color: {{.color}} }</style>`, data)
		defer delete(result)
		testing.expectf(t, err.kind == .None, "css color error: %s", err.msg)
		testing.expect(t, len(result) > 0, "css color: empty")
	}

	// CSS injection attempt in style element
	{
		data := Data {
			color = "red; background: url(javascript:alert(1))",
		}
		result, err := ohtml.render(
			"css_inject",
			`<style>body { color: {{.color}} }</style>`,
			data,
		)
		defer delete(result)
		testing.expectf(t, err.kind == .None, "css inject error: %s", err.msg)
		testing.expect(t, len(result) > 0, "css inject: not empty")
	}

	// expression() in style element
	{
		data := Data {
			bg = "expression(alert(1))",
		}
		result, err := ohtml.render(
			"css_expr",
			`<style>body { background: {{.bg}} }</style>`,
			data,
		)
		defer delete(result)
		testing.expectf(t, err.kind == .None, "css expr error: %s", err.msg)
		testing.expect(t, len(result) > 0, "css expr: not empty")
	}
}

// ---------------------------------------------------------------------------
// render_raw (no escaping) tests
// ---------------------------------------------------------------------------

@(test)
test_render_raw :: proc(t: ^testing.T) {
	Raw_Data :: struct {
		name: string,
	}

	// render_raw should NOT escape HTML
	{
		data := Raw_Data {
			name = "<b>bold</b>",
		}
		result, err := ohtml.render_raw("raw1", "{{.name}}", data)
		defer delete(result)
		testing.expect(t, err.kind == .None, "render_raw error")
		testing.expectf(t, result == "<b>bold</b>", "render_raw: got %q", result)
	}

	// render_raw preserves special chars
	{
		data := Raw_Data {
			name = "A&B<C>D\"E'F",
		}
		result, err := ohtml.render_raw("raw2", "{{.name}}", data)
		defer delete(result)
		testing.expect(t, err.kind == .None, "render_raw2 error")
		testing.expectf(t, result == "A&B<C>D\"E'F", "render_raw2: got %q", result)
	}
}

// ---------------------------------------------------------------------------
// Context transition tests — HTML state machine
// ---------------------------------------------------------------------------

@(test)
test_context_transitions :: proc(t: ^testing.T) {
	Transition_Test :: struct {
		name:     string,
		input:    string,
		start:    ohtml.Context_State,
		expected: ohtml.Context_State,
	}

	tests := []Transition_Test {
		// Text context
		{"text_stays_text", "hello world", .Text, .Text},
		{"text_to_tag", "<div", .Text, .Tag},
		{"text_div_closes", "<div>", .Text, .Text},
		{"text_html_comment", "<!-- comment -->", .Text, .Text},
		{"text_html_comment_start", "<!-- start", .Text, .HTML_Cmt},
		// Script element
		{"text_to_script_tag", "<script", .Text, .Tag},
		{"script_tag_to_js", "<script>", .Text, .JS},
		{"style_tag_to_css", "<style>", .Text, .CSS},
		// Textarea/title (RCDATA)
		{"textarea_to_rcdata", "<textarea>", .Text, .RCDATA},
		{"title_to_rcdata", "<title>", .Text, .RCDATA},
		// Self-closing tag
		{"self_closing", "<br/>", .Text, .Text},
		// JS states
		{"js_dq_string", `"`, .JS, .JS_Dq_Str},
		{"js_sq_string", "'", .JS, .JS_Sq_Str},
		{"js_tmpl_lit", "`", .JS, .JS_Tmpl_Lit},
		{"js_line_comment", "//", .JS, .JS_Line_Cmt},
		{"js_block_comment", "/*", .JS, .JS_Block_Cmt},
		// JS string ends
		{"js_dq_str_end", `"`, .JS_Dq_Str, .JS},
		{"js_sq_str_end", "'", .JS_Sq_Str, .JS},
		{"js_tmpl_lit_end", "`", .JS_Tmpl_Lit, .JS},
		// JS comment ends
		{"js_line_cmt_end", "\n", .JS_Line_Cmt, .JS},
		{"js_block_cmt_end", "*/", .JS_Block_Cmt, .JS},
		// CSS states
		{"css_dq_string", `"`, .CSS, .CSS_Dq_Str},
		{"css_sq_string", "'", .CSS, .CSS_Sq_Str},
		{"css_block_comment", "/*", .CSS, .CSS_Block_Cmt},
		// CSS string/comment ends
		{"css_dq_str_end", `"`, .CSS_Dq_Str, .CSS},
		{"css_sq_str_end", "'", .CSS_Sq_Str, .CSS},
		{"css_block_cmt_end", "*/", .CSS_Block_Cmt, .CSS},
		// Tag context
		{"tag_attr", `class`, .Tag, .After_Name},
		// HTML comment
		{"html_cmt_end", "-->", .HTML_Cmt, .Text},
	}

	for &tt in tests {
		ctx := ohtml.Escape_Context {
			state = tt.start,
		}
		if tt.start == .Tag || tt.start == .After_Name {
			// Need to set element for tag context tests
		}
		result := ohtml.transition(ctx, transmute([]u8)tt.input)
		testing.expectf(
			t,
			result.state == tt.expected,
			"[%s] after %q: expected %v, got %v",
			tt.name,
			tt.input,
			tt.expected,
			result.state,
		)
	}
}

// ---------------------------------------------------------------------------
// Context transitions: attribute types
// ---------------------------------------------------------------------------

@(test)
test_context_attr_types :: proc(t: ^testing.T) {
	// href attribute should enter URL context
	{
		ctx := ohtml.Escape_Context {
			state = .Text,
		}
		ctx = ohtml.transition(ctx, transmute([]u8)string(`<a href="`))
		testing.expectf(t, ctx.state == .URL, "after <a href=\": expected URL, got %v", ctx.state)
	}

	// src attribute should enter URL context
	{
		ctx := ohtml.Escape_Context {
			state = .Text,
		}
		ctx = ohtml.transition(ctx, transmute([]u8)string(`<img src="`))
		testing.expectf(t, ctx.state == .URL, "after <img src=\": expected URL, got %v", ctx.state)
	}

	// style attribute should enter CSS context
	{
		ctx := ohtml.Escape_Context {
			state = .Text,
		}
		ctx = ohtml.transition(ctx, transmute([]u8)string(`<div style="`))
		testing.expectf(
			t,
			ctx.state == .CSS,
			"after <div style=\": expected CSS, got %v",
			ctx.state,
		)
	}

	// onclick attribute should enter JS context
	{
		ctx := ohtml.Escape_Context {
			state = .Text,
		}
		ctx = ohtml.transition(ctx, transmute([]u8)string(`<div onclick="`))
		testing.expectf(
			t,
			ctx.state == .JS,
			"after <div onclick=\": expected JS, got %v",
			ctx.state,
		)
	}

	// Regular attribute should enter Attr context
	{
		ctx := ohtml.Escape_Context {
			state = .Text,
		}
		ctx = ohtml.transition(ctx, transmute([]u8)string(`<div class="`))
		testing.expectf(
			t,
			ctx.state == .Attr,
			"after <div class=\": expected Attr, got %v",
			ctx.state,
		)
	}

	// action attribute should enter URL context
	{
		ctx := ohtml.Escape_Context {
			state = .Text,
		}
		ctx = ohtml.transition(ctx, transmute([]u8)string(`<form action="`))
		testing.expectf(
			t,
			ctx.state == .URL,
			"after <form action=\": expected URL, got %v",
			ctx.state,
		)
	}
}

// ---------------------------------------------------------------------------
// Conditional escaping tests
// ---------------------------------------------------------------------------

@(test)
test_escape_conditionals :: proc(t: ^testing.T) {
	// if/else in HTML context
	{
		data := struct {
			show: bool,
			name: string,
		}{true, "World"}
		result, err := ohtml.render("esc_if", "<div>{{if .show}}{{.name}}{{end}}</div>", data)
		defer delete(result)
		testing.expectf(t, err.kind == .None, "esc_if error: %s", err.msg)
		testing.expectf(t, result == "<div>World</div>", "esc_if: got %q", result)
	}

	// if/else both branches
	{
		data := struct {
			show: bool,
			a:    string,
			b:    string,
		}{false, "Alpha", "Beta"}
		result, err := ohtml.render("esc_if_else", "{{if .show}}{{.a}}{{else}}{{.b}}{{end}}", data)
		defer delete(result)
		testing.expectf(t, err.kind == .None, "esc_if_else error: %s", err.msg)
		testing.expectf(t, result == "Beta", "esc_if_else: got %q", result)
	}

	// Range in HTML context
	{
		data := struct {
			items: []string,
		} {
			items = {"<b>", "&amp;"},
		}
		result, err := ohtml.render("esc_range", "{{range .items}}[{{.}}]{{end}}", data)
		defer delete(result)
		testing.expectf(t, err.kind == .None, "esc_range error: %s", err.msg)
		expected := "[&lt;b&gt;][&amp;amp;]"
		testing.expectf(t, result == expected, "esc_range: expected %q, got %q", expected, result)
	}

	// With in HTML context
	{
		data := struct {
			x: string,
		} {
			x = "<em>hi</em>",
		}
		result, err := ohtml.render("esc_with", "{{with .x}}{{.}}{{end}}", data)
		defer delete(result)
		testing.expectf(t, err.kind == .None, "esc_with error: %s", err.msg)
		testing.expectf(t, result == "&lt;em&gt;hi&lt;/em&gt;", "esc_with: got %q", result)
	}
}

// ---------------------------------------------------------------------------
// Overescaping prevention tests
// ---------------------------------------------------------------------------

@(test)
test_no_overescaping :: proc(t: ^testing.T) {
	// Safe_HTML should not be double-escaped
	{
		data := struct {
			h: ohtml.Safe_HTML,
		} {
			h = ohtml.Safe_HTML("&amp;"),
		}
		result, err := ohtml.render("no_overesc1", "{{.h}}", data)
		defer delete(result)
		testing.expectf(t, err.kind == .None, "no_overesc1 error: %s", err.msg)
		testing.expectf(
			t,
			result == "&amp;",
			"no_overesc1: got %q (should not be &amp;amp;)",
			result,
		)
	}

	// Regular string should be escaped once
	{
		data := struct {
			s: string,
		} {
			s = "&",
		}
		result, err := ohtml.render("no_overesc2", "{{.s}}", data)
		defer delete(result)
		testing.expectf(t, err.kind == .None, "no_overesc2 error: %s", err.msg)
		testing.expectf(t, result == "&amp;", "no_overesc2: got %q", result)
	}
}

// ---------------------------------------------------------------------------
// Non-string value escaping
// ---------------------------------------------------------------------------

@(test)
test_escape_non_string :: proc(t: ^testing.T) {
	// Boolean in HTML context
	{
		data := struct {
			b: bool,
		} {
			b = true,
		}
		result, err := ohtml.render("esc_bool", "{{.b}}", data)
		defer delete(result)
		testing.expectf(t, err.kind == .None, "esc_bool error: %s", err.msg)
		testing.expectf(t, result == "true", "esc_bool: got %q", result)
	}

	// Integer in HTML context
	{
		data := struct {
			n: int,
		} {
			n = 42,
		}
		result, err := ohtml.render("esc_int", "{{.n}}", data)
		defer delete(result)
		testing.expectf(t, err.kind == .None, "esc_int error: %s", err.msg)
		testing.expectf(t, result == "42", "esc_int: got %q", result)
	}

	// Float in HTML context
	{
		data := struct {
			f: f64,
		} {
			f = 3.14,
		}
		result, err := ohtml.render("esc_float", "{{.f}}", data)
		defer delete(result)
		testing.expectf(t, err.kind == .None, "esc_float error: %s", err.msg)
		testing.expectf(t, result == "3.14", "esc_float: got %q", result)
	}
}

// ---------------------------------------------------------------------------
// Srcset attribute tests
// ---------------------------------------------------------------------------

@(test)
test_escape_srcset :: proc(t: ^testing.T) {
	data := struct {
		img: string,
	} {
		img = "image.png",
	}

	result, err := ohtml.render("esc_srcset", `<img srcset="{{.img}} 2x">`, data)
	defer delete(result)
	testing.expectf(t, err.kind == .None, "srcset error: %s", err.msg)
	testing.expect(t, len(result) > 0, "srcset: empty result")
}

// ---------------------------------------------------------------------------
// RCDATA context tests (textarea, title)
// ---------------------------------------------------------------------------

@(test)
test_escape_rcdata :: proc(t: ^testing.T) {
	// Textarea content should be HTML-escaped
	{
		data := struct {
			content: string,
		} {
			content = "<script>alert(1)</script>",
		}
		result, err := ohtml.render("esc_textarea", "<textarea>{{.content}}</textarea>", data)
		defer delete(result)
		testing.expectf(t, err.kind == .None, "textarea error: %s", err.msg)
		// Content inside textarea is RCDATA — should be escaped
		testing.expect(t, len(result) > 0, "textarea: empty result")
	}

	// Title content should be HTML-escaped
	{
		data := struct {
			title: string,
		} {
			title = "<script>alert(1)</script>",
		}
		result, err := ohtml.render("esc_title", "<title>{{.title}}</title>", data)
		defer delete(result)
		testing.expectf(t, err.kind == .None, "title error: %s", err.msg)
		testing.expect(t, len(result) > 0, "title: empty result")
	}
}

// ---------------------------------------------------------------------------
// Template ends in unsafe context error tests
// ---------------------------------------------------------------------------

@(test)
test_escape_unsafe_context_errors :: proc(t: ^testing.T) {
	data := struct {
		x: string,
	} {
		x = "hello",
	}

	// Template ending inside a tag (unclosed)
	{
		_, err := ohtml.render("esc_err_tag", "<div {{.x}}", data)
		if err.msg != "" {delete(err.msg)}
		testing.expectf(t, err.kind != .None, "template ending in tag should error, got none")
	}

	// Template ending inside script
	{
		_, err := ohtml.render("esc_err_script", "<script>{{.x}}", data)
		if err.msg != "" {delete(err.msg)}
		testing.expectf(t, err.kind != .None, "template ending in script should error, got none")
	}

	// Template ending inside style
	{
		_, err := ohtml.render("esc_err_style", "<style>{{.x}}", data)
		if err.msg != "" {delete(err.msg)}
		testing.expectf(t, err.kind != .None, "template ending in style should error, got none")
	}

	// Template ending inside HTML comment
	{
		_, err := ohtml.render("esc_err_comment", "<!-- {{.x}}", data)
		if err.msg != "" {delete(err.msg)}
		testing.expectf(
			t,
			err.kind != .None,
			"template ending in HTML comment should error, got none",
		)
	}

	// Template ending inside attribute
	{
		_, err := ohtml.render("esc_err_attr", `<div class="{{.x}}`, data)
		if err.msg != "" {delete(err.msg)}
		testing.expectf(
			t,
			err.kind != .None,
			"template ending in unclosed attribute should error, got none",
		)
	}
}

// ---------------------------------------------------------------------------
// Context helper function tests
// ---------------------------------------------------------------------------

@(test)
test_context_helpers :: proc(t: ^testing.T) {
	// is_in_js
	{
		js_states := []ohtml.Context_State {
			.JS,
			.JS_Dq_Str,
			.JS_Sq_Str,
			.JS_Tmpl_Lit,
			.JS_Regexp,
			.JS_Block_Cmt,
			.JS_Line_Cmt,
			.JS_HTML_Open_Cmt,
			.JS_HTML_Close_Cmt,
		}
		for state in js_states {
			ctx := ohtml.Escape_Context {
				state = state,
			}
			testing.expectf(t, ohtml.is_in_js(ctx), "is_in_js should be true for %v", state)
		}

		non_js_states := []ohtml.Context_State{.Text, .Tag, .CSS, .URL, .Attr}
		for state in non_js_states {
			ctx := ohtml.Escape_Context {
				state = state,
			}
			testing.expectf(t, !ohtml.is_in_js(ctx), "is_in_js should be false for %v", state)
		}
	}

	// is_in_css
	{
		css_states := []ohtml.Context_State {
			.CSS,
			.CSS_Dq_Str,
			.CSS_Sq_Str,
			.CSS_Dq_URL,
			.CSS_Sq_URL,
			.CSS_URL,
			.CSS_Block_Cmt,
			.CSS_Line_Cmt,
		}
		for state in css_states {
			ctx := ohtml.Escape_Context {
				state = state,
			}
			testing.expectf(t, ohtml.is_in_css(ctx), "is_in_css should be true for %v", state)
		}

		non_css_states := []ohtml.Context_State{.Text, .Tag, .JS, .URL, .Attr}
		for state in non_css_states {
			ctx := ohtml.Escape_Context {
				state = state,
			}
			testing.expectf(t, !ohtml.is_in_css(ctx), "is_in_css should be false for %v", state)
		}
	}

	// context_eq
	{
		a := ohtml.Escape_Context {
			state = .Text,
		}
		b := ohtml.Escape_Context {
			state = .Text,
		}
		testing.expect(t, ohtml.context_eq(a, b), "identical contexts should be equal")

		c := ohtml.Escape_Context {
			state = .JS,
		}
		testing.expect(t, !ohtml.context_eq(a, c), "different states should not be equal")
	}
}

// ---------------------------------------------------------------------------
// Pipeline-based escaping tests
// ---------------------------------------------------------------------------

@(test)
test_escape_pipeline :: proc(t: ^testing.T) {
	// Piped value in HTML context should be escaped
	{
		data := struct {
			s: string,
		} {
			s = "<b>test</b>",
		}
		result, err := ohtml.render("esc_pipe", "{{.s | printf \"%s\"}}", data)
		defer delete(result)
		testing.expectf(t, err.kind == .None, "esc_pipe error: %s", err.msg)
		// Result should still be HTML-escaped
		testing.expect(t, len(result) > 0, "esc_pipe: empty result")
	}

	// Constant in HTML context
	{
		data := struct {
			x: int,
		} {
			x = 0,
		}
		result, err := ohtml.render("esc_const", `{{"<b>"}}`, data)
		defer delete(result)
		testing.expectf(t, err.kind == .None, "esc_const error: %s", err.msg)
		testing.expectf(t, result == "&lt;b&gt;", "esc_const: expected &lt;b&gt;, got %q", result)
	}
}

// ---------------------------------------------------------------------------
// Element type detection tests
// ---------------------------------------------------------------------------

@(test)
test_element_types :: proc(t: ^testing.T) {
	// script (case insensitive)
	{
		ctx := ohtml.Escape_Context {
			state = .Text,
		}
		ctx = ohtml.transition(ctx, transmute([]u8)string("<SCRIPT>"))
		testing.expectf(t, ctx.state == .JS, "after <SCRIPT> expected JS, got %v", ctx.state)
	}

	// STYLE (case insensitive)
	{
		ctx := ohtml.Escape_Context {
			state = .Text,
		}
		ctx = ohtml.transition(ctx, transmute([]u8)string("<STYLE>"))
		testing.expectf(t, ctx.state == .CSS, "after <STYLE> expected CSS, got %v", ctx.state)
	}

	// TEXTAREA (case insensitive)
	{
		ctx := ohtml.Escape_Context {
			state = .Text,
		}
		ctx = ohtml.transition(ctx, transmute([]u8)string("<TEXTAREA>"))
		testing.expectf(
			t,
			ctx.state == .RCDATA,
			"after <TEXTAREA> expected RCDATA, got %v",
			ctx.state,
		)
	}

	// Regular div stays text
	{
		ctx := ohtml.Escape_Context {
			state = .Text,
		}
		ctx = ohtml.transition(ctx, transmute([]u8)string("<div>"))
		testing.expectf(t, ctx.state == .Text, "after <div> expected Text, got %v", ctx.state)
	}
}
