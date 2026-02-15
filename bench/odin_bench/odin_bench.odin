package odin_bench

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:time"
import ohtml "ohtml:."

// ---------------------------------------------------------------------------
// Data types matching the JSON files
// ---------------------------------------------------------------------------

Simple_Data :: struct {
	Name:  string,
	Count: int,
}

Loop_Data :: struct {
	Items: []string,
}

Nested_Data :: struct {
	Show:    bool,
	Name:    string,
	Email:   string,
	IsAdmin: bool,
	Tags:    []string,
}

Escape_Data :: struct {
	URL:    string,
	Title:  string,
	JSVal:  string,
	CSSVal: string,
}

Complex_Item :: struct {
	Name:   string,
	Desc:   string,
	Active: bool,
}

Complex_Section :: struct {
	Heading: string,
	Items:   []Complex_Item,
}

Complex_Data :: struct {
	Title:    string,
	Sections: []Complex_Section,
	Footer:   string,
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

DATA_DIR :: "bench/data/"

read_file :: proc(path: string) -> string {
	data, ok := os.read_entire_file_from_filename(path)
	if !ok {
		fmt.panicf("failed to read file: %s", path)
	}
	return string(data)
}

unmarshal_file :: proc($T: typeid, path: string) -> T {
	data, ok := os.read_entire_file_from_filename(path)
	if !ok {
		fmt.panicf("failed to read file: %s", path)
	}
	result: T
	err := json.unmarshal(data, &result)
	if err != nil {
		fmt.panicf("failed to unmarshal %s: %v", path, err)
	}
	return result
}

// ---------------------------------------------------------------------------
// Benchmark runner
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
// Parse benchmarks
// ---------------------------------------------------------------------------

// Store loaded data at file scope so benchmark closures can capture them.
tpl_simple: string
tpl_loop: string
tpl_nested: string
tpl_escape: string
tpl_complex: string

data_simple: Simple_Data
data_loop: Loop_Data
data_nested: Nested_Data
data_escape: Escape_Data
data_complex: Complex_Data

bench_parse_simple :: proc(n: int) {
	for _ in 0 ..< n {
		t := ohtml.template_new("simple")
		ohtml.template_parse(t, tpl_simple)
		ohtml.template_destroy(t)
	}
}

bench_parse_loop :: proc(n: int) {
	for _ in 0 ..< n {
		t := ohtml.template_new("loop")
		ohtml.template_parse(t, tpl_loop)
		ohtml.template_destroy(t)
	}
}

bench_parse_complex :: proc(n: int) {
	for _ in 0 ..< n {
		t := ohtml.template_new("complex")
		ohtml.template_parse(t, tpl_complex)
		ohtml.template_destroy(t)
	}
}

// ---------------------------------------------------------------------------
// Execute benchmarks (pre-parsed + escaped)
// ---------------------------------------------------------------------------

bench_exec_simple :: proc(n: int) {
	t := ohtml.template_new("simple")
	ohtml.template_parse(t, tpl_simple)
	ohtml.escape_template(t)
	defer ohtml.template_destroy(t)
	for _ in 0 ..< n {
		result, _ := ohtml.execute_to_string(t, data_simple)
		delete(result)
	}
}

bench_exec_loop :: proc(n: int) {
	t := ohtml.template_new("loop")
	ohtml.template_parse(t, tpl_loop)
	ohtml.escape_template(t)
	defer ohtml.template_destroy(t)
	for _ in 0 ..< n {
		result, _ := ohtml.execute_to_string(t, data_loop)
		delete(result)
	}
}

bench_exec_nested :: proc(n: int) {
	t := ohtml.template_new("nested")
	ohtml.template_parse(t, tpl_nested)
	ohtml.escape_template(t)
	defer ohtml.template_destroy(t)
	for _ in 0 ..< n {
		result, _ := ohtml.execute_to_string(t, data_nested)
		delete(result)
	}
}

bench_exec_escape :: proc(n: int) {
	t := ohtml.template_new("escape")
	ohtml.template_parse(t, tpl_escape)
	ohtml.escape_template(t)
	defer ohtml.template_destroy(t)
	for _ in 0 ..< n {
		result, _ := ohtml.execute_to_string(t, data_escape)
		delete(result)
	}
}

bench_exec_complex :: proc(n: int) {
	t := ohtml.template_new("complex")
	ohtml.template_parse(t, tpl_complex)
	ohtml.escape_template(t)
	defer ohtml.template_destroy(t)
	for _ in 0 ..< n {
		result, _ := ohtml.execute_to_string(t, data_complex)
		delete(result)
	}
}

// ---------------------------------------------------------------------------
// Full pipeline (parse + escape + execute)
// ---------------------------------------------------------------------------

bench_full_simple :: proc(n: int) {
	for _ in 0 ..< n {
		result, _ := ohtml.render("simple", tpl_simple, data_simple)
		delete(result)
	}
}

bench_full_complex :: proc(n: int) {
	for _ in 0 ..< n {
		result, _ := ohtml.render("complex", tpl_complex, data_complex)
		delete(result)
	}
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

main :: proc() {
	// Load all files and data before benchmarking.
	tpl_simple = read_file(DATA_DIR + "simple.html")
	tpl_loop = read_file(DATA_DIR + "loop.html")
	tpl_nested = read_file(DATA_DIR + "nested.html")
	tpl_escape = read_file(DATA_DIR + "escape.html")
	tpl_complex = read_file(DATA_DIR + "complex.html")

	data_simple = unmarshal_file(Simple_Data, DATA_DIR + "simple.json")
	data_loop = unmarshal_file(Loop_Data, DATA_DIR + "loop.json")
	data_nested = unmarshal_file(Nested_Data, DATA_DIR + "nested.json")
	data_escape = unmarshal_file(Escape_Data, DATA_DIR + "escape.json")
	data_complex = unmarshal_file(Complex_Data, DATA_DIR + "complex.json")

	min_dur := time.Duration(1 * time.Second)

	fmt.println("=== Odin ohtml Benchmarks ===")
	fmt.println()

	fmt.println("--- Parse Only ---")
	bench("ParseSimple", bench_parse_simple, min_dur)
	bench("ParseLoop", bench_parse_loop, min_dur)
	bench("ParseComplex", bench_parse_complex, min_dur)
	fmt.println()

	fmt.println("--- Execute Only (pre-parsed + escaped) ---")
	bench("ExecSimple", bench_exec_simple, min_dur)
	bench("ExecLoop", bench_exec_loop, min_dur)
	bench("ExecNested", bench_exec_nested, min_dur)
	bench("ExecEscape", bench_exec_escape, min_dur)
	bench("ExecComplex", bench_exec_complex, min_dur)
	fmt.println()

	fmt.println("--- Full Pipeline (parse + escape + execute) ---")
	bench("FullSimple", bench_full_simple, min_dur)
	bench("FullComplex", bench_full_complex, min_dur)
}
