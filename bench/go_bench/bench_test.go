package go_bench

import (
	"bytes"
	"encoding/json"
	"html/template"
	"os"
	"testing"
)

// ---------------------------------------------------------------------------
// Data types matching the JSON files
// ---------------------------------------------------------------------------

type SimpleData struct {
	Name  string `json:"Name"`
	Count int    `json:"Count"`
}

type LoopData struct {
	Items []string `json:"Items"`
}

type NestedData struct {
	Show    bool     `json:"Show"`
	Name    string   `json:"Name"`
	Email   string   `json:"Email"`
	IsAdmin bool     `json:"IsAdmin"`
	Tags    []string `json:"Tags"`
}

type EscapeData struct {
	URL    string `json:"URL"`
	Title  string `json:"Title"`
	JSVal  string `json:"JSVal"`
	CSSVal string `json:"CSSVal"`
}

type ComplexItem struct {
	Name   string `json:"Name"`
	Desc   string `json:"Desc"`
	Active bool   `json:"Active"`
}

type ComplexSection struct {
	Heading string        `json:"Heading"`
	Items   []ComplexItem `json:"Items"`
}

type ComplexData struct {
	Title    string           `json:"Title"`
	Sections []ComplexSection `json:"Sections"`
	Footer   string           `json:"Footer"`
}

// ---------------------------------------------------------------------------
// Helpers — read file + unmarshal JSON (called once, outside benchmark loop)
// ---------------------------------------------------------------------------

const dataDir = "../data/"

func mustReadFile(path string) string {
	b, err := os.ReadFile(path)
	if err != nil {
		panic(err)
	}
	return string(b)
}

func mustUnmarshal[T any](path string) T {
	b, err := os.ReadFile(path)
	if err != nil {
		panic(err)
	}
	var v T
	if err := json.Unmarshal(b, &v); err != nil {
		panic(err)
	}
	return v
}

// ---------------------------------------------------------------------------
// Parse-only benchmarks
// ---------------------------------------------------------------------------

func BenchmarkParseSimple(b *testing.B) {
	tpl := mustReadFile(dataDir + "simple.html")

	for b.Loop() {
		template.Must(template.New("simple").Parse(tpl))
	}
}

func BenchmarkParseLoop(b *testing.B) {
	tpl := mustReadFile(dataDir + "loop.html")

	for b.Loop() {
		template.Must(template.New("loop").Parse(tpl))
	}
}

func BenchmarkParseComplex(b *testing.B) {
	tpl := mustReadFile(dataDir + "complex.html")

	for b.Loop() {
		template.Must(template.New("complex").Parse(tpl))
	}
}

// ---------------------------------------------------------------------------
// Execute-only benchmarks (pre-parsed, template.Execute includes escaping)
// ---------------------------------------------------------------------------

func BenchmarkExecSimple(b *testing.B) {
	tpl := template.Must(template.New("simple").Parse(mustReadFile(dataDir + "simple.html")))
	data := mustUnmarshal[SimpleData](dataDir + "simple.json")
	var buf bytes.Buffer

	for b.Loop() {
		buf.Reset()
		tpl.Execute(&buf, data)
	}
}

func BenchmarkExecLoop(b *testing.B) {
	tpl := template.Must(template.New("loop").Parse(mustReadFile(dataDir + "loop.html")))
	data := mustUnmarshal[LoopData](dataDir + "loop.json")
	var buf bytes.Buffer

	for b.Loop() {
		buf.Reset()
		tpl.Execute(&buf, data)
	}
}

func BenchmarkExecNested(b *testing.B) {
	tpl := template.Must(template.New("nested").Parse(mustReadFile(dataDir + "nested.html")))
	data := mustUnmarshal[NestedData](dataDir + "nested.json")
	var buf bytes.Buffer

	for b.Loop() {
		buf.Reset()
		tpl.Execute(&buf, data)
	}
}

func BenchmarkExecEscape(b *testing.B) {
	tpl := template.Must(template.New("escape").Parse(mustReadFile(dataDir + "escape.html")))
	data := mustUnmarshal[EscapeData](dataDir + "escape.json")
	var buf bytes.Buffer

	for b.Loop() {
		buf.Reset()
		tpl.Execute(&buf, data)
	}
}

func BenchmarkExecComplex(b *testing.B) {
	tpl := template.Must(template.New("complex").Parse(mustReadFile(dataDir + "complex.html")))
	data := mustUnmarshal[ComplexData](dataDir + "complex.json")
	var buf bytes.Buffer

	for b.Loop() {
		buf.Reset()
		tpl.Execute(&buf, data)
	}
}

// ---------------------------------------------------------------------------
// Full pipeline (parse + escape + execute)
// ---------------------------------------------------------------------------

func BenchmarkFullSimple(b *testing.B) {
	tplText := mustReadFile(dataDir + "simple.html")
	data := mustUnmarshal[SimpleData](dataDir + "simple.json")

	for b.Loop() {
		t := template.Must(template.New("simple").Parse(tplText))
		var buf bytes.Buffer
		t.Execute(&buf, data)
	}
}

func BenchmarkFullComplex(b *testing.B) {
	tplText := mustReadFile(dataDir + "complex.html")
	data := mustUnmarshal[ComplexData](dataDir + "complex.json")

	for b.Loop() {
		t := template.Must(template.New("complex").Parse(tplText))
		var buf bytes.Buffer
		t.Execute(&buf, data)
	}
}
