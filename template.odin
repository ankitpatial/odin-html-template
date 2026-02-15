package ohtml

import "core:io"
import "core:mem/virtual"
import "core:strings"

// ---------------------------------------------------------------------------
// Template and Common — shared template infrastructure
// ---------------------------------------------------------------------------

Common :: struct {
	tmpl_map:  map[string]^Template,
	func_maps: [dynamic]Func_Map,
}

Template :: struct {
	name:   string,
	tree:   ^Tree,
	common: ^Common,
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

// template_new creates a new template with the given name.
template_new :: proc(name: string) -> ^Template {
	t := new(Template)
	t.name = name
	t.common = new(Common)
	t.common.tmpl_map = make(map[string]^Template)
	t.common.tmpl_map[name] = t
	return t
}

// template_parse parses the template text and returns the template.
template_parse :: proc(t: ^Template, text: string) -> (^Template, Error) {
	trees, err := parse(t.name, text, mode = {.Skip_Func_Check})
	if err.kind != .None {
		// On error, clean up any partially-parsed trees.
		trees_destroy(&trees)
		return nil, err
	}
	for name, tree in trees {
		tmpl := _associate(t, tree, name)
		tmpl.tree = tree
	}
	// The tree structs are now owned by the templates; just delete the map.
	delete(trees)
	return t, {}
}

// template_funcs adds the given function map to the template.
template_funcs :: proc(t: ^Template, funcs: Func_Map) {
	append(&t.common.func_maps, funcs)
}

// template_lookup looks up a template by name in the associated set.
template_lookup :: proc(t: ^Template, name: string) -> ^Template {
	if t == nil || t.common == nil {
		return nil
	}
	return t.common.tmpl_map[name]
}

// execute executes the template, writing the result to the writer.
execute :: proc(t: ^Template, wr: io.Writer, data: any) -> Error {
	if t.tree == nil || t.tree.root == nil {
		return Error{kind = .Incomplete_Template, msg = "template has no content"}
	}

	// Use a growing virtual arena for all execution-time allocations.
	caller_alloc := context.allocator
	arena: virtual.Arena
	arena_err := virtual.arena_init_growing(&arena)
	if arena_err != nil {
		return Error{kind = .Execution_Failed, msg = "failed to initialize arena"}
	}

	s := Exec_State {
		tmpl = t,
		wr   = wr,
	}

	context.allocator = virtual.arena_allocator(&arena)
	exec_push(&s, "$", data)
	err := walk(&s, data, t.tree.root)
	delete(s.vars)

	// Clone error message to caller's allocator before freeing the arena.
	if err.kind != .None && err.msg != "" {
		err.msg = strings.clone(err.msg, caller_alloc)
	}
	virtual.arena_destroy(&arena)
	return err
}

// execute_to_string executes the template, returning the result as a string.
execute_to_string :: proc(
	t: ^Template,
	data: any,
	allocator := context.allocator,
) -> (
	string,
	Error,
) {
	if t.tree == nil || t.tree.root == nil {
		return "", Error{kind = .Incomplete_Template, msg = "template has no content"}
	}

	// Use a growing virtual arena for all execution-time allocations.
	arena: virtual.Arena
	arena_err := virtual.arena_init_growing(&arena)
	if arena_err != nil {
		return "", Error{kind = .Execution_Failed, msg = "failed to initialize arena"}
	}
	exec_alloc := virtual.arena_allocator(&arena)

	b := strings.builder_make(exec_alloc)
	s := Exec_State {
		tmpl = t,
		wr   = strings.to_writer(&b),
	}

	context.allocator = exec_alloc
	exec_push(&s, "$", data)
	err := walk(&s, data, t.tree.root)
	delete(s.vars)

	if err.kind != .None {
		// Clone error message to caller's allocator before freeing the arena,
		// since fmt.aprintf may have allocated it in the arena.
		if err.msg != "" {
			err.msg = strings.clone(err.msg, allocator)
		}
		virtual.arena_destroy(&arena)
		return "", err
	}

	// Copy the result string to the caller's allocator before freeing the arena.
	result := strings.clone(strings.to_string(b), allocator)
	virtual.arena_destroy(&arena)
	return result, {}
}

// template_destroy frees all resources associated with the template.
template_destroy :: proc(t: ^Template) {
	if t == nil {
		return
	}
	if t.common != nil {
		// Build a name->tree map for the block-list null-out pass.
		tree_map: map[string]^Tree
		for name, tmpl in t.common.tmpl_map {
			if tmpl.tree != nil {
				tree_map[name] = tmpl.tree
			}
		}
		// Null out Block_Node.list pointers shared with sub-trees.
		for _, tree in tree_map {
			if tree.root != nil {
				_null_block_lists(tree.root, &tree_map)
			}
		}
		delete(tree_map)
		// Destroy all templates and their trees.
		for _, tmpl in t.common.tmpl_map {
			if tmpl.tree != nil {
				tree_destroy(tmpl.tree)
				tmpl.tree = nil
			}
			if tmpl != t {
				free(tmpl)
			}
		}
		delete(t.common.tmpl_map)
		for &fm in t.common.func_maps {
			delete(fm)
		}
		delete(t.common.func_maps)
		free(t.common)
	}
	free(t)
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

@(private = "package")
_associate :: proc(t: ^Template, tree: ^Tree, name: string) -> ^Template {
	existing, ok := t.common.tmpl_map[name]
	if ok {
		existing.tree = tree
		return existing
	}
	tmpl := new(Template)
	tmpl.name = name
	tmpl.common = t.common
	t.common.tmpl_map[name] = tmpl
	return tmpl
}
