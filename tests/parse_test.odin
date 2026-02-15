package ohtml_tests

import ohtml ".."
import "core:testing"

Parse_Test :: struct {
	name:  string,
	input: string,
	ok:    bool, // expect successful parse
}

parse_tests := [?]Parse_Test {
	// --- Plain text ---
	{"empty", "", true},
	{"text", "some text", true},
	{"multiline_text", "line1\nline2\nline3", true},
	// --- Simple actions ---
	{"dot", "{{.}}", true},
	{"field", "{{.X}}", true},
	{"field_chain", "{{.X.Y.Z}}", true},
	{"number", "{{42}}", true},
	{"negative_number", "{{-42}}", true},
	{"float", "{{3.14}}", true},
	{"hex", "{{0x1F}}", true},
	{"octal", "{{0o17}}", true},
	{"binary", "{{0b101}}", true},
	{"scientific", "{{1e2}}", true},
	{"bool_true", "{{true}}", true},
	{"bool_false", "{{false}}", true},
	{"string", `{{"hello"}}`, true},
	{"raw_string", "{{`hello`}}", true},
	{"nil", "{{nil}}", true},
	{"empty_action", `{{""}}`, true},
	// --- Pipelines ---
	{"pipe", "{{.X | printf}}", true},
	{"multi_pipe", "{{.X | printf | html}}", true},
	{"pipe_with_args", `{{printf "%d" .X}}`, true},
	{"pipe_with_decl", "{{$x := .X | html}}", true},
	// --- Variable declaration ---
	{"declare", "{{$x := .Y}}", true},
	{"var_use", "{{$x := .Y}}{{$x}}", true},
	{"dollar", "{{$}}", true},
	{"dollar_invocation", "{{$ := .X}}", true},
	// --- Parenthesized expressions ---
	{"parens", "{{(printf .X)}}", true},
	{"nested_parens", "{{((.X))}}", true},
	{"field_of_paren", "{{(.X).Y}}", true},
	{"parens_in_pipe", "{{(.X) | html}}", true},
	// --- If ---
	{"if", "{{if .X}}yes{{end}}", true},
	{"if_else", "{{if .X}}yes{{else}}no{{end}}", true},
	{"if_else_if", "{{if .X}}a{{else if .Y}}b{{end}}", true},
	{"if_else_if_else", "{{if .X}}a{{else if .Y}}b{{else}}c{{end}}", true},
	{"if_chain_deep", "{{if .A}}a{{else if .B}}b{{else if .C}}c{{else}}d{{end}}", true},
	// --- Range ---
	{"range", "{{range .Items}}{{.}}{{end}}", true},
	{"range_else", "{{range .Items}}{{.}}{{else}}empty{{end}}", true},
	{"range_var", "{{range $v := .Items}}{{$v}}{{end}}", true},
	{"range_kv", "{{range $k, $v := .Items}}{{$k}}={{$v}}{{end}}", true},
	{"range_pipeline", "{{range .X | .M}}{{.}}{{end}}", true},
	// --- With ---
	{"with", "{{with .X}}{{.}}{{end}}", true},
	{"with_else", "{{with .X}}{{.}}{{else}}none{{end}}", true},
	{"with_else_with", "{{with .X}}a{{else with .Y}}b{{end}}", true},
	{"with_else_with_chain", "{{with .X}}a{{else with .Y}}b{{else}}c{{end}}", true},
	// --- Template ---
	{"template", `{{template "sub" .}}`, true},
	{"template_no_data", `{{template "sub"}}`, true},
	// --- Define ---
	{"define", `{{define "sub"}}content{{end}}`, true},
	{"define_empty", `{{define "sub"}}{{end}}`, true},
	// --- Block ---
	{"block", `{{block "name" .}}default{{end}}`, true},
	{"block_empty", `{{block "name" .}}{{end}}`, true},
	// --- Nested structures ---
	{"nested_if", "{{if .A}}{{if .B}}deep{{end}}{{end}}", true},
	{"nested_range", "{{range .X}}{{range .Y}}{{.}}{{end}}{{end}}", true},
	{"range_with_if", "{{range .X}}{{if .Y}}{{.}}{{end}}{{end}}", true},
	{"if_with_range", "{{if .X}}{{range .Y}}{{.}}{{end}}{{end}}", true},
	// --- Trim ---
	{"trim_left", "  {{- .X}}", true},
	{"trim_right", "{{.X -}}  ", true},
	{"trim_both", "  {{- .X -}}  ", true},
	// --- Comments ---
	{"comment", "{{/* comment */}}", true},
	{"text_and_comment", "hello {{/* comment */}}world", true},
	// --- Multiple actions ---
	{"multi", "{{.A}} and {{.B}}", true},
	// --- Complex ---
	{"complex", `{{if .Show}}<h1>{{.Title}}</h1>{{end}}`, true},
	{"full_page", `<html>{{if .Show}}<h1>{{.Title}}</h1>{{end}}<p>{{.Body}}</p></html>`, true},
	// --- Constants ---
	{"mixed_constants", `{{printf "%v %v %v" true 42 "hello"}}`, true},
	// --- Multi-word command ---
	{"multi_word_cmd", "{{print .X .Y .Z}}", true},
	// --- Range break/continue (parsed through full template_parse) ---
	// Note: break/continue parsing is tested via parse_branch_control in test_parse_break_continue
}

@(test)
test_parse :: proc(t: ^testing.T) {
	for &tt in parse_tests {
		trees, err := ohtml.parse(tt.name, tt.input, mode = {.Skip_Func_Check})
		defer ohtml.trees_destroy(&trees)
		if err.msg != "" {
			defer delete(err.msg)
		}
		if tt.ok {
			testing.expectf(
				t,
				err.kind == .None,
				"[%s] unexpected error: %s (kind=%v)",
				tt.name,
				err.msg,
				err.kind,
			)
		} else {
			testing.expectf(t, err.kind != .None, "[%s] expected error, got none", tt.name)
		}
	}
}

// ---------------------------------------------------------------------------
// Verify basic AST structure
// ---------------------------------------------------------------------------

@(test)
test_parse_structure :: proc(t: ^testing.T) {
	// Simple text
	{
		trees, err := ohtml.parse("t1", "hello", mode = {.Skip_Func_Check})
		defer ohtml.trees_destroy(&trees)
		testing.expect(t, err.kind == .None, "t1: parse error")
		if tree, ok := trees["t1"]; ok {
			testing.expect(t, tree.root != nil, "t1: nil root")
			if tree.root != nil {
				testing.expectf(
					t,
					len(tree.root.nodes) == 1,
					"t1: expected 1 node, got %d",
					len(tree.root.nodes),
				)
				if len(tree.root.nodes) == 1 {
					_, is_text := tree.root.nodes[0].(^ohtml.Text_Node)
					testing.expect(t, is_text, "t1: expected Text_Node")
				}
			}
		} else {
			testing.expect(t, false, "t1: tree not found")
		}
	}

	// Action with field
	{
		trees, err := ohtml.parse("t2", "{{.Name}}", mode = {.Skip_Func_Check})
		defer ohtml.trees_destroy(&trees)
		testing.expect(t, err.kind == .None, "t2: parse error")
		if tree, ok := trees["t2"]; ok {
			testing.expect(t, tree.root != nil, "t2: nil root")
			if tree.root != nil {
				testing.expectf(
					t,
					len(tree.root.nodes) == 1,
					"t2: expected 1 node, got %d",
					len(tree.root.nodes),
				)
				if len(tree.root.nodes) == 1 {
					action, is_action := tree.root.nodes[0].(^ohtml.Action_Node)
					testing.expect(t, is_action, "t2: expected Action_Node")
					if is_action {
						testing.expect(t, action.pipe != nil, "t2: nil pipe")
						if action.pipe != nil {
							testing.expectf(
								t,
								len(action.pipe.cmds) == 1,
								"t2: expected 1 cmd, got %d",
								len(action.pipe.cmds),
							)
						}
					}
				}
			}
		}
	}

	// If with else
	{
		trees, err := ohtml.parse("t3", "{{if .X}}yes{{else}}no{{end}}", mode = {.Skip_Func_Check})
		defer ohtml.trees_destroy(&trees)
		testing.expect(t, err.kind == .None, "t3: parse error")
		if tree, ok := trees["t3"]; ok && tree.root != nil {
			testing.expectf(
				t,
				len(tree.root.nodes) == 1,
				"t3: expected 1 node, got %d",
				len(tree.root.nodes),
			)
			if len(tree.root.nodes) == 1 {
				if_node, is_if := tree.root.nodes[0].(^ohtml.If_Node)
				testing.expect(t, is_if, "t3: expected If_Node")
				if is_if {
					testing.expect(t, if_node.pipe != nil, "t3: nil pipe")
					testing.expect(t, if_node.list != nil, "t3: nil list")
					testing.expect(t, if_node.else_list != nil, "t3: nil else_list")
				}
			}
		}
	}

	// Define creates a separate tree
	{
		trees, err := ohtml.parse(
			"t4",
			`{{define "sub"}}content{{end}}`,
			mode = {.Skip_Func_Check},
		)
		defer ohtml.trees_destroy(&trees)
		testing.expect(t, err.kind == .None, "t4: parse error")
		_, has_sub := trees["sub"]
		testing.expect(t, has_sub, "t4: 'sub' tree not found")
	}

	// Range node
	{
		trees, err := ohtml.parse("t5", "{{range .X}}{{.}}{{end}}", mode = {.Skip_Func_Check})
		defer ohtml.trees_destroy(&trees)
		testing.expect(t, err.kind == .None, "t5: parse error")
		if tree, ok := trees["t5"]; ok && tree.root != nil {
			if len(tree.root.nodes) == 1 {
				_, is_range := tree.root.nodes[0].(^ohtml.Range_Node)
				testing.expect(t, is_range, "t5: expected Range_Node")
			}
		}
	}

	// With node
	{
		trees, err := ohtml.parse("t6", "{{with .X}}{{.}}{{end}}", mode = {.Skip_Func_Check})
		defer ohtml.trees_destroy(&trees)
		testing.expect(t, err.kind == .None, "t6: parse error")
		if tree, ok := trees["t6"]; ok && tree.root != nil {
			if len(tree.root.nodes) == 1 {
				_, is_with := tree.root.nodes[0].(^ohtml.With_Node)
				testing.expect(t, is_with, "t6: expected With_Node")
			}
		}
	}

	// Pipeline with two commands
	{
		trees, err := ohtml.parse("t7", "{{.X | html}}", mode = {.Skip_Func_Check})
		defer ohtml.trees_destroy(&trees)
		testing.expect(t, err.kind == .None, "t7: parse error")
		if tree, ok := trees["t7"]; ok && tree.root != nil {
			if len(tree.root.nodes) == 1 {
				action, is_action := tree.root.nodes[0].(^ohtml.Action_Node)
				if is_action && action.pipe != nil {
					testing.expectf(
						t,
						len(action.pipe.cmds) == 2,
						"t7: expected 2 cmds in pipeline, got %d",
						len(action.pipe.cmds),
					)
				}
			}
		}
	}

	// Block creates separate tree
	{
		trees, err := ohtml.parse(
			"t8",
			`{{block "blk" .}}default{{end}}`,
			mode = {.Skip_Func_Check},
		)
		defer ohtml.trees_destroy(&trees)
		testing.expect(t, err.kind == .None, "t8: parse error")
		_, has_blk := trees["blk"]
		testing.expect(t, has_blk, "t8: 'blk' tree not found")
	}

	// Variable declaration in pipeline
	{
		trees, err := ohtml.parse("t9", "{{$x := .Y}}", mode = {.Skip_Func_Check})
		defer ohtml.trees_destroy(&trees)
		testing.expect(t, err.kind == .None, "t9: parse error")
		if tree, ok := trees["t9"]; ok && tree.root != nil {
			if len(tree.root.nodes) == 1 {
				action, is_action := tree.root.nodes[0].(^ohtml.Action_Node)
				if is_action && action.pipe != nil {
					testing.expectf(
						t,
						len(action.pipe.decl) == 1,
						"t9: expected 1 decl, got %d",
						len(action.pipe.decl),
					)
				}
			}
		}
	}
}

// ---------------------------------------------------------------------------
// Parse error cases
// ---------------------------------------------------------------------------

@(test)
test_parse_errors :: proc(t: ^testing.T) {
	Error_Test :: struct {
		name:  string,
		input: string,
	}

	error_tests := [?]Error_Test {
		// Missing end
		{"missing_end", "{{if .X}}yes"},
		{"missing_end_range", "{{range .X}}item"},
		{"missing_end_with", "{{with .X}}body"},
		// Unclosed action
		{"unclosed_action", "{{.X"},
		// Invalid punctuation
		{"bad_pipe_start", "{{| .X}}"},
		// Missing template name
		{"template_no_name", "{{template 42}}"},
		// Missing block name
		{"block_no_name", "{{block 42 .}}{{end}}"},
		// Missing define name
		{"define_no_name", "{{define 42}}{{end}}"},
		// Bad number syntax
		{"bad_number", "{{3k}}"},
	}

	for &tt in error_tests {
		trees, err := ohtml.parse(tt.name, tt.input, mode = {.Skip_Func_Check})
		defer ohtml.trees_destroy(&trees)
		if err.msg != "" {
			delete(err.msg)
		}
		testing.expectf(t, err.kind != .None, "[%s] expected error, got none", tt.name)
	}
}

// ---------------------------------------------------------------------------
// Parse with comments mode
// ---------------------------------------------------------------------------

@(test)
test_parse_with_comments :: proc(t: ^testing.T) {
	trees, err := ohtml.parse(
		"cmt",
		"hello {{/* a comment */}}world",
		mode = {.Skip_Func_Check, .Parse_Comments},
	)
	defer ohtml.trees_destroy(&trees)
	testing.expect(t, err.kind == .None, "parse with comments error")

	if tree, ok := trees["cmt"]; ok && tree.root != nil {
		// Should have text, comment, text nodes
		found_comment := false
		for node in tree.root.nodes {
			if _, is_cmt := node.(^ohtml.Comment_Node); is_cmt {
				found_comment = true
			}
		}
		testing.expect(t, found_comment, "expected to find Comment_Node in AST")
	}
}

// ---------------------------------------------------------------------------
// Range break/continue test (via full template)
// ---------------------------------------------------------------------------

@(test)
test_parse_break_continue :: proc(t: ^testing.T) {
	// Break inside range should parse fine
	{
		tmpl := ohtml.template_new("brk")
		defer ohtml.template_destroy(tmpl)
		_, err := ohtml.template_parse(tmpl, "{{range .X}}{{if .Y}}{{break}}{{end}}{{end}}")
		testing.expectf(t, err.kind == .None, "break in range: unexpected error: %s", err.msg)
	}

	// Continue inside range should parse fine
	{
		tmpl := ohtml.template_new("cont")
		defer ohtml.template_destroy(tmpl)
		_, err := ohtml.template_parse(tmpl, "{{range .X}}{{if .Y}}{{continue}}{{end}}{{end}}")
		testing.expectf(t, err.kind == .None, "continue in range: unexpected error: %s", err.msg)
	}
}

// ---------------------------------------------------------------------------
// Skip func check mode test
// ---------------------------------------------------------------------------

@(test)
test_parse_skip_func_check :: proc(t: ^testing.T) {
	// Without skip func check, unknown functions should fail
	{
		trees, err := ohtml.parse("noskip", "{{myFunc .X}}", mode = {})
		defer ohtml.trees_destroy(&trees)
		if err.msg != "" {
			delete(err.msg)
		}
		testing.expect(t, err.kind != .None, "expected error for undefined function")
	}

	// With skip func check, it should succeed
	{
		trees, err := ohtml.parse("skip", "{{myFunc .X}}", mode = {.Skip_Func_Check})
		defer ohtml.trees_destroy(&trees)
		testing.expect(t, err.kind == .None, "skip func check should allow unknown function")
	}
}
