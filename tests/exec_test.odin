#+feature dynamic-literals

package ohtml_tests

import ohtml ".."
import "core:testing"

// ---------------------------------------------------------------------------
// Test data structures
// ---------------------------------------------------------------------------

Test_Data :: struct {
	title:  string,
	body:   string,
	show:   bool,
	count:  int,
	pi:     f64,
	items:  []string,
	nested: Nested_Data,
	m:      map[string]int,
	empty:  string,
	nums:   []int,
	big:    i64,
	small:  i8,
	u_val:  u32,
}

Nested_Data :: struct {
	x:     int,
	y:     string,
	inner: Inner_Data,
}

Inner_Data :: struct {
	z: int,
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Exec_Test :: struct {
	name:     string,
	template: string,
	expected: string,
}

_run_exec_tests :: proc(t: ^testing.T, data: any, tests: []Exec_Test) {
	for &tt in tests {
		tmpl := ohtml.template_new(tt.name)
		defer ohtml.template_destroy(tmpl)

		_, parse_err := ohtml.template_parse(tmpl, tt.template)
		testing.expectf(t, parse_err.kind == .None, "[%s] parse error: %s", tt.name, parse_err.msg)
		if parse_err.kind != .None {
			continue
		}

		result, exec_err := ohtml.execute_to_string(tmpl, data)
		defer delete(result)
		testing.expectf(t, exec_err.kind == .None, "[%s] exec error: %s", tt.name, exec_err.msg)
		testing.expectf(
			t,
			result == tt.expected,
			"[%s] expected %q, got %q",
			tt.name,
			tt.expected,
			result,
		)
	}
}

_run_raw_tests :: proc(t: ^testing.T, data: any, tests: []Exec_Test) {
	for &tt in tests {
		result, err := ohtml.render_raw(tt.name, tt.template, data)
		defer delete(result)
		testing.expectf(t, err.kind == .None, "[%s] error: %s", tt.name, err.msg)
		testing.expectf(
			t,
			result == tt.expected,
			"[%s] expected %q, got %q",
			tt.name,
			tt.expected,
			result,
		)
	}
}

// ---------------------------------------------------------------------------
// Basic execution tests
// ---------------------------------------------------------------------------

@(test)
test_exec_basic :: proc(t: ^testing.T) {
	data := Test_Data {
		title = "Hello",
		body = "World",
		show = true,
		count = 42,
		pi = 3.14,
		items = {"a", "b", "c"},
		nested = {x = 10, y = "nested", inner = {z = 99}},
		big = 9999999,
		small = 7,
		u_val = 255,
	}

	tests := []Exec_Test {
		// Plain text
		{"text_only", "hello world", "hello world"},
		{"empty_template", "", ""},
		// Dot field access
		{"dot_field", "{{.title}}", "Hello"},
		{"dot_field2", "{{.body}}", "World"},
		// Numbers
		{"int_field", "{{.count}}", "42"},
		{"i64_field", "{{.big}}", "9999999"},
		{"i8_field", "{{.small}}", "7"},
		{"u32_field", "{{.u_val}}", "255"},
		// Float
		{"float_field", "{{.pi}}", "3.14"},
		// Bool
		{"bool_field_true", "{{.show}}", "true"},
		{"bool_literal_true", "{{true}}", "true"},
		{"bool_literal_false", "{{false}}", "false"},
		// String literal
		{"string_literal", `{{"literal"}}`, "literal"},
		{"string_literal_empty", `{{""}}`, ""},
		// Int literal
		{"int_literal", "{{123}}", "123"},
		{"negative_literal", "{{-5}}", "-5"},
		// Mixed text and actions
		{"mixed", "<h1>{{.title}}</h1>", "<h1>Hello</h1>"},
		{"multi_field", "{{.title}} {{.body}}", "Hello World"},
		// Nested field access
		{"nested_x", "{{.nested.x}}", "10"},
		{"nested_y", "{{.nested.y}}", "nested"},
		{"deep_nested", "{{.nested.inner.z}}", "99"},
		// Nil value (empty string field)
		{"empty_string_field", "{{.empty}}", ""},
	}

	_run_raw_tests(t, data, tests[:])
}

// ---------------------------------------------------------------------------
// If/else tests
// ---------------------------------------------------------------------------

@(test)
test_exec_if :: proc(t: ^testing.T) {
	// Test with true condition
	{
		data := Test_Data {
			show  = true,
			title = "Yes",
		}
		tests := []Exec_Test {
			{"if_true", "{{if .show}}visible{{end}}", "visible"},
			{"if_true_with_text", "before{{if .show}}yes{{end}}after", "beforeyesafter"},
		}
		_run_raw_tests(t, data, tests[:])
	}

	// Test with false condition
	{
		data := Test_Data {
			show  = false,
			title = "No",
		}
		tests := []Exec_Test {
			{"if_false", "{{if .show}}visible{{end}}", ""},
			{"if_else", "{{if .show}}yes{{else}}no{{end}}", "no"},
		}
		_run_raw_tests(t, data, tests[:])
	}

	// If with different truthiness values
	{
		// Non-zero int is true
		data := Test_Data {
			count = 5,
		}
		tests := []Exec_Test{{"if_nonzero_int", "{{if .count}}yes{{else}}no{{end}}", "yes"}}
		_run_raw_tests(t, data, tests[:])
	}

	{
		// Zero int is false
		data := Test_Data {
			count = 0,
		}
		tests := []Exec_Test{{"if_zero_int", "{{if .count}}yes{{else}}no{{end}}", "no"}}
		_run_raw_tests(t, data, tests[:])
	}

	{
		// Non-empty string is true
		data := Test_Data {
			title = "x",
		}
		tests := []Exec_Test{{"if_nonempty_string", "{{if .title}}yes{{else}}no{{end}}", "yes"}}
		_run_raw_tests(t, data, tests[:])
	}

	{
		// Empty string is false
		data := Test_Data {
			title = "",
		}
		tests := []Exec_Test{{"if_empty_string", "{{if .title}}yes{{else}}no{{end}}", "no"}}
		_run_raw_tests(t, data, tests[:])
	}

	// If with literal values
	{
		data := Test_Data{}
		tests := []Exec_Test {
			{"if_true_literal", "{{if true}}yes{{end}}", "yes"},
			{"if_false_literal", "{{if false}}yes{{else}}no{{end}}", "no"},
			{"if_int_1", "{{if 1}}yes{{end}}", "yes"},
			{"if_int_0", "{{if 0}}yes{{else}}no{{end}}", "no"},
			{"if_string_nonempty", `{{if "x"}}yes{{end}}`, "yes"},
			{"if_string_empty", `{{if ""}}yes{{else}}no{{end}}`, "no"},
		}
		_run_raw_tests(t, data, tests[:])
	}

	// If/else if
	{
		data := struct {
			a: bool,
			b: bool,
		}{false, true}
		tests := []Exec_Test{{"if_else_if", "{{if .a}}A{{else if .b}}B{{else}}C{{end}}", "B"}}
		_run_raw_tests(t, data, tests[:])
	}

	// If/else if chain with first true
	{
		data := struct {
			a: bool,
			b: bool,
		}{true, true}
		tests := []Exec_Test {
			{"if_else_if_first_true", "{{if .a}}A{{else if .b}}B{{else}}C{{end}}", "A"},
		}
		_run_raw_tests(t, data, tests[:])
	}

	// If/else if chain fallthrough to else
	{
		data := struct {
			a: bool,
			b: bool,
		}{false, false}
		tests := []Exec_Test {
			{"if_else_if_fallthrough", "{{if .a}}A{{else if .b}}B{{else}}C{{end}}", "C"},
		}
		_run_raw_tests(t, data, tests[:])
	}
}

// ---------------------------------------------------------------------------
// Range tests
// ---------------------------------------------------------------------------

@(test)
test_exec_range :: proc(t: ^testing.T) {
	// Basic range over slice
	{
		data := Test_Data {
			items = {"x", "y", "z"},
		}
		tests := []Exec_Test{{"range_basic", "{{range .items}}[{{.}}]{{end}}", "[x][y][z]"}}
		_run_raw_tests(t, data, tests[:])
	}

	// Range else (empty)
	{
		data := Test_Data {
			items = {},
		}
		tests := []Exec_Test {
			{"range_else_empty", "{{range .items}}{{.}}{{else}}empty{{end}}", "empty"},
			{"range_no_else_empty", "{{range .items}}{{.}}{{end}}", ""},
		}
		_run_raw_tests(t, data, tests[:])
	}

	// Range over int slice
	{
		data := struct {
			nums: []int,
		} {
			nums = {10, 20, 30},
		}
		tests := []Exec_Test{{"range_ints", "{{range .nums}}{{.}} {{end}}", "10 20 30 "}}
		_run_raw_tests(t, data, tests[:])
	}

	// Range with variable
	{
		data := Test_Data {
			items = {"a", "b"},
		}
		result, err := ohtml.render_raw("range_var", "{{range $v := .items}}[{{$v}}]{{end}}", data)
		defer delete(result)
		testing.expectf(t, err.kind == .None, "range_var error: %s", err.msg)
		testing.expectf(t, result == "[a][b]", "range_var: got %q", result)
	}

	// Range with key-value variables
	{
		data := struct {
			m: map[string]int,
		}{}
		// Can't easily test map ordering, so test with a single-entry map
		m := map[string]int {
			"hello" = 42,
		}
		data.m = m
		defer delete(m)

		result, err := ohtml.render_raw(
			"range_kv",
			"{{range $k, $v := .m}}{{$k}}={{$v}}{{end}}",
			data,
		)
		defer delete(result)
		testing.expectf(t, err.kind == .None, "range_kv error: %s", err.msg)
		testing.expectf(t, result == "hello=42", "range_kv: got %q", result)
	}

	// Range over integer (Go 1.22+)
	{
		data := struct {
			n: int,
		} {
			n = 3,
		}
		result, err := ohtml.render_raw("range_int", "{{range .n}}{{.}} {{end}}", data)
		defer delete(result)
		testing.expectf(t, err.kind == .None, "range_int error: %s", err.msg)
		testing.expectf(t, result == "0 1 2 ", "range_int: got %q", result)
	}

	// Range over string (character iteration)
	{
		data := struct {
			s: string,
		} {
			s = "abc",
		}
		result, err := ohtml.render_raw("range_str", "{{range .s}}[{{.}}]{{end}}", data)
		defer delete(result)
		testing.expectf(t, err.kind == .None, "range_str error: %s", err.msg)
		// Characters are runes, printed as integers
		testing.expect(t, len(result) > 0, "range_str: empty result")
	}

	// Range with break
	{
		data := struct {
			items: []int,
		} {
			items = {1, 2, 3, 4, 5},
		}
		result, err := ohtml.render_raw(
			"range_break",
			"{{range .items}}{{if eq . 3}}{{break}}{{end}}{{.}} {{end}}",
			data,
		)
		defer delete(result)
		testing.expectf(t, err.kind == .None, "range_break error: %s", err.msg)
		testing.expectf(t, result == "1 2 ", "range_break: got %q", result)
	}

	// Range with continue
	{
		data := struct {
			items: []int,
		} {
			items = {1, 2, 3, 4},
		}
		result, err := ohtml.render_raw(
			"range_continue",
			"{{range .items}}{{if eq . 2}}{{continue}}{{end}}{{.}} {{end}}",
			data,
		)
		defer delete(result)
		testing.expectf(t, err.kind == .None, "range_continue error: %s", err.msg)
		testing.expectf(t, result == "1 3 4 ", "range_continue: got %q", result)
	}
}

// ---------------------------------------------------------------------------
// Pipeline tests
// ---------------------------------------------------------------------------

@(test)
test_exec_pipeline :: proc(t: ^testing.T) {
	data := Test_Data {
		title = "hello",
		count = 5,
		items = {"a", "b", "c"},
	}

	tests := []Exec_Test {
		// Pipe to builtin function
		{"pipe_len", "{{.title | len}}", "5"},
		{"pipe_len_slice", "{{.items | len}}", "3"},
		// printf
		{"printf", `{{printf "%s!" .title}}`, "hello!"},
		{"printf_int", `{{printf "%d" .count}}`, "5"},
		// Multi-pipe
		{"multi_pipe", `{{.title | printf "%s!"}}`, "hello!"},
	}

	_run_raw_tests(t, data, tests[:])
}

// ---------------------------------------------------------------------------
// Variable tests
// ---------------------------------------------------------------------------

@(test)
test_exec_variables :: proc(t: ^testing.T) {
	data := Test_Data {
		title = "test",
		count = 7,
	}

	tests := []Exec_Test {
		// Variable declaration and use
		{"var_decl", "{{$x := .title}}{{$x}}", "test"},
		{"var_decl_int", "{{$n := .count}}{{$n}}", "7"},
		// Dollar is the original data
		{"dollar", "{{$}}", data.title}, // $ is the whole data, will print struct
	}

	// Test $x := field, then use
	{
		result, err := ohtml.render_raw("var_use", "{{$x := .title}}val={{$x}}", data)
		defer delete(result)
		testing.expectf(t, err.kind == .None, "var_use error: %s", err.msg)
		testing.expectf(t, result == "val=test", "var_use: got %q", result)
	}

	// Variable in if
	{
		result, err := ohtml.render_raw("var_in_if", "{{$x := .count}}{{if $x}}yes{{end}}", data)
		defer delete(result)
		testing.expectf(t, err.kind == .None, "var_in_if error: %s", err.msg)
		testing.expectf(t, result == "yes", "var_in_if: got %q", result)
	}
}

// ---------------------------------------------------------------------------
// With tests
// ---------------------------------------------------------------------------

@(test)
test_exec_with :: proc(t: ^testing.T) {
	// With changes dot
	{
		data := Test_Data {
			nested = {x = 42, y = "inner"},
		}
		tests := []Exec_Test {
			{"with_field", "{{with .nested}}{{.y}}{{end}}", "inner"},
			{"with_int", "{{with .nested}}{{.x}}{{end}}", "42"},
		}
		_run_raw_tests(t, data, tests[:])
	}

	// With true/false
	{
		data := struct {
			val: int,
		} {
			val = 5,
		}
		tests := []Exec_Test{{"with_true", "{{with .val}}yes:{{.}}{{end}}", "yes:5"}}
		_run_raw_tests(t, data, tests[:])
	}

	{
		data := struct {
			val: int,
		} {
			val = 0,
		}
		tests := []Exec_Test{{"with_false", "{{with .val}}yes{{else}}no{{end}}", "no"}}
		_run_raw_tests(t, data, tests[:])
	}

	// With string
	{
		data := struct {
			s: string,
		} {
			s = "hello",
		}
		tests := []Exec_Test{{"with_string", "{{with .s}}[{{.}}]{{end}}", "[hello]"}}
		_run_raw_tests(t, data, tests[:])
	}

	{
		data := struct {
			s: string,
		} {
			s = "",
		}
		tests := []Exec_Test{{"with_empty_string", "{{with .s}}yes{{else}}no{{end}}", "no"}}
		_run_raw_tests(t, data, tests[:])
	}

	// With else with chain
	{
		data := struct {
			a: int,
			b: int,
		} {
			a = 0,
			b = 5,
		}
		result, err := ohtml.render_raw(
			"with_else_with",
			"{{with .a}}A={{.}}{{else with .b}}B={{.}}{{end}}",
			data,
		)
		defer delete(result)
		testing.expectf(t, err.kind == .None, "with_else_with error: %s", err.msg)
		testing.expectf(t, result == "B=5", "with_else_with: got %q", result)
	}
}

// ---------------------------------------------------------------------------
// Comparison function tests
// ---------------------------------------------------------------------------

@(test)
test_exec_comparison :: proc(t: ^testing.T) {
	// Integer comparisons
	{
		data := Test_Data {
			count = 5,
		}
		tests := []Exec_Test {
			{"eq_true", "{{if eq .count 5}}yes{{end}}", "yes"},
			{"eq_false", "{{if eq .count 3}}yes{{else}}no{{end}}", "no"},
			{"ne_true", "{{if ne .count 3}}yes{{end}}", "yes"},
			{"ne_false", "{{if ne .count 5}}yes{{else}}no{{end}}", "no"},
			{"lt_true", "{{if lt .count 10}}yes{{end}}", "yes"},
			{"lt_false", "{{if lt .count 3}}yes{{else}}no{{end}}", "no"},
			{"le_true_less", "{{if le .count 10}}yes{{end}}", "yes"},
			{"le_true_equal", "{{if le .count 5}}yes{{end}}", "yes"},
			{"le_false", "{{if le .count 3}}yes{{else}}no{{end}}", "no"},
			{"gt_true", "{{if gt .count 3}}yes{{end}}", "yes"},
			{"gt_false", "{{if gt .count 10}}yes{{else}}no{{end}}", "no"},
			{"ge_true_greater", "{{if ge .count 3}}yes{{end}}", "yes"},
			{"ge_true_equal", "{{if ge .count 5}}yes{{end}}", "yes"},
			{"ge_false", "{{if ge .count 10}}yes{{else}}no{{end}}", "no"},
		}
		_run_raw_tests(t, data, tests[:])
	}

	// String comparisons
	{
		data := struct {
			s: string,
		} {
			s = "hello",
		}
		tests := []Exec_Test {
			{"eq_string_true", `{{if eq .s "hello"}}yes{{end}}`, "yes"},
			{"eq_string_false", `{{if eq .s "world"}}yes{{else}}no{{end}}`, "no"},
			{"ne_string", `{{if ne .s "world"}}yes{{end}}`, "yes"},
			{"lt_string", `{{if lt .s "world"}}yes{{end}}`, "yes"},
			{"gt_string", `{{if gt .s "abc"}}yes{{end}}`, "yes"},
		}
		_run_raw_tests(t, data, tests[:])
	}

	// Bool comparisons
	{
		data := struct {
			b: bool,
		} {
			b = true,
		}
		tests := []Exec_Test {
			{"eq_bool_true", "{{if eq .b true}}yes{{end}}", "yes"},
			{"eq_bool_false", "{{if eq .b false}}yes{{else}}no{{end}}", "no"},
		}
		_run_raw_tests(t, data, tests[:])
	}

	// Multi-arg eq (eq arg1 arg2 arg3 ... = arg1==arg2 || arg1==arg3 ...)
	{
		data := struct {
			n: int,
		} {
			n = 3,
		}
		tests := []Exec_Test {
			{"eq_multi_match", "{{if eq .n 1 2 3}}yes{{end}}", "yes"},
			{"eq_multi_no_match", "{{if eq .n 1 2 4}}yes{{else}}no{{end}}", "no"},
		}
		_run_raw_tests(t, data, tests[:])
	}
}

// ---------------------------------------------------------------------------
// Boolean logic functions: and, or, not
// ---------------------------------------------------------------------------

@(test)
test_exec_boolean_logic :: proc(t: ^testing.T) {
	data := struct {
		t_val: bool,
		f_val: bool,
		one:   int,
		zero:  int,
		s:     string,
	}{true, false, 1, 0, "hello"}

	tests := []Exec_Test {
		// not
		{"not_true", "{{not .t_val}}", "false"},
		{"not_false", "{{not .f_val}}", "true"},
		// and — returns first falsy or last arg
		{"and_true_true", "{{if and .t_val .one}}yes{{end}}", "yes"},
		{"and_true_false", "{{if and .t_val .f_val}}yes{{else}}no{{end}}", "no"},
		{"and_false_true", "{{if and .f_val .t_val}}yes{{else}}no{{end}}", "no"},
		// or — returns first truthy or last arg
		{"or_true_false", "{{if or .t_val .f_val}}yes{{end}}", "yes"},
		{"or_false_true", "{{if or .f_val .t_val}}yes{{end}}", "yes"},
		{"or_false_false", "{{if or .f_val .zero}}yes{{else}}no{{end}}", "no"},
		// Short circuit: and returns first falsy
		{"and_short_circuit", "{{if and .f_val .t_val}}yes{{else}}no{{end}}", "no"},
		// or returns first truthy
		{"or_short_circuit", "{{if or .t_val .f_val}}yes{{end}}", "yes"},
	}

	_run_raw_tests(t, data, tests[:])
}

// ---------------------------------------------------------------------------
// Print / Printf / Println tests
// ---------------------------------------------------------------------------

@(test)
test_exec_print_functions :: proc(t: ^testing.T) {
	data := struct {
		name:  string,
		count: int,
		pi:    f64,
		flag:  bool,
	}{"world", 42, 3.14, true}

	tests := []Exec_Test {
		// print
		{"print_string", `{{print .name}}`, "world"},
		{"print_int", `{{print .count}}`, "42"},
		{"print_multi", `{{print .name .count}}`, "world 42"},
		// printf
		{"printf_s", `{{printf "%s" .name}}`, "world"},
		{"printf_d", `{{printf "%d" .count}}`, "42"},
		{"printf_combo", `{{printf "%s=%d" .name .count}}`, "world=42"},
		{"printf_percent", `{{printf "100%%"}}`, "100%"},
		// println
		{"println_single", `{{println .name}}`, "world\n"},
		{"println_multi", `{{println .name .count}}`, "world 42\n"},
	}

	_run_raw_tests(t, data, tests[:])
}

// ---------------------------------------------------------------------------
// Len function tests
// ---------------------------------------------------------------------------

@(test)
test_exec_len :: proc(t: ^testing.T) {
	data := struct {
		s:     string,
		items: []int,
		m:     map[string]int,
	} {
		s     = "hello",
		items = {1, 2, 3},
	}
	m := map[string]int {
		"a" = 1,
		"b" = 2,
	}
	data.m = m
	defer delete(m)

	tests := []Exec_Test {
		{"len_string", "{{len .s}}", "5"},
		{"len_slice", "{{len .items}}", "3"},
		{"len_map", "{{len .m}}", "2"},
		{"len_empty_string", `{{len ""}}`, "0"},
	}

	_run_raw_tests(t, data, tests[:])
}

// ---------------------------------------------------------------------------
// Index function tests
// ---------------------------------------------------------------------------

@(test)
test_exec_index :: proc(t: ^testing.T) {
	// Index into slice
	{
		data := struct {
			items: []string,
		} {
			items = {"a", "b", "c"},
		}
		tests := []Exec_Test {
			{"index_0", `{{index .items 0}}`, "a"},
			{"index_1", `{{index .items 1}}`, "b"},
			{"index_2", `{{index .items 2}}`, "c"},
		}
		_run_raw_tests(t, data, tests[:])
	}

	// Index into map
	{
		data := struct {
			m: map[string]int,
		}{}
		m := map[string]int {
			"one"   = 1,
			"two"   = 2,
			"three" = 3,
		}
		data.m = m
		defer delete(m)

		tests := []Exec_Test {
			{"index_map_one", `{{index .m "one"}}`, "1"},
			{"index_map_two", `{{index .m "two"}}`, "2"},
		}
		_run_raw_tests(t, data, tests[:])
	}

	// Index out of range should error
	{
		data := struct {
			items: []string,
		} {
			items = {"a"},
		}
		tmpl := ohtml.template_new("index_oor")
		defer ohtml.template_destroy(tmpl)
		ohtml.template_parse(tmpl, "{{index .items 5}}")
		_, err := ohtml.execute_to_string(tmpl, data)
		testing.expect(t, err.kind != .None, "index out of range should error")
		if err.msg != "" {delete(err.msg)}
	}
}

// ---------------------------------------------------------------------------
// Map access via field syntax
// ---------------------------------------------------------------------------

@(test)
test_exec_map_field :: proc(t: ^testing.T) {
	data := struct {
		m: map[string]int,
	}{}
	m := map[string]int {
		"x" = 10,
		"y" = 20,
	}
	data.m = m
	defer delete(m)

	tests := []Exec_Test{{"map_field_x", "{{.m.x}}", "10"}, {"map_field_y", "{{.m.y}}", "20"}}

	_run_raw_tests(t, data, tests[:])
}

// ---------------------------------------------------------------------------
// Template call tests
// ---------------------------------------------------------------------------

@(test)
test_exec_template_call :: proc(t: ^testing.T) {
	// Basic template call with data
	{
		data := Test_Data {
			title = "Main",
		}

		tmpl := ohtml.template_new("main")
		defer ohtml.template_destroy(tmpl)
		ohtml.template_parse(tmpl, `{{define "greet"}}Hi {{.title}}{{end}}{{template "greet" .}}`)
		result, err := ohtml.execute_to_string(tmpl, data)
		defer delete(result)
		testing.expect(t, err.kind == .None, "template_call exec error")
		testing.expectf(t, result == "Hi Main", "template_call: got %q", result)
	}

	// Template call without data
	{
		tmpl := ohtml.template_new("nodata")
		defer ohtml.template_destroy(tmpl)
		ohtml.template_parse(tmpl, `{{define "static"}}hello world{{end}}{{template "static"}}`)
		result, err := ohtml.execute_to_string(tmpl, nil)
		defer delete(result)
		testing.expect(t, err.kind == .None, "template_nodata exec error")
		testing.expectf(t, result == "hello world", "template_nodata: got %q", result)
	}

	// Multiple defines
	{
		data := struct {
			name: string,
		}{"Test"}

		tmpl := ohtml.template_new("multi")
		defer ohtml.template_destroy(tmpl)
		ohtml.template_parse(
			tmpl,
			`{{define "a"}}A:{{.name}}{{end}}{{define "b"}}B:{{.name}}{{end}}{{template "a" .}}/{{template "b" .}}`,
		)
		result, err := ohtml.execute_to_string(tmpl, data)
		defer delete(result)
		testing.expect(t, err.kind == .None, "multi_define exec error")
		testing.expectf(t, result == "A:Test/B:Test", "multi_define: got %q", result)
	}
}

// ---------------------------------------------------------------------------
// Block tests
// ---------------------------------------------------------------------------

@(test)
test_exec_block :: proc(t: ^testing.T) {
	// Block provides default content
	{
		data := struct {
			name: string,
		}{"World"}

		tmpl := ohtml.template_new("blk")
		defer ohtml.template_destroy(tmpl)
		ohtml.template_parse(tmpl, `{{block "greeting" .}}Hello {{.name}}{{end}}`)
		result, err := ohtml.execute_to_string(tmpl, data)
		defer delete(result)
		testing.expect(t, err.kind == .None, "block exec error")
		testing.expectf(t, result == "Hello World", "block: got %q", result)
	}
}

// ---------------------------------------------------------------------------
// Custom function tests
// ---------------------------------------------------------------------------

@(test)
test_exec_custom_funcs :: proc(t: ^testing.T) {
	data := struct {
		name: string,
	}{"world"}

	tmpl := ohtml.template_new("custom")
	defer ohtml.template_destroy(tmpl)

	// Register a custom function
	fm: ohtml.Func_Map
	fm["upper"] = proc(args: []any) -> (any, ohtml.Error) {
		if len(args) != 1 {
			return nil, ohtml.Error{kind = .Wrong_Arg_Count, msg = "upper requires 1 arg"}
		}
		s := ohtml.sprint_value(args[0])
		// Simple ASCII upper (for test only)
		buf := make([]u8, len(s))
		for i in 0 ..< len(s) {
			c := s[i]
			if c >= 'a' && c <= 'z' {
				c -= 32
			}
			buf[i] = c
		}
		return ohtml.box_string(string(buf)), {}
	}
	ohtml.template_funcs(tmpl, fm)
	ohtml.template_parse(tmpl, "{{.name | upper}}")

	result, err := ohtml.execute_to_string(tmpl, data)
	defer delete(result)
	testing.expectf(t, err.kind == .None, "custom func error: %s", err.msg)
	testing.expectf(t, result == "WORLD", "custom func: got %q", result)
}

// ---------------------------------------------------------------------------
// HTML/JS/urlquery builtin function tests
// ---------------------------------------------------------------------------

@(test)
test_exec_escape_builtins :: proc(t: ^testing.T) {
	data := struct {
		s: string,
	} {
		s = "<script>alert('xss')</script>",
	}

	// html builtin
	{
		result, err := ohtml.render_raw("html_builtin", "{{html .s}}", data)
		defer delete(result)
		testing.expectf(t, err.kind == .None, "html builtin error: %s", err.msg)
		testing.expect(t, result != data.s, "html builtin should escape the string")
	}

	// js builtin
	{
		result, err := ohtml.render_raw("js_builtin", "{{js .s}}", data)
		defer delete(result)
		testing.expectf(t, err.kind == .None, "js builtin error: %s", err.msg)
		testing.expect(t, result != data.s, "js builtin should escape the string")
	}

	// urlquery builtin
	{
		data2 := struct {
			s: string,
		} {
			s = "hello world&foo=bar",
		}
		result, err := ohtml.render_raw("urlquery_builtin", "{{urlquery .s}}", data2)
		defer delete(result)
		testing.expectf(t, err.kind == .None, "urlquery builtin error: %s", err.msg)
		testing.expect(t, result != data2.s, "urlquery builtin should encode the string")
	}
}

// ---------------------------------------------------------------------------
// Nested template and complex scenarios
// ---------------------------------------------------------------------------

@(test)
test_exec_complex :: proc(t: ^testing.T) {
	// Simulated page rendering
	{
		data := struct {
			title:    string,
			items:    []string,
			show_nav: bool,
		} {
			title    = "Test Page",
			items    = {"Item 1", "Item 2", "Item 3"},
			show_nav = true,
		}

		tmpl_text := `<html><head><title>{{.title}}</title></head><body>{{if .show_nav}}<nav>NAV</nav>{{end}}<ul>{{range .items}}<li>{{.}}</li>{{end}}</ul></body></html>`
		result, err := ohtml.render_raw("complex_page", tmpl_text, data)
		defer delete(result)
		testing.expectf(t, err.kind == .None, "complex_page error: %s", err.msg)
		expected := "<html><head><title>Test Page</title></head><body><nav>NAV</nav><ul><li>Item 1</li><li>Item 2</li><li>Item 3</li></ul></body></html>"
		testing.expectf(t, result == expected, "complex_page: got %q", result)
	}

	// If inside range
	{
		data := struct {
			items: []int,
		} {
			items = {1, 2, 3, 4, 5},
		}
		result, err := ohtml.render_raw(
			"if_in_range",
			"{{range .items}}{{if gt . 3}}[{{.}}]{{end}}{{end}}",
			data,
		)
		defer delete(result)
		testing.expectf(t, err.kind == .None, "if_in_range error: %s", err.msg)
		testing.expectf(t, result == "[4][5]", "if_in_range: got %q", result)
	}

	// Variable assignment in range
	{
		data := struct {
			items: []int,
		} {
			items = {10, 20, 30},
		}
		result, err := ohtml.render_raw(
			"var_in_range",
			"{{range $v := .items}}({{$v}}){{end}}",
			data,
		)
		defer delete(result)
		testing.expectf(t, err.kind == .None, "var_in_range error: %s", err.msg)
		testing.expectf(t, result == "(10)(20)(30)", "var_in_range: got %q", result)
	}
}

// ---------------------------------------------------------------------------
// Execution error tests
// ---------------------------------------------------------------------------

@(test)
test_exec_errors :: proc(t: ^testing.T) {
	Exec_Error_Test :: struct {
		name:     string,
		template: string,
		data:     any,
	}

	// Missing field
	{
		data := struct {
			x: int,
		} {
			x = 1,
		}
		tmpl := ohtml.template_new("missing_field")
		defer ohtml.template_destroy(tmpl)
		ohtml.template_parse(tmpl, "{{.nonexistent}}")
		_, err := ohtml.execute_to_string(tmpl, data)
		testing.expect(t, err.kind != .None, "missing field should error")
		if err.msg != "" {delete(err.msg)}
	}

	// Nil pointer
	{
		tmpl := ohtml.template_new("nil_data")
		defer ohtml.template_destroy(tmpl)
		ohtml.template_parse(tmpl, "{{.x}}")
		_, err := ohtml.execute_to_string(tmpl, nil)
		testing.expect(t, err.kind != .None, "nil data with field access should error")
		if err.msg != "" {delete(err.msg)}
	}

	// Undefined template
	{
		data := struct {
			x: int,
		} {
			x = 1,
		}
		tmpl := ohtml.template_new("undef_tmpl")
		defer ohtml.template_destroy(tmpl)
		ohtml.template_parse(tmpl, `{{template "nonexistent" .}}`)
		_, err := ohtml.execute_to_string(tmpl, data)
		testing.expect(t, err.kind != .None, "undefined template should error")
		if err.msg != "" {delete(err.msg)}
	}

	// Range over non-iterable
	{
		data := struct {
			x: int,
		} {
			x = 5,
		}
		tmpl := ohtml.template_new("range_non_iter")
		defer ohtml.template_destroy(tmpl)
		ohtml.template_parse(tmpl, "{{range .x}}{{.}}{{end}}")
		// int should be iterable (range over integer), so this might not error
		// but a bool should not be iterable
		data2 := struct {
			b: bool,
		} {
			b = true,
		}
		tmpl2 := ohtml.template_new("range_bool")
		defer ohtml.template_destroy(tmpl2)
		ohtml.template_parse(tmpl2, "{{range .b}}{{.}}{{end}}")
		_, err2 := ohtml.execute_to_string(tmpl2, data2)
		testing.expect(t, err2.kind != .None, "range over bool should error")
		if err2.msg != "" {delete(err2.msg)}
	}

	// Incomplete template (no content)
	{
		tmpl := ohtml.template_new("incomplete")
		defer ohtml.template_destroy(tmpl)
		// Don't parse anything
		_, err := ohtml.execute_to_string(tmpl, nil)
		testing.expect(
			t,
			err.kind == .Incomplete_Template,
			"empty template should give Incomplete_Template error",
		)
	}
}

// ---------------------------------------------------------------------------
// Max exec depth test
// ---------------------------------------------------------------------------

@(test)
test_exec_max_depth :: proc(t: ^testing.T) {
	// Recursive template should hit max depth
	tmpl := ohtml.template_new("recurse")
	defer ohtml.template_destroy(tmpl)
	ohtml.template_parse(tmpl, `{{define "r"}}{{template "r" .}}{{end}}{{template "r" .}}`)
	_, err := ohtml.execute_to_string(tmpl, nil)
	testing.expect(t, err.kind == .Max_Depth_Exceeded, "recursive template should hit max depth")
}
