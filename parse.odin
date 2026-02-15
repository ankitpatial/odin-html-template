package ohtml

import "core:fmt"
import "core:strconv"
import "core:strings"

MAX_STACK_DEPTH :: 10000

// Parse_Mode controls optional parser behavior.
Parse_Mode :: bit_set[Parse_Mode_Flag]

Parse_Mode_Flag :: enum {
	Parse_Comments, // emit comment nodes in the AST
	Skip_Func_Check, // don't check that functions are defined
}

// Func_Map maps function names to template functions.
Func_Map :: map[string]Template_Func

// Template_Func is the uniform signature for all template functions.
Template_Func :: #type proc(args: []any) -> (any, Error)

// Tree represents a parsed template.
Tree :: struct {
	name:        string,
	parse_name:  string, // name of top-level template during parsing (for errors)
	root:        ^List_Node,
	text:        string, // source text
	mode:        Parse_Mode,
	// Parsing state
	funcs:       []Func_Map,
	lex:         Lexer,
	token:       [3]Token, // 3-token lookahead buffer
	peek_count:  int,
	vars:        [dynamic]string,
	tree_set:    ^map[string]^Tree,
	action_line: int,
	range_depth: int,
	stack_depth: int,
}

// --- Destruction ---

// tree_destroy frees a tree and its root node list.
tree_destroy :: proc(t: ^Tree) {
	if t == nil {
		return
	}
	delete(t.vars)
	if t.root != nil {
		list_node_destroy(t.root)
		t.root = nil
	}
	free(t)
}

// trees_destroy frees a map of trees returned by parse().
// Block trees share their root list with a Block_Node in the parent tree,
// so we null out those shared pointers before destroying to prevent double-free.
trees_destroy :: proc(trees: ^map[string]^Tree) {
	if trees == nil {
		return
	}
	// Null out Block_Node.list pointers that are shared with sub-tree roots.
	for _, t in trees {
		if len(t.vars) > 0 && t.root != nil {
			_null_block_lists(t.root, trees)
		}
	}
	for _, t in trees {
		tree_destroy(t)
	}
	delete(trees^)
}

// _null_block_lists walks the AST and nulls out Block_Node.list pointers
// that are shared with sub-trees (to prevent double-free).
@(private = "package")
_null_block_lists :: proc(list: ^List_Node, trees: ^map[string]^Tree) {
	if list == nil {
		return
	}
	for node in list.nodes {
		#partial switch n in node {
		case ^Block_Node:
			// Block_Node.list is shared with trees[n.name].root
			if sub, ok := trees[n.name]; ok && sub != nil {
				if sub.root == n.list {
					n.list = nil // prevent double-free
				}
			}
		case ^If_Node:
			_null_block_lists(n.list, trees)
			_null_block_lists(n.else_list, trees)
		case ^Range_Node:
			_null_block_lists(n.list, trees)
			_null_block_lists(n.else_list, trees)
		case ^With_Node:
			_null_block_lists(n.list, trees)
			_null_block_lists(n.else_list, trees)
		case:
		}
	}
}

// --- Public API ---

// parse parses the template text and returns a map of named trees.
parse :: proc(
	name, text: string,
	left_delim := "",
	right_delim := "",
	funcs: []Func_Map = nil,
	mode: Parse_Mode = {},
	allocator := context.allocator,
) -> (
	trees: map[string]^Tree,
	err: Error,
) {
	context.allocator = allocator
	t := new(Tree)
	t.name = name
	t.parse_name = name
	t.text = text
	t.mode = mode
	trees = make(map[string]^Tree)
	t.tree_set = &trees
	t.funcs = funcs
	// $ is always in scope
	append(&t.vars, "$")
	lexer_init(&t.lex, name, text, left_delim, right_delim)
	if .Parse_Comments in mode {
		t.lex.options.emit_comment = true
	}
	err = tree_parse(t)
	// Always add the main tree so trees_destroy can clean it up.
	trees[name] = t
	return
}

// --- Token navigation ---

tree_next :: proc(t: ^Tree) -> Token {
	if t.peek_count > 0 {
		t.peek_count -= 1
	} else {
		t.token[0] = next_token(&t.lex)
	}
	return t.token[t.peek_count]
}

tree_backup :: proc(t: ^Tree) {
	t.peek_count += 1
}

tree_backup2 :: proc(t: ^Tree, t1: Token) {
	t.token[1] = t1
	t.peek_count = 2
}

tree_backup3 :: proc(t: ^Tree, t2, t1: Token) {
	t.token[1] = t1
	t.token[2] = t2
	t.peek_count = 3
}

tree_peek :: proc(t: ^Tree) -> Token {
	if t.peek_count > 0 {
		return t.token[t.peek_count - 1]
	}
	t.peek_count = 1
	t.token[0] = next_token(&t.lex)
	return t.token[0]
}

tree_next_non_space :: proc(t: ^Tree) -> Token {
	for {
		tok := tree_next(t)
		if tok.kind != .Space {
			return tok
		}
	}
}

tree_peek_non_space :: proc(t: ^Tree) -> Token {
	for {
		tok := tree_next(t)
		if tok.kind != .Space {
			tree_backup(t)
			return tok
		}
	}
}

// --- Error helpers ---

parse_error :: proc(t: ^Tree, kind: Error_Kind, format: string, args: ..any) -> Error {
	return Error {
		kind = kind,
		msg = fmt.aprintf(format, ..args),
		name = t.parse_name,
		line = t.token[0].line,
	}
}

expect :: proc(t: ^Tree, expected: Token_Kind, ctx: string) -> (Token, Error) {
	tok := tree_next_non_space(t)
	if tok.kind != expected {
		if tok.kind == .Error {
			delete(tok.val)
		}
		return tok, parse_error(
			t,
			.Unexpected_Token,
			"expected %v in %s, got %v",
			expected,
			ctx,
			tok.kind,
		)
	}
	return tok, {}
}

// --- Variable management ---

has_variable :: proc(t: ^Tree, name: string) -> bool {
	for v in t.vars {
		if v == name {
			return true
		}
	}
	return false
}

pop_vars :: proc(t: ^Tree, n: int) {
	resize(&t.vars, n)
}

has_function :: proc(t: ^Tree, name: string) -> bool {
	for fm in t.funcs {
		if name in fm {
			return true
		}
	}
	return false
}

// --- Node constructors ---

new_list :: proc(t: ^Tree, p: Pos) -> ^List_Node {
	n := new(List_Node)
	n.pos = p
	return n
}

new_text :: proc(t: ^Tree, p: Pos, text: string) -> ^Text_Node {
	n := new(Text_Node)
	n.pos = p
	n.text = transmute([]u8)text
	return n
}

new_comment :: proc(t: ^Tree, p: Pos, text: string) -> ^Comment_Node {
	n := new(Comment_Node)
	n.pos = p
	n.text = text
	return n
}

new_action :: proc(t: ^Tree, p: Pos, line: int, pipe: ^Pipe_Node) -> ^Action_Node {
	n := new(Action_Node)
	n.pos = p
	n.line = line
	n.pipe = pipe
	return n
}

new_pipe :: proc(t: ^Tree, p: Pos, line: int) -> ^Pipe_Node {
	n := new(Pipe_Node)
	n.pos = p
	n.line = line
	return n
}

new_command :: proc(t: ^Tree, p: Pos) -> ^Command_Node {
	n := new(Command_Node)
	n.pos = p
	return n
}

new_identifier :: proc(t: ^Tree, p: Pos, ident: string) -> ^Identifier_Node {
	n := new(Identifier_Node)
	n.pos = p
	n.ident = ident
	return n
}

new_variable :: proc(t: ^Tree, p: Pos, text: string) -> ^Variable_Node {
	n := new(Variable_Node)
	n.pos = p
	n.ident = split_variable(text)
	return n
}

new_dot :: proc(t: ^Tree, p: Pos) -> ^Dot_Node {
	n := new(Dot_Node)
	n.pos = p
	return n
}

new_nil :: proc(t: ^Tree, p: Pos) -> ^Nil_Node {
	n := new(Nil_Node)
	n.pos = p
	return n
}

new_field :: proc(t: ^Tree, p: Pos, text: string) -> ^Field_Node {
	n := new(Field_Node)
	n.pos = p
	n.ident = split_field(text)
	return n
}

new_chain :: proc(t: ^Tree, p: Pos, node: Node) -> ^Chain_Node {
	n := new(Chain_Node)
	n.pos = p
	n.node = node
	return n
}

new_bool :: proc(t: ^Tree, p: Pos, val: bool) -> ^Bool_Node {
	n := new(Bool_Node)
	n.pos = p
	n.val = val
	return n
}

new_number :: proc(t: ^Tree, p: Pos, text: string, typ: Token_Kind) -> (^Number_Node, Error) {
	n := new(Number_Node)
	n.pos = p
	n.text = text

	if i, ok := strconv.parse_i64(text); ok {
		n.is_int = true
		n.int_val = i
		n.is_float = true
		n.float_val = f64(i)
		if i >= 0 {
			n.is_uint = true
			n.uint_val = u64(i)
		}
		return n, {}
	}

	if u, ok := strconv.parse_u64(text); ok {
		n.is_uint = true
		n.uint_val = u
		n.is_float = true
		n.float_val = f64(u)
		return n, {}
	}

	if f, ok := strconv.parse_f64(text); ok {
		n.is_float = true
		n.float_val = f
		if f64(i64(f)) == f {
			n.is_int = true
			n.int_val = i64(f)
			if f >= 0 {
				n.is_uint = true
				n.uint_val = u64(f)
			}
		}
		return n, {}
	}

	return nil, parse_error(t, .Bad_Number, "bad number syntax: %q", text)
}

new_string :: proc(t: ^Tree, p: Pos, orig, text: string) -> ^String_Node {
	n := new(String_Node)
	n.pos = p
	n.quoted = orig
	n.text = text
	return n
}

new_if :: proc(
	t: ^Tree,
	p: Pos,
	line: int,
	pipe: ^Pipe_Node,
	list, else_list: ^List_Node,
) -> ^If_Node {
	n := new(If_Node)
	n.pos = p
	n.line = line
	n.pipe = pipe
	n.list = list
	n.else_list = else_list
	return n
}

new_range :: proc(
	t: ^Tree,
	p: Pos,
	line: int,
	pipe: ^Pipe_Node,
	list, else_list: ^List_Node,
) -> ^Range_Node {
	n := new(Range_Node)
	n.pos = p
	n.line = line
	n.pipe = pipe
	n.list = list
	n.else_list = else_list
	return n
}

new_with :: proc(
	t: ^Tree,
	p: Pos,
	line: int,
	pipe: ^Pipe_Node,
	list, else_list: ^List_Node,
) -> ^With_Node {
	n := new(With_Node)
	n.pos = p
	n.line = line
	n.pipe = pipe
	n.list = list
	n.else_list = else_list
	return n
}

new_template_node :: proc(
	t: ^Tree,
	p: Pos,
	line: int,
	name: string,
	pipe: ^Pipe_Node,
) -> ^Template_Node {
	n := new(Template_Node)
	n.pos = p
	n.line = line
	n.name = name
	n.pipe = pipe
	return n
}

new_block :: proc(
	t: ^Tree,
	p: Pos,
	line: int,
	name: string,
	pipe: ^Pipe_Node,
	list: ^List_Node,
) -> ^Block_Node {
	n := new(Block_Node)
	n.pos = p
	n.line = line
	n.name = name
	n.pipe = pipe
	n.list = list
	return n
}

new_break :: proc(t: ^Tree, p: Pos, line: int) -> ^Break_Node {
	n := new(Break_Node)
	n.pos = p
	n.line = line
	return n
}

new_continue :: proc(t: ^Tree, p: Pos, line: int) -> ^Continue_Node {
	n := new(Continue_Node)
	n.pos = p
	n.line = line
	return n
}

// --- String helpers ---

split_variable :: proc(text: string) -> []string {
	// Count dots to determine number of parts.
	dot_count := 0
	for c in text {
		if c == '.' {
			dot_count += 1
		}
	}
	if dot_count == 0 {
		result := make([]string, 1)
		result[0] = text
		return result
	}
	// Split on '.' — parts are slices into the original text, no allocation needed for the strings.
	result := make([]string, dot_count + 1)
	idx := 0
	start := 0
	for i in 0 ..< len(text) {
		if text[i] == '.' {
			result[idx] = text[start:i]
			idx += 1
			start = i + 1
		}
	}
	result[idx] = text[start:]
	return result
}

split_field :: proc(text: string) -> []string {
	s := text[1:] if len(text) > 0 && text[0] == '.' else text
	// Count dots.
	dot_count := 0
	for c in s {
		if c == '.' {
			dot_count += 1
		}
	}
	result := make([]string, dot_count + 1)
	idx := 0
	start := 0
	for i in 0 ..< len(s) {
		if s[i] == '.' {
			result[idx] = s[start:i]
			idx += 1
			start = i + 1
		}
	}
	result[idx] = s[start:]
	return result
}

// --- Top-level parser ---

tree_parse :: proc(t: ^Tree) -> Error {
	t.root = new_list(t, tree_peek(t).pos)
	for tree_peek(t).kind != .EOF {
		if tree_peek(t).kind == .Left_Delim {
			delim := tree_next(t)
			ns := tree_next_non_space(t)
			if ns.kind == .Define {
				err := parse_define(t)
				if err.kind != .None {
					return err
				}
				continue
			}
			tree_backup2(t, delim)
		}
		n, err := text_or_action(t)
		if err.kind != .None {
			return err
		}
		if n != nil {
			list_append(t.root, n)
		}
	}
	return {}
}

text_or_action :: proc(t: ^Tree) -> (Node, Error) {
	tok := tree_next_non_space(t)
	#partial switch tok.kind {
	case .Text:
		return new_text(t, tok.pos, tok.val), {}
	case .Left_Delim:
		t.action_line = tok.line
		return action(t)
	case .Comment:
		return new_comment(t, tok.pos, tok.val), {}
	case:
		if tok.kind == .Error {
			delete(tok.val)
		}
		return nil, parse_error(t, .Unexpected_Token, "unexpected token %v in input", tok.kind)
	}
}

action :: proc(t: ^Tree) -> (Node, Error) {
	tok := tree_next_non_space(t)
	#partial switch tok.kind {
	case .Block:
		return block_control(t)
	case .Break:
		return break_control(t, tok.pos, tok.line)
	case .Continue:
		return continue_control(t, tok.pos, tok.line)
	case .Else:
		return else_control(t)
	case .End:
		return end_control(t)
	case .If:
		return if_control(t)
	case .Range:
		return range_control(t)
	case .Template:
		return template_control(t)
	case .With:
		return with_control(t)
	case:
		tree_backup(t)
		tok = tree_peek(t)
		pipe, err := parse_pipeline(t, "command", .Right_Delim)
		if err.kind != .None {
			if pipe != nil {
				pipe_node_destroy(pipe)
			}
			return nil, err
		}
		return new_action(t, tok.pos, tok.line, pipe), {}
	}
}

// --- Control structures ---

if_control :: proc(t: ^Tree) -> (Node, Error) {
	return parse_branch_control(t, "if")
}

range_control :: proc(t: ^Tree) -> (Node, Error) {
	return parse_branch_control(t, "range")
}

with_control :: proc(t: ^Tree) -> (Node, Error) {
	return parse_branch_control(t, "with")
}

parse_branch_control :: proc(t: ^Tree, ctx: string) -> (Node, Error) {
	saved_vars := len(t.vars)
	defer pop_vars(t, saved_vars)

	pipe, pipe_err := parse_pipeline(t, ctx, .Right_Delim)
	if pipe_err.kind != .None {
		return nil, pipe_err
	}

	if ctx == "range" {
		t.range_depth += 1
		t.lex.options.break_ok = true
		t.lex.options.continue_ok = true
	}

	list, found_else, list_err := item_list(t)

	if ctx == "range" {
		t.range_depth -= 1
		if t.range_depth == 0 {
			t.lex.options.break_ok = false
			t.lex.options.continue_ok = false
		}
	}

	if list_err.kind != .None {
		pipe_node_destroy(pipe)
		list_node_destroy(list)
		return nil, list_err
	}

	else_list: ^List_Node
	if found_else {
		peek := tree_peek_non_space(t)
		if ctx == "if" && peek.kind == .If {
			tree_next(t) // consume "if"
			else_list = new_list(t, peek.pos)
			chained, chain_err := parse_branch_control(t, "if")
			if chain_err.kind != .None {
				pipe_node_destroy(pipe)
				list_node_destroy(list)
				list_node_destroy(else_list)
				return nil, chain_err
			}
			list_append(else_list, chained)
		} else if ctx == "with" && peek.kind == .With {
			tree_next(t) // consume "with"
			else_list = new_list(t, peek.pos)
			chained, chain_err := parse_branch_control(t, "with")
			if chain_err.kind != .None {
				pipe_node_destroy(pipe)
				list_node_destroy(list)
				list_node_destroy(else_list)
				return nil, chain_err
			}
			list_append(else_list, chained)
		} else {
			else_body, _, else_err := item_list(t)
			if else_err.kind != .None {
				pipe_node_destroy(pipe)
				list_node_destroy(list)
				return nil, else_err
			}
			else_list = else_body
		}
	}

	p := pipe.pos
	line := pipe.line

	switch ctx {
	case "if":
		return new_if(t, p, line, pipe, list, else_list), {}
	case "range":
		return new_range(t, p, line, pipe, list, else_list), {}
	case "with":
		return new_with(t, p, line, pipe, list, else_list), {}
	}

	return nil, parse_error(t, .Unexpected_Token, "unknown branch context: %s", ctx)
}

// item_list parses until {{end}} or {{else}}.
// Returns the list, whether {{else}} was found, and any error.
item_list :: proc(t: ^Tree) -> (list: ^List_Node, found_else: bool, err: Error) {
	list = new_list(t, tree_peek_non_space(t).pos)
	for tree_peek_non_space(t).kind != .EOF {
		if tree_peek_non_space(t).kind == .Left_Delim {
			delim := tree_next(t)
			t.action_line = delim.line
			ns := tree_next_non_space(t)
			#partial switch ns.kind {
			case .End:
				_, end_err := expect(t, .Right_Delim, "end")
				if end_err.kind != .None {
					err = end_err
				}
				return
			case .Else:
				peek := tree_peek_non_space(t)
				if peek.kind == .If || peek.kind == .With {
					// {{else if ...}} or {{else with ...}} — don't consume }},
					// parse_branch_control will handle the chained keyword.
				} else {
					_, else_err := expect(t, .Right_Delim, "else")
					if else_err.kind != .None {
						err = else_err
						return
					}
				}
				found_else = true
				return
			case:
				// Regular action — push back the token and parse
				tree_backup(t)
				n: Node
				n, err = action(t)
				if err.kind != .None {
					return
				}
				if n != nil {
					list_append(list, n)
				}
			}
		} else {
			n: Node
			n, err = text_or_action(t)
			if err.kind != .None {
				return
			}
			if n != nil {
				list_append(list, n)
			}
		}
	}
	err = parse_error(t, .Missing_End, "unexpected EOF; missing {{end}}")
	return
}

end_control :: proc(t: ^Tree) -> (Node, Error) {
	_, err := expect(t, .Right_Delim, "end")
	return nil, err
}

else_control :: proc(t: ^Tree) -> (Node, Error) {
	_, err := expect(t, .Right_Delim, "else")
	return nil, err
}

block_control :: proc(t: ^Tree) -> (Node, Error) {
	tok := tree_next_non_space(t)
	name := ""
	#partial switch tok.kind {
	case .String:
		s, ok := unquote_string(tok.val)
		if !ok {
			return nil, parse_error(t, .Unterminated_String, "bad block name: %q", tok.val)
		}
		name = s
	case .Raw_String:
		name = tok.val[1:len(tok.val) - 1]
	case:
		return nil, parse_error(
			t,
			.Unexpected_Token,
			"unexpected %v in block; want string",
			tok.kind,
		)
	}

	pipe, err := parse_pipeline(t, "block", .Right_Delim)
	if err.kind != .None {
		return nil, err
	}

	list, _, list_err := item_list(t)
	if list_err.kind != .None {
		return nil, list_err
	}

	block := new_block(t, tok.pos, tok.line, name, pipe, list)

	if t.tree_set != nil {
		block_tree := new(Tree)
		block_tree.name = name
		block_tree.parse_name = t.parse_name
		block_tree.root = list
		block_tree.text = t.text
		t.tree_set^[name] = block_tree
	}

	return block, {}
}

template_control :: proc(t: ^Tree) -> (Node, Error) {
	tok := tree_next_non_space(t)
	name := ""
	#partial switch tok.kind {
	case .String:
		s, ok := unquote_string(tok.val)
		if !ok {
			return nil, parse_error(t, .Unterminated_String, "bad template name: %q", tok.val)
		}
		name = s
	case .Raw_String:
		name = tok.val[1:len(tok.val) - 1]
	case:
		return nil, parse_error(
			t,
			.Unexpected_Token,
			"unexpected %v in template; want string",
			tok.kind,
		)
	}

	pipe, err := parse_pipeline(t, "template", .Right_Delim)
	if err.kind != .None {
		return nil, err
	}

	return new_template_node(t, tok.pos, tok.line, name, pipe), {}
}

break_control :: proc(t: ^Tree, p: Pos, line: int) -> (Node, Error) {
	if t.range_depth == 0 {
		return nil, parse_error(t, .Branch_In_Wrong_Context, "{{break}} outside {{range}}")
	}
	_, err := expect(t, .Right_Delim, "break")
	if err.kind != .None {
		return nil, err
	}
	return new_break(t, p, line), {}
}

continue_control :: proc(t: ^Tree, p: Pos, line: int) -> (Node, Error) {
	if t.range_depth == 0 {
		return nil, parse_error(t, .Branch_In_Wrong_Context, "{{continue}} outside {{range}}")
	}
	_, err := expect(t, .Right_Delim, "continue")
	if err.kind != .None {
		return nil, err
	}
	return new_continue(t, p, line), {}
}

parse_define :: proc(t: ^Tree) -> Error {
	tok := tree_next_non_space(t)
	name := ""
	#partial switch tok.kind {
	case .String:
		s, ok := unquote_string(tok.val)
		if !ok {
			return parse_error(t, .Unterminated_String, "bad define name: %q", tok.val)
		}
		name = s
	case .Raw_String:
		name = tok.val[1:len(tok.val) - 1]
	case:
		return parse_error(t, .Unexpected_Token, "unexpected %v in define; want string", tok.kind)
	}

	_, err := expect(t, .Right_Delim, "define")
	if err.kind != .None {
		return err
	}

	list, _, list_err := item_list(t)
	if list_err.kind != .None {
		return list_err
	}

	if t.tree_set != nil {
		new_tree := new(Tree)
		new_tree.name = name
		new_tree.parse_name = t.parse_name
		new_tree.root = list
		new_tree.text = t.text
		t.tree_set^[name] = new_tree
	}

	return {}
}

// --- Pipeline parser ---

parse_pipeline :: proc(t: ^Tree, ctx: string, end: Token_Kind) -> (pipe: ^Pipe_Node, err: Error) {
	tok := tree_peek_non_space(t)
	pipe = new_pipe(t, tok.pos, tok.line)

	// Check for variable declarations
	if v := tree_peek_non_space(t); v.kind == .Variable {
		tree_next(t) // consume variable
		token_after := tree_peek(t) // might be space
		ns := tree_peek_non_space(t)

		switch {
		case ns.kind == .Assign || ns.kind == .Declare:
			pipe.is_assign = ns.kind == .Assign
			tree_next_non_space(t) // consume assign/declare
			vn := new_variable(t, v.pos, v.val)
			append(&pipe.decl, vn)
			append(&t.vars, v.val)
		case ns.kind == .Char && ns.val == ",":
			// Range: $k, $v :=
			tree_next_non_space(t) // consume comma
			vn := new_variable(t, v.pos, v.val)
			append(&pipe.decl, vn)
			append(&t.vars, v.val)
			if ctx == "range" && len(pipe.decl) < 2 {
				peeked := tree_peek_non_space(t)
				if peeked.kind == .Variable {
					v2 := tree_next_non_space(t)
					ns2 := tree_peek_non_space(t)
					if ns2.kind == .Assign || ns2.kind == .Declare {
						pipe.is_assign = ns2.kind == .Assign
						tree_next_non_space(t)
						vn2 := new_variable(t, v2.pos, v2.val)
						append(&pipe.decl, vn2)
						append(&t.vars, v2.val)
					} else {
						tree_backup(t)
					}
				}
			} else {
				err = parse_error(t, .Too_Many_Decls, "too many declarations in %s", ctx)
				return
			}
		case token_after.kind == .Space:
			tree_backup3(t, v, token_after)
		case:
			tree_backup2(t, v)
		}
	}

	// Parse commands
	for {
		tok = tree_next_non_space(t)
		#partial switch tok.kind {
		case end:
			return
		case .Bool,
		     .Char_Constant,
		     .Dot,
		     .Field,
		     .Identifier,
		     .Number,
		     .Nil,
		     .Raw_String,
		     .String,
		     .Variable,
		     .Left_Paren:
			tree_backup(t)
			cmd: ^Command_Node
			cmd, err = parse_command(t)
			if err.kind != .None {
				if cmd != nil {
					cmd_node_destroy(cmd)
				}
				return
			}
			pipe_append(pipe, cmd)
		case:
			if tok.kind == .Error {
				delete(tok.val)
			}
			err = parse_error(t, .Unexpected_Token, "unexpected %v in %s", tok.kind, ctx)
			return
		}
	}
}

parse_command :: proc(t: ^Tree) -> (cmd: ^Command_Node, err: Error) {
	cmd = new_command(t, tree_peek_non_space(t).pos)
	for {
		tree_peek_non_space(t)
		operand: Node
		operand, err = parse_operand(t)
		if err.kind != .None {
			return
		}
		if operand != nil {
			cmd_append(cmd, operand)
		}
		tok := tree_next(t)
		#partial switch tok.kind {
		case .Space:
			continue
		case .Right_Delim, .Right_Paren:
			tree_backup(t)
		case .Pipe:
		// end of this command
		case:
			if tok.kind == .Error {
				delete(tok.val)
			}
			err = parse_error(t, .Unexpected_Token, "unexpected %v in operand", tok.kind)
			return
		}
		break
	}
	if len(cmd.args) == 0 {
		err = parse_error(t, .Empty_Command, "empty command")
	}
	return
}

parse_operand :: proc(t: ^Tree) -> (Node, Error) {
	node, err := parse_term(t)
	if err.kind != .None {
		return nil, err
	}
	if node == nil {
		return nil, {}
	}
	if tree_peek(t).kind == .Field {
		chain := new_chain(t, tree_peek(t).pos, node)
		for tree_peek(t).kind == .Field {
			tok := tree_next(t)
			chain_add(chain, tok.val)
		}
		#partial switch v in node {
		case ^Field_Node:
			cs, buf := chain_string(chain)
			result := new_field(t, chain.pos, cs)
			result._alloc_buf = raw_data(buf)
			delete(chain.field)
			chain.node = nil
			free(chain)
			node_destroy(node)
			return result, {}
		case ^Variable_Node:
			cs, buf := chain_string(chain)
			result := new_variable(t, chain.pos, cs)
			result._alloc_buf = raw_data(buf)
			delete(chain.field)
			chain.node = nil
			free(chain)
			node_destroy(node)
			return result, {}
		case ^Bool_Node, ^String_Node, ^Number_Node, ^Nil_Node, ^Dot_Node:
			delete(chain.field)
			chain.node = nil
			free(chain)
			return nil, parse_error(t, .Unexpected_Token, "unexpected . after term")
		case:
			return chain, {}
		}
	}
	return node, {}
}

chain_string :: proc(c: ^Chain_Node) -> (string, [dynamic]u8) {
	b := strings.builder_make_len_cap(0, len(c.field) * 8)
	#partial switch v in c.node {
	case ^Field_Node:
		strings.write_string(&b, ".")
		for ident, i in v.ident {
			if i > 0 {
				strings.write_string(&b, ".")
			}
			strings.write_string(&b, ident)
		}
	case ^Variable_Node:
		for ident, i in v.ident {
			if i > 0 {
				strings.write_string(&b, ".")
			}
			strings.write_string(&b, ident)
		}
	case:
	// other node types
	}
	for f in c.field {
		strings.write_string(&b, f)
	}
	return strings.to_string(b), b.buf
}

parse_term :: proc(t: ^Tree) -> (Node, Error) {
	tok := tree_next_non_space(t)
	#partial switch tok.kind {
	case .Identifier:
		check_func := .Skip_Func_Check not_in t.mode
		if check_func && !has_function(t, tok.val) {
			return nil, parse_error(t, .Undefined_Function, "function %q not defined", tok.val)
		}
		return new_identifier(t, tok.pos, tok.val), {}
	case .Dot:
		return new_dot(t, tok.pos), {}
	case .Nil:
		return new_nil(t, tok.pos), {}
	case .Variable:
		return use_var(t, tok.pos, tok.val)
	case .Field:
		return new_field(t, tok.pos, tok.val), {}
	case .Bool:
		return new_bool(t, tok.pos, tok.val == "true"), {}
	case .Char_Constant, .Number:
		tree_backup(t)
		tok = tree_next(t)
		return new_number(t, tok.pos, tok.val, tok.kind)
	case .Left_Paren:
		if t.stack_depth >= MAX_STACK_DEPTH {
			return nil, parse_error(t, .Max_Paren_Depth, "max expression depth exceeded")
		}
		t.stack_depth += 1
		pipe, err := parse_pipeline(t, "parenthesized pipeline", .Right_Paren)
		t.stack_depth -= 1
		if err.kind != .None {
			return nil, err
		}
		return pipe, {}
	case .String:
		s, ok := unquote_string(tok.val)
		if !ok {
			return nil, parse_error(t, .Unterminated_String, "bad string syntax: %q", tok.val)
		}
		return new_string(t, tok.pos, tok.val, s), {}
	case .Raw_String:
		s := tok.val[1:len(tok.val) - 1]
		return new_string(t, tok.pos, tok.val, s), {}
	case:
		tree_backup(t)
		return nil, {}
	}
}

use_var :: proc(t: ^Tree, p: Pos, text: string) -> (Node, Error) {
	v := new_variable(t, p, text)
	name := v.ident[0]
	if !has_variable(t, name) {
		return nil, parse_error(t, .Undefined_Variable, "undefined variable %q", name)
	}
	return v, {}
}

// --- String unquoting ---

unquote_string :: proc(s: string) -> (string, bool) {
	if len(s) < 2 {
		return "", false
	}
	quote := s[0]
	if quote != '"' && quote != '\'' {
		return "", false
	}
	if s[len(s) - 1] != quote {
		return "", false
	}
	inner := s[1:len(s) - 1]
	if !strings.contains(inner, "\\") {
		return inner, true
	}
	b := strings.builder_make_len_cap(0, len(inner))
	i := 0
	for i < len(inner) {
		if inner[i] == '\\' && i + 1 < len(inner) {
			i += 1
			switch inner[i] {
			case 'n':
				strings.write_byte(&b, '\n')
			case 't':
				strings.write_byte(&b, '\t')
			case 'r':
				strings.write_byte(&b, '\r')
			case '\\':
				strings.write_byte(&b, '\\')
			case '"':
				strings.write_byte(&b, '"')
			case '\'':
				strings.write_byte(&b, '\'')
			case 'a':
				strings.write_byte(&b, '\a')
			case 'b':
				strings.write_byte(&b, '\b')
			case 'f':
				strings.write_byte(&b, '\f')
			case 'v':
				strings.write_byte(&b, '\v')
			case:
				strings.write_byte(&b, '\\')
				strings.write_byte(&b, inner[i])
			}
		} else {
			strings.write_byte(&b, inner[i])
		}
		i += 1
	}
	return strings.to_string(b), true
}
