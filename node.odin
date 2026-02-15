package ohtml

// Node is the tagged union for all AST node types.
// All node types are heap-allocated pointers stored as union variants.
Node :: union {
	^List_Node,
	^Text_Node,
	^Comment_Node,
	^Action_Node,
	^Pipe_Node,
	^Command_Node,
	^Identifier_Node,
	^Variable_Node,
	^Dot_Node,
	^Nil_Node,
	^Field_Node,
	^Chain_Node,
	^Bool_Node,
	^Number_Node,
	^String_Node,
	^If_Node,
	^Range_Node,
	^With_Node,
	^Template_Node,
	^Block_Node,
	^Break_Node,
	^Continue_Node,
}

// List_Node holds a sequence of nodes.
List_Node :: struct {
	pos:   Pos,
	nodes: [dynamic]Node,
}

// Text_Node holds plain text (outside actions).
Text_Node :: struct {
	pos:  Pos,
	text: []u8, // raw text bytes, may be modified by trim
}

// Comment_Node holds a comment.
Comment_Node :: struct {
	pos:  Pos,
	text: string,
}

// Pipe_Node holds a pipeline: optional variable declarations and a sequence of commands.
Pipe_Node :: struct {
	pos:       Pos,
	line:      int,
	is_assign: bool, // = vs :=
	decl:      [dynamic]^Variable_Node, // LHS of := or =
	cmds:      [dynamic]^Command_Node, // piped commands
}

// Action_Node holds a non-control action ({{ ... }}).
Action_Node :: struct {
	pos:  Pos,
	line: int,
	pipe: ^Pipe_Node,
}

// Command_Node holds a single command in a pipeline.
Command_Node :: struct {
	pos:  Pos,
	args: [dynamic]Node, // arguments: identifiers, literals, fields, sub-pipes, etc.
}

// Identifier_Node holds an identifier (always a function name in practice).
Identifier_Node :: struct {
	pos:   Pos,
	ident: string,
}

// Variable_Node holds a $ variable reference.
// ident is split by '.': e.g. "$x.Field" -> {"$x", "Field"}
Variable_Node :: struct {
	pos:        Pos,
	ident:      []string,
	_alloc_buf: rawptr, // if non-nil, heap-allocated string buffer (from chain_string) to free
}

// Dot_Node represents the cursor '.' (the current data context).
Dot_Node :: struct {
	pos: Pos,
}

// Nil_Node represents the nil constant.
Nil_Node :: struct {
	pos: Pos,
}

// Field_Node holds a field access chain starting with '.'.
// ident is split: ".A.B" -> {"A", "B"}
Field_Node :: struct {
	pos:        Pos,
	ident:      []string,
	_alloc_buf: rawptr, // if non-nil, heap-allocated string buffer (from chain_string) to free
}

// Chain_Node holds a term followed by field accesses: (expr).Field1.Field2
Chain_Node :: struct {
	pos:   Pos,
	node:  Node,
	field: [dynamic]string,
}

// Bool_Node holds a boolean constant.
Bool_Node :: struct {
	pos: Pos,
	val: bool,
}

// Number_Node holds a numeric constant.
Number_Node :: struct {
	pos:        Pos,
	is_int:     bool,
	is_uint:    bool,
	is_float:   bool,
	int_val:    i64,
	uint_val:   u64,
	float_val:  f64,
	text:       string, // original text representation
	cached_val: any, // lazily-populated boxed value, avoids re-allocation per eval
}

// String_Node holds a string constant.
String_Node :: struct {
	pos:    Pos,
	quoted: string, // original quoted text (includes quotes)
	text:   string, // unquoted value
}

// Branch_Node is the shared base for if/range/with control structures.
Branch_Node :: struct {
	pos:       Pos,
	line:      int,
	pipe:      ^Pipe_Node,
	list:      ^List_Node,
	else_list: ^List_Node, // nil if no else
}

// If_Node represents an {{if}} action.
If_Node :: struct {
	using branch: Branch_Node,
}

// Range_Node represents a {{range}} action.
Range_Node :: struct {
	using branch: Branch_Node,
}

// With_Node represents a {{with}} action.
With_Node :: struct {
	using branch: Branch_Node,
}

// Template_Node represents a {{template "name" .}} invocation.
Template_Node :: struct {
	pos:  Pos,
	line: int,
	name: string,
	pipe: ^Pipe_Node, // nil if no pipeline
}

// Block_Node represents a {{block "name" .}}...{{end}} definition.
Block_Node :: struct {
	pos:  Pos,
	line: int,
	name: string,
	pipe: ^Pipe_Node,
	list: ^List_Node,
}

// Break_Node represents a {{break}} action.
Break_Node :: struct {
	pos:  Pos,
	line: int,
}

// Continue_Node represents a {{continue}} action.
Continue_Node :: struct {
	pos:  Pos,
	line: int,
}

// --- Helper procs ---

// list_append appends a node to a list node.
list_append :: proc(list: ^List_Node, n: Node) {
	append(&list.nodes, n)
}

// pipe_append appends a command to a pipe node.
pipe_append :: proc(pipe: ^Pipe_Node, cmd: ^Command_Node) {
	append(&pipe.cmds, cmd)
}

// cmd_append appends an argument to a command node.
cmd_append :: proc(cmd: ^Command_Node, arg: Node) {
	append(&cmd.args, arg)
}

// chain_add adds a field name to a chain node.
chain_add :: proc(chain: ^Chain_Node, field: string) {
	append(&chain.field, field)
}

// ---------------------------------------------------------------------------
// Node destruction — recursively free all AST nodes
// ---------------------------------------------------------------------------

// node_destroy frees a node and all its children.
node_destroy :: proc(n: Node) {
	switch v in n {
	case ^List_Node:
		list_node_destroy(v)
	case ^Text_Node:
		free(v)
	case ^Comment_Node:
		free(v)
	case ^Action_Node:
		if v.pipe != nil {
			pipe_node_destroy(v.pipe)
		}
		free(v)
	case ^Pipe_Node:
		pipe_node_destroy(v)
	case ^Command_Node:
		cmd_node_destroy(v)
	case ^Identifier_Node:
		free(v)
	case ^Variable_Node:
		if v._alloc_buf != nil {
			free(v._alloc_buf)
		}
		delete(v.ident)
		free(v)
	case ^Dot_Node:
		free(v)
	case ^Nil_Node:
		free(v)
	case ^Field_Node:
		if v._alloc_buf != nil {
			free(v._alloc_buf)
		}
		delete(v.ident)
		free(v)
	case ^Chain_Node:
		node_destroy(v.node)
		delete(v.field)
		free(v)
	case ^Bool_Node:
		free(v)
	case ^Number_Node:
		// Free the pre-boxed cached_val allocated during parsing.
		if v.cached_val != nil {
			free(v.cached_val.data)
		}
		free(v)
	case ^String_Node:
		free(v)
	case ^If_Node:
		branch_node_destroy(&v.branch)
		free(v)
	case ^Range_Node:
		branch_node_destroy(&v.branch)
		free(v)
	case ^With_Node:
		branch_node_destroy(&v.branch)
		free(v)
	case ^Template_Node:
		if v.pipe != nil {
			pipe_node_destroy(v.pipe)
		}
		free(v)
	case ^Block_Node:
		if v.pipe != nil {
			pipe_node_destroy(v.pipe)
		}
		// v.list is shared with a separate tree; don't free it here.
		free(v)
	case ^Break_Node:
		free(v)
	case ^Continue_Node:
		free(v)
	case nil:
	// nothing
	}
}

// list_node_destroy frees a list node and all its children.
list_node_destroy :: proc(list: ^List_Node) {
	if list == nil {
		return
	}
	for child in list.nodes {
		node_destroy(child)
	}
	delete(list.nodes)
	free(list)
}

// pipe_node_destroy frees a pipe node and its declarations and commands.
pipe_node_destroy :: proc(pipe: ^Pipe_Node) {
	if pipe == nil {
		return
	}
	for v in pipe.decl {
		if v._alloc_buf != nil {
			free(v._alloc_buf)
		}
		delete(v.ident)
		free(v)
	}
	delete(pipe.decl)
	for cmd in pipe.cmds {
		cmd_node_destroy(cmd)
	}
	delete(pipe.cmds)
	free(pipe)
}

// cmd_node_destroy frees a command node and its arguments.
cmd_node_destroy :: proc(cmd: ^Command_Node) {
	if cmd == nil {
		return
	}
	for arg in cmd.args {
		node_destroy(arg)
	}
	delete(cmd.args)
	free(cmd)
}

// branch_node_destroy frees the internals of a branch node (if/range/with).
// Does NOT free the branch node itself (caller does that).
branch_node_destroy :: proc(b: ^Branch_Node) {
	if b.pipe != nil {
		pipe_node_destroy(b.pipe)
	}
	list_node_destroy(b.list)
	list_node_destroy(b.else_list)
}
