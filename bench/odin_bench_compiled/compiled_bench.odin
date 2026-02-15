package compiled_bench

import "core:fmt"
import "core:io"
import "core:strings"
import "core:time"

import "tpls"

// ---------------------------------------------------------------------------
// Benchmark runner (same harness as odin_bench)
// ---------------------------------------------------------------------------

Bench_Fn :: #type proc(n: int)

bench :: proc(name: string, f: Bench_Fn, min_duration: time.Duration) {
	// Warmup
	f(10)

	// Auto-calibrate N
	n := 100
	elapsed: time.Duration
	for {
		start := time.tick_now()
		f(n)
		elapsed = time.tick_diff(start, time.tick_now())
		if elapsed >= min_duration {
			break
		}
		if elapsed <= 0 {
			n *= 100
		} else {
			target_n := int(
				f64(n) *
				(f64(time.duration_seconds(min_duration)) / f64(time.duration_seconds(elapsed))) *
				1.2,
			)
			if target_n <= n {
				target_n = n * 2
			}
			n = target_n
		}
	}

	ns_per_op := f64(time.duration_nanoseconds(elapsed)) / f64(n)
	us_per_op := ns_per_op / 1000.0
	fmt.printf("%-30s %8d ops  %10.0f ns/op  (%6.1f us/op)\n", name, n, ns_per_op, us_per_op)
}

// ---------------------------------------------------------------------------
// Test data (matches bench/data/*.json)
// ---------------------------------------------------------------------------

data_simple := tpls.Simple_Data {
	Name  = "World",
	Count = 42,
}

data_loop := tpls.Loop_Data {
	Items = {
		"alpha",
		"beta",
		"gamma",
		"delta",
		"epsilon",
		"zeta",
		"eta",
		"theta",
		"iota",
		"kappa",
	},
}

data_nested := tpls.Nested_Data {
	Show    = true,
	Name    = "Alice",
	Email   = "alice@example.com",
	IsAdmin = true,
	Tags    = {"go", "odin", "rust", "zig"},
}

data_escape := tpls.Escape_Data {
	URL    = "https://example.com/search?q=hello world&lang=en",
	Title  = "<script>alert(\"xss\")</script>",
	JSVal  = "\"; alert('xss'); \"",
	CSSVal = "red; background: url(javascript:alert(1))",
}

data_complex := tpls.Complex_Data {
	Title    = "Product Catalog",
	Sections = {
		{
			Heading = "Electronics",
			Items = {
				{Name = "Laptop", Desc = "High performance", Active = true},
				{Name = "Phone", Desc = "Latest model", Active = true},
				{Name = "Tablet", Desc = "Discontinued", Active = false},
			},
		},
		{
			Heading = "Books",
			Items = {
				{Name = "Go Programming", Desc = "Learn Go", Active = true},
				{Name = "Odin Manual", Desc = "Language ref", Active = true},
			},
		},
		{Heading = "Empty Category", Items = {}},
	},
	Footer   = "\u00a9 2024 Example Corp",
}

// ---------------------------------------------------------------------------
// Benchmark functions — compiled execution only (no parse/escape)
// ---------------------------------------------------------------------------

bench_exec_simple :: proc(n: int) {
	for _ in 0 ..< n {
		b := strings.builder_make()
		w := strings.to_writer(&b)
		tpls.render_simple(w, &data_simple)
		strings.builder_destroy(&b)
	}
}

bench_exec_loop :: proc(n: int) {
	for _ in 0 ..< n {
		b := strings.builder_make()
		w := strings.to_writer(&b)
		tpls.render_loop(w, &data_loop)
		strings.builder_destroy(&b)
	}
}

bench_exec_nested :: proc(n: int) {
	for _ in 0 ..< n {
		b := strings.builder_make()
		w := strings.to_writer(&b)
		tpls.render_nested(w, &data_nested)
		strings.builder_destroy(&b)
	}
}

bench_exec_escape :: proc(n: int) {
	for _ in 0 ..< n {
		b := strings.builder_make()
		w := strings.to_writer(&b)
		tpls.render_escape(w, &data_escape)
		strings.builder_destroy(&b)
	}
}

bench_exec_complex :: proc(n: int) {
	for _ in 0 ..< n {
		b := strings.builder_make()
		w := strings.to_writer(&b)
		tpls.render_complex(w, &data_complex)
		strings.builder_destroy(&b)
	}
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

main :: proc() {
	min_dur := time.Duration(1 * time.Second)

	fmt.println("=== Compiled ohtml Benchmarks ===")
	fmt.println()

	fmt.println("--- Execute (compiled — no parse/escape overhead) ---")
	bench("ExecSimple", bench_exec_simple, min_dur)
	bench("ExecLoop", bench_exec_loop, min_dur)
	bench("ExecNested", bench_exec_nested, min_dur)
	bench("ExecEscape", bench_exec_escape, min_dur)
	bench("ExecComplex", bench_exec_complex, min_dur)
}
