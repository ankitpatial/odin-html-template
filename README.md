# Odin Html Template
Odin version of Go html [template](https://pkg.go.dev/html/template@go1.26.0) package ported over using Claude code.

Its doing most of things i need at the momemnt.

## Features

- **Context-aware auto-escaping** -- automatically applies the correct escaping based on where a value appears (HTML body, attribute, JS, CSS, URL)
- **Full template language** -- if/else, range, with, variables, pipelines, define/template/block
- **Safe content types** -- `Safe_HTML`, `Safe_URL`, `Safe_CSS`, `Safe_JS`, etc. to bypass escaping for trusted content
- **Custom functions** -- register your own template functions via `Func_Map`
- **Layout composition** -- `block`/`define` for template inheritance (layouts, partials)
- **19 built-in functions** -- `and`, `or`, `not`, `eq`, `ne`, `lt`, `le`, `gt`, `ge`, `print`, `printf`, `println`, `len`, `index`, `call`, `html`, `js`, `urlquery`
- **Zero dependencies** beyond Odin's core library

## Quick Start

```odin
package main

import "core:fmt"
import "ohtml"

main :: proc() {
    Page :: struct {
        title: string,
        name:  string,
    }

    data := Page{title = "Hello", name = "World"}
    result, err := ohtml.render("page", "<h1>{{.title}}</h1><p>{{.name}}</p>", data)
    if err.kind != .None {
        fmt.eprintln("error:", err.msg)
        return
    }
    defer delete(result)

    fmt.println(result)
    // Output: <h1>Hello</h1><p>World</p>
}
```

## API

### Core

| Proc | Description |
|------|-------------|
| `render(name, text, data) -> (string, Error)` | Parse, escape, and execute in one call |
| `render_raw(name, text, data) -> (string, Error)` | Same but without auto-escaping (trusted templates only) |
| `template_new(name) -> ^Template` | Create a new template |
| `template_parse(t, text) -> (^Template, Error)` | Parse template source |
| `template_funcs(t, funcs)` | Register custom functions |
| `escape_template(t) -> Error` | Run the auto-escaping pass |
| `execute(t, writer, data) -> Error` | Execute template, write to `io.Writer` |
| `execute_to_string(t, data) -> (string, Error)` | Execute template, return string |
| `template_lookup(t, name) -> ^Template` | Look up a named sub-template |
| `template_destroy(t)` | Free all resources |

### Custom Functions

All custom functions use the uniform signature:

```odin
Template_Func :: #type proc(args: []any) -> (any, Error)
Func_Map :: map[string]Template_Func
```

```odin
upper_fn :: proc(args: []any) -> (ohtml.any, ohtml.Error) {
    s := args[0].(string)
    return strings.to_upper(s), {}
}

t := ohtml.template_new("page")
funcs := ohtml.Func_Map{"upper" = upper_fn}
ohtml.template_funcs(t, funcs)
ohtml.template_parse(t, `{{.name | upper}}`)
```

### Safe Content Types

Bypass auto-escaping for trusted content using distinct string types:

| Type | Use |
|------|-----|
| `Safe_HTML` | Trusted HTML markup |
| `Safe_CSS` | Trusted CSS rules |
| `Safe_JS` | Trusted JavaScript code |
| `Safe_JS_Str` | Trusted JS string literal |
| `Safe_URL` | Trusted URL |
| `Safe_Srcset` | Trusted srcset attribute |
| `Safe_HTML_Attr` | Trusted HTML attribute |

```odin
Page :: struct {
    bio: ohtml.Safe_HTML,
}

data := Page{bio = ohtml.Safe_HTML(`<em>bold</em>`)}
// {{.bio}} renders as <em>bold</em> without escaping
```

## Template Syntax

### Text Substitution

```
{{.title}}                         -- field access
{{.user.name}}                     -- nested field
{{.}}                              -- current value (dot)
```

### Conditionals

```
{{if .show}}visible{{end}}
{{if .admin}}Admin{{else}}User{{end}}
{{if eq .role "admin"}}...{{else if eq .role "editor"}}...{{else}}...{{end}}
```

### Loops

```
{{range .items}}{{.}}{{end}}
{{range $i, $v := .items}}[{{$i}}] {{$v}}{{end}}
{{range .items}}...{{else}}No items.{{end}}
```

### Scoped Context

```
{{with .user}}Name: {{.name}}{{end}}
{{with .user}}...{{else}}No user.{{end}}
```

### Variables

```
{{$name := "Odin"}}{{$name}}
```

### Pipelines

```
{{.name | printf "Hello, %s!"}}
{{.items | len}}
```

### Template Composition

```
{{/* Layout defines default blocks */}}
{{block "content" .}}Default content{{end}}

{{/* Page overrides them */}}
{{define "content"}}Page-specific content{{end}}

{{/* Call a named template */}}
{{template "header" .}}
```

### Comparisons and Logic

```
{{if eq .x 1}}...{{end}}
{{if ne .x .y}}...{{end}}
{{if lt .age 18}}...{{end}}
{{if and .admin .active}}...{{end}}
{{if or .a .b}}...{{end}}
{{if not .disabled}}...{{end}}
```

### Print Functions

```
{{print "a" "b"}}                  -- "a b"
{{printf "%s is %d" .name .age}}   -- formatted
{{println "line"}}                 -- with newline
```

### Whitespace Trimming

```
{{- .x}}       -- trim whitespace before
{{.x -}}       -- trim whitespace after
{{- .x -}}     -- trim both sides
```

### Comments

```
{{/* This produces no output */}}
```

## Auto-Escaping

The escaping pass analyzes each template action's HTML context and injects the appropriate escaper:

| Context | Example | Escaping |
|---------|---------|----------|
| HTML body | `<p>{{.x}}</p>` | `&`, `<`, `>`, `"`, `'` encoded |
| HTML attribute | `<div title="{{.x}}">` | Attribute-safe encoding |
| JavaScript | `<script>var x = "{{.x}}";</script>` | JS string escaping |
| CSS | `<style>{{.x}}</style>` | CSS hex escaping |
| URL | `<a href="{{.x}}">` | Percent-encoding, `javascript:` blocked |

Dangerous protocols like `javascript:` are automatically neutralized.

## Layout Composition

Combine a layout with page-specific content by concatenating sources (layout first, then page):

```odin
layout_src := read_file("layout.html")   // has {{block "content" .}}...{{end}}
page_src   := read_file("page.html")     // has {{define "content"}}...{{end}}

combined := strings.concatenate({layout_src, page_src})

t := ohtml.template_new("page")
ohtml.template_parse(t, combined)
ohtml.escape_template(t)
result, _ := ohtml.execute_to_string(t, data)
```

The layout's `block` provides defaults; the page's `define` overrides them.

## Examples

### E-commerce Web App

`examples/ecomm/` -- a full web app using [odin-http](https://github.com/laytan/odin-http) with:

- Product listing, detail, and cart pages
- Login and forgot-password flows
- Layout/page template composition
- A `/capability` page demonstrating every template feature

```sh
odin run examples/ecomm
# Visit http://localhost:8080
```


## Testing

```sh
odin test tests
```

## License

MIT
