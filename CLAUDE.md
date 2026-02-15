# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

Port of Go's `html/template` to Odin. Single flat package providing context-aware auto-escaping HTML templates. Zero external dependencies.

## Commands

```bash
# Run all tests
odin test tests

# Run specific test by name
odin test tests -define:ODIN_TEST_NAMES=test_lex_basic

# Run the console example
odin run examples

# Build benchmarks
cd bench/odin_bench && odin build . -collection:ohtml=../.. -o:speed -out:bench

# Run benchmarks (from project root)
./bench/odin_bench/bench
```

## Architecture

Pipeline: `Template Text → Lexer → Parser → Escape Analysis → Execution → Output`

**Core flow across files:**
- `ohtml.odin` — Public convenience API (`render`, `render_raw`)
- `template.odin` — Template lifecycle, scratch allocator setup for execution
- `lex.odin` — Pull-based state machine lexer (`next_token()` returns one token at a time)
- `parse.odin` — Recursive descent parser, produces AST. Also defines `Template_Func` and `Func_Map`
- `node.odin` — 21-variant tagged `Node` union (all heap-allocated pointers)
- `exec.odin` — AST walker, variable stack, field/map access via `core:reflect`
- `escape.odin` — Walks AST, determines HTML context per action, injects escaper function calls into pipelines
- `transition.odin` — HTML/JS/CSS state machine that advances `Escape_Context` through raw text bytes
- `context.odin` — `Escape_Context` struct with 26 states (Text, Tag, JS, CSS, URL, etc.)

**Supporting files:**
- `value.odin` — Truthiness (`is_true`), comparison (`compare_eq`/`compare_lt`), `box_*` helpers, `indirect` (pointer following)
- `funcs.odin` — 19 built-in functions (`and`, `or`, `eq`, `len`, `index`, `print`, etc.), `find_builtin` switch
- `content.odin` — `Safe_HTML`, `Safe_CSS`, etc. distinct string types to bypass escaping
- `html_escape.odin`, `js_escape.odin`, `css_escape.odin`, `url_escape.odin` — Escaping implementations

## Key Design Patterns

**Error handling:** `(result, Error)` returns everywhere. `Error` has `.kind` (enum), `.msg`, `.name`, `.line`. Check `err.kind != .None`.

**`any` lifetime rule:** `any` stores a pointer to data. Never return a local variable as `any`. Use `box_int()`, `box_string()`, `box_bool()`, `box_i64()`, `box_f64()` to heap-allocate values that will be returned as `any`.

**Template functions:** All must be `proc(args: []any) -> (any, Error)`. Return boxed values.

**Memory:** Execution uses a 64KB stack-based `mem.Scratch` allocator with heap fallback. The scratch buffer lives on the stack — no mmap/syscall per call. `template_destroy()` frees all parse-time allocations.

**Lexer:** State functions return the next state function, or `nil` to emit a token. `next_token()` drives the loop. Not goroutine-based like Go's.

**Node ownership:** `Block_Node.list` is shared with a sub-tree's `.root`. `_null_block_lists` prevents double-free during destruction.

## Odin Language Gotchas

- `for value, index in slice` — value first, index second
- `#partial switch` required for non-exhaustive switch on enums/unions
- `defer { block }` not `defer do { block }`
- `[dynamic]T` to `[]T`: use `arr[:]`
- `io.write_string` returns `(int, Error)` not just `Error`
- `base:runtime` not `core:runtime`
- `testing` package: `expect`, `expectf`, `expect_value`, `fail`, `fail_now` — no `errorf`
- No global-scope proc calls — use struct literal constants instead
- Map iteration: `for key, &value in map` — use `&` to get addressable values for slicing

## Test Structure

Tests are in `tests/` and import the package as `import ohtml ".."`:
- `lex_test.odin` — Token-by-token lexer verification
- `parse_test.odin` — AST construction tests
- `exec_test.odin` — Data binding, field access, loops, conditionals, functions
- `escape_test.odin` — Context-aware escaping, XSS prevention
