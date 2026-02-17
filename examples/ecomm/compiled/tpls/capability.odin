package tpls

import "core:io"
import "core:fmt"

render_capability :: proc(w: io.Writer, data: ^CapabilityData) {
	io.write_string(w, "<html lang=\"en\"> <head> <meta charset=\"utf-8\"> <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\"> <title>")
	io.write_string(w, html_escape(data.title))
	io.write_string(w, "— ShopOdin</title> <style> *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; } body { font-family: system-ui, sans-serif; color: #1a1a1a; background: #f5f5f5; } a { color: #2563eb; text-decoration: none; } a:hover { text-decoration: underline; } .header { background: #fff; border-bottom: 1px solid #e5e5e5; padding: 1rem 2rem; display: flex; align-items: center; justify-content: space-between; } .header h1 { font-size: 1.25rem; } .header nav a { margin-left: 1.5rem; font-size: 0.9rem; } .container { max-width: 1100px; margin: 0 auto; padding: 2rem; } .footer { text-align: center; padding: 2rem; color: #666; font-size: 0.85rem; border-top: 1px solid #e5e5e5; margin-top: 3rem; } </style>")
	// {template "extra_head"}
	io.write_string(w, "<style> .demo { margin-bottom: 2.5rem; } .demo h2 { font-size: 1.35rem; border-bottom: 2px solid #2563eb; padding-bottom: 0.4rem; margin-bottom: 1rem; color: #1e40af; } .demo h3 { font-size: 1rem; margin: 1rem 0 0.5rem; color: #444; } .box { background: #fff; border-radius: 8px; padding: 1.25rem; margin-bottom: 0.75rem; box-shadow: 0 1px 3px rgba(0,0,0,0.08); font-family: monospace; font-size: 0.9rem; white-space: pre-wrap; word-break: break-all; } .box .label { font-family: system-ui, sans-serif; font-weight: 600; color: #666; font-size: 0.8rem; display: block; margin-bottom: 0.35rem; } .grid2 { display: grid; grid-template-columns: 1fr 1fr; gap: 0.75rem; } .tag { display: inline-block; background: #e5e7eb; border-radius: 4px; padding: 2px 8px; font-size: 0.8rem; margin: 2px; } .active { background: #d1fae5; color: #065f46; } .inactive { background: #fee2e2; color: #991b1b; } table.spec { width: 100%; border-collapse: collapse; background: #fff; border-radius: 8px; overflow: hidden; box-shadow: 0 1px 3px rgba(0,0,0,0.08); } table.spec th { background: #f3f4f6; text-align: left; padding: 0.5rem 1rem; font-size: 0.85rem; } table.spec td { padding: 0.5rem 1rem; border-top: 1px solid #eee; font-size: 0.9rem; } .esc-compare { display: grid; grid-template-columns: 1fr 1fr; gap: 0.75rem; } .esc-compare .box { font-size: 0.8rem; } .tpl { background: #eff6ff; border: 1px solid #bfdbfe; border-radius: 6px; padding: 0.5rem 0.75rem; font-family: monospace; font-size: 0.8rem; margin-bottom: 0.5rem; color: #1e40af; } .intro { background: #fff; border-radius: 8px; padding: 1.5rem; margin-bottom: 2rem; box-shadow: 0 1px 3px rgba(0,0,0,0.08); } .intro p { line-height: 1.6; color: #444; } </style>")
	io.write_string(w, "</head> <body> <header class=\"header\"> <h1><a href=\"/\">ShopOdin</a></h1> <nav> <a href=\"/\">Home</a> <a href=\"/products\">Products</a>")
	if len(data.user_name) > 0 {
		io.write_string(w, "<a href=\"/account\">")
		io.write_string(w, html_escape(data.user_name))
		io.write_string(w, "</a>")
	} else {
		io.write_string(w, "<a href=\"/login\">Sign In</a>")
	}
	io.write_string(w, "<a href=\"/cart\">Cart (")
	buf_0: [32]u8
	io.write_string(w, write_int(buf_0[:], i64(data.cart_count)))
	io.write_string(w, ")</a> <a href=\"/capability\">Capability</a> </nav> </header> <div class=\"container\">")
	// {template "content"}
	io.write_string(w, "<div class=\"intro\"> <h1>ohtml Template Engine — Capability Demo</h1> <p>This page demonstrates every feature of <strong>ohtml</strong>, the Odin port of Go's html/template. All examples below are rendered live by the template engine with auto-escaping enabled.</p> </div>")
	io.write_string(w, "<div class=\"demo\"> <h2>1. Text Substitution</h2> <p class=\"tpl\">")
	io.write_string(w, "{{.greeting}}")
	io.write_string(w, "</p> <div class=\"box\">")
	io.write_string(w, data.greeting)
	io.write_string(w, "</div> <h3>Multiple fields</h3> <p class=\"tpl\">")
	io.write_string(w, "{{.user_name}} has {{.count}} items at ${{.price}} each")
	io.write_string(w, "</p> <div class=\"box\">")
	io.write_string(w, data.user_name)
	io.write_string(w, "has")
	buf_1: [32]u8
	io.write_string(w, write_int(buf_1[:], i64(data.count)))
	io.write_string(w, "items at $")
	fmt.wprintf(w, "%v", data.price)
	io.write_string(w, "each</div> </div>")
	io.write_string(w, "<div class=\"demo\"> <h2>2. Conditionals (if / else / else if)</h2> <h3>Simple if</h3> <p class=\"tpl\">")
	io.write_string(w, "{{if .is_admin}}<b>Admin</b>{{end}}")
	io.write_string(w, "</p> <div class=\"box\">")
	if data.is_admin {
		io.write_string(w, "<b>Admin</b>")
	}
	io.write_string(w, "</div> <h3>If / else</h3> <p class=\"tpl\">")
	io.write_string(w, "{{if .is_admin}}Admin{{else}}Regular User{{end}}")
	io.write_string(w, "</p> <div class=\"box\">")
	if data.is_admin {
		io.write_string(w, "Admin")
	} else {
		io.write_string(w, "Regular User")
	}
	io.write_string(w, "</div> <h3>Else-if chain</h3> <p class=\"tpl\">")
	io.write_string(w, "{{if eq .role \"admin\"}}Full Access{{else if eq .role \"editor\"}}Edit Access{{else}}Read Only{{end}}")
	io.write_string(w, "</p> <div class=\"box\">")
	if data.role == "admin" {
		io.write_string(w, "Full Access")
	} else {
		if data.role == "editor" {
			io.write_string(w, "Edit Access")
		} else {
			io.write_string(w, "Read Only")
		}
	}
	io.write_string(w, "</div> <h3>Truthiness — empty string is false</h3> <p class=\"tpl\">")
	io.write_string(w, "{{if .empty_list}}has items{{else}}empty{{end}}")
	io.write_string(w, "</p> <div class=\"box\">")
	if len(data.empty_list) > 0 {
		io.write_string(w, "has items")
	} else {
		io.write_string(w, "empty")
	}
	io.write_string(w, "</div> </div>")
	io.write_string(w, "<div class=\"demo\"> <h2>3. Range Loops</h2> <h3>Range over strings</h3> <p class=\"tpl\">")
	io.write_string(w, "{{range .items}}<span class=\"tag\">{{.}}</span>{{end}}")
	io.write_string(w, "</p> <div class=\"box\">")
	for tmp_0 in data.items {
		io.write_string(w, "<span class=\"tag\">")
		io.write_string(w, tmp_0)
		io.write_string(w, "</span>")
	}
	io.write_string(w, "</div> <h3>Range with index variable</h3> <p class=\"tpl\">")
	io.write_string(w, "{{range $i, $v := .items}}[{{$i}}] {{$v}}  {{end}}")
	io.write_string(w, "</p> <div class=\"box\">")
	for _v_v, _v_i in data.items {
		io.write_string(w, "[")
		io.write_string(w, fmt.aprintf("%v", _v_i))
		io.write_string(w, "]")
		io.write_string(w, fmt.aprintf("%v", _v_v))
	}
	io.write_string(w, "</div> <h3>Range over structs</h3> <table class=\"spec\"> <tr><th>Name</th><th>Value</th><th>Status</th></tr>")
	for tmp_1 in data.demo_items {
		io.write_string(w, "<tr> <td>")
		io.write_string(w, tmp_1.name)
		io.write_string(w, "</td> <td>")
		io.write_string(w, tmp_1.value)
		io.write_string(w, "</td> <td>")
		if tmp_1.active {
			io.write_string(w, "<span class=\"tag active\">Active</span>")
		} else {
			io.write_string(w, "<span class=\"tag inactive\">Inactive</span>")
		}
		io.write_string(w, "</td> </tr>")
	}
	io.write_string(w, "</table> <h3>Range with else (empty list)</h3> <p class=\"tpl\">")
	io.write_string(w, "{{range .empty_list}}...{{else}}No items found.{{end}}")
	io.write_string(w, "</p> <div class=\"box\">")
	if len(data.empty_list) > 0 {
		for tmp_2 in data.empty_list {
			io.write_string(w, "...")
		}
	} else {
		io.write_string(w, "No items found.")
	}
	io.write_string(w, "</div> </div>")
	io.write_string(w, "<div class=\"demo\"> <h2>4. With (Scoped Context)</h2> <h3>With narrows dot to a field</h3> <p class=\"tpl\">")
	io.write_string(w, "{{with .greeting}}The greeting is: {{.}}{{end}}")
	io.write_string(w, "</p> <div class=\"box\">")
	if len(data.greeting) > 0 {
		io.write_string(w, "The greeting is:")
		io.write_string(w, data.greeting)
	}
	io.write_string(w, "</div> <h3>With / else fallback</h3> <p class=\"tpl\">")
	io.write_string(w, "{{with .empty_list}}Has items{{else}}Nothing here{{end}}")
	io.write_string(w, "</p> <div class=\"box\">")
	if len(data.empty_list) > 0 {
		io.write_string(w, "Has items")
	} else {
		io.write_string(w, "Nothing here")
	}
	io.write_string(w, "</div> </div>")
	io.write_string(w, "<div class=\"demo\"> <h2>5. Variables</h2> <h3>Declare and use</h3> <p class=\"tpl\">")
	io.write_string(w, "{{$lang := \"Odin\"}}Language: {{$lang}}")
	io.write_string(w, "</p> <div class=\"box\">")
	_v_lang : string = "Odin"
	io.write_string(w, "Language:")
	io.write_string(w, fmt.aprintf("%v", _v_lang))
	io.write_string(w, "</div> <h3>Variables in range</h3> <p class=\"tpl\">")
	io.write_string(w, "{{range $i, $v := .items}}{{if $i}}, {{end}}{{$v}}{{end}}")
	io.write_string(w, "</p> <div class=\"box\">")
	for _v_v, _v_i in data.items {
		if _v_i != 0 {
			io.write_string(w, ",")
		}
		io.write_string(w, fmt.aprintf("%v", _v_v))
	}
	io.write_string(w, "</div> </div>")
	io.write_string(w, "<div class=\"demo\"> <h2>6. Pipelines</h2> <h3>Pipe to function</h3> <p class=\"tpl\">")
	io.write_string(w, "{{.items | len}}")
	io.write_string(w, "</p> <div class=\"box\">Item count:")
	buf_2: [32]u8
	io.write_string(w, write_int(buf_2[:], i64(len(data.items))))
	io.write_string(w, "</div> <h3>Chained pipes</h3> <p class=\"tpl\">")
	io.write_string(w, "{{.user_name | printf \"Welcome, %s!\"}}")
	io.write_string(w, "</p> <div class=\"box\">")
	io.write_string(w, fmt.aprintf("Welcome, %s!", data.user_name))
	io.write_string(w, "</div> </div>")
	io.write_string(w, "<div class=\"demo\"> <h2>7. Comparison Functions</h2> <div class=\"grid2\"> <div class=\"box\"><span class=\"label\">eq .count 42</span>")
	if data.count == 42 {
		io.write_string(w, "true")
	} else {
		io.write_string(w, "false")
	}
	io.write_string(w, "</div> <div class=\"box\"><span class=\"label\">ne .count 99</span>")
	if data.count != 99 {
		io.write_string(w, "true")
	} else {
		io.write_string(w, "false")
	}
	io.write_string(w, "</div> <div class=\"box\"><span class=\"label\">lt .count 100</span>")
	if data.count < 100 {
		io.write_string(w, "true")
	} else {
		io.write_string(w, "false")
	}
	io.write_string(w, "</div> <div class=\"box\"><span class=\"label\">ge .count 42</span>")
	if data.count >= 42 {
		io.write_string(w, "true")
	} else {
		io.write_string(w, "false")
	}
	io.write_string(w, "</div> <div class=\"box\"><span class=\"label\">gt .price 10.0</span>")
	if data.price > 10.0 {
		io.write_string(w, "true")
	} else {
		io.write_string(w, "false")
	}
	io.write_string(w, "</div> <div class=\"box\"><span class=\"label\">le .price 20.0</span>")
	if data.price <= 20.0 {
		io.write_string(w, "true")
	} else {
		io.write_string(w, "false")
	}
	io.write_string(w, "</div> </div> <h3>Multi-arg eq (matches any)</h3> <p class=\"tpl\">")
	io.write_string(w, "{{if eq .role \"admin\" \"editor\" \"mod\"}}privileged{{else}}regular{{end}}")
	io.write_string(w, "</p> <div class=\"box\">")
	if (data.role == "admin" || data.role == "editor" || data.role == "mod") {
		io.write_string(w, "privileged")
	} else {
		io.write_string(w, "regular")
	}
	io.write_string(w, "</div> </div>")
	io.write_string(w, "<div class=\"demo\"> <h2>8. Boolean Logic (and / or / not)</h2> <div class=\"grid2\"> <div class=\"box\"><span class=\"label\">and .is_admin .user_name</span>")
	if data.is_admin && len(data.user_name) > 0 {
		io.write_string(w, "true")
	} else {
		io.write_string(w, "false")
	}
	io.write_string(w, "</div> <div class=\"box\"><span class=\"label\">or .empty_list .greeting</span>")
	if len(data.empty_list) > 0 || len(data.greeting) > 0 {
		io.write_string(w, "true")
	} else {
		io.write_string(w, "false")
	}
	io.write_string(w, "</div> <div class=\"box\"><span class=\"label\">not .is_admin</span>")
	if !(data.is_admin) {
		io.write_string(w, "true")
	} else {
		io.write_string(w, "false")
	}
	io.write_string(w, "</div> <div class=\"box\"><span class=\"label\">not .empty_list</span>")
	if len(data.empty_list) == 0 {
		io.write_string(w, "true")
	} else {
		io.write_string(w, "false")
	}
	io.write_string(w, "</div> </div> </div>")
	io.write_string(w, "<div class=\"demo\"> <h2>9. Print Functions</h2> <div class=\"grid2\"> <div class=\"box\"><span class=\"label\">print</span>")
	io.write_string(w, fmt.aprint("Hello", "World"))
	io.write_string(w, "</div> <div class=\"box\"><span class=\"label\">printf</span>")
	io.write_string(w, fmt.aprintf("%s has %d items at $%.2f", data.user_name, data.count, data.price))
	io.write_string(w, "</div> <div class=\"box\"><span class=\"label\">println</span>[")
	io.write_string(w, fmt.aprintln("a line"))
	io.write_string(w, "]</div> <div class=\"box\"><span class=\"label\">printf format</span>")
	io.write_string(w, fmt.aprintf("hex: %x  pad: %04d", data.count, data.count))
	io.write_string(w, "</div> </div> </div>")
	io.write_string(w, "<div class=\"demo\"> <h2>10. len and index</h2> <div class=\"grid2\"> <div class=\"box\"><span class=\"label\">len .items</span>")
	buf_3: [32]u8
	io.write_string(w, write_int(buf_3[:], i64(len(data.items))))
	io.write_string(w, "</div> <div class=\"box\"><span class=\"label\">len .greeting</span>")
	buf_4: [32]u8
	io.write_string(w, write_int(buf_4[:], i64(len(data.greeting))))
	io.write_string(w, "</div> <div class=\"box\"><span class=\"label\">index .items 0</span>")
	io.write_string(w, fmt.aprintf("%v", data.items[0]))
	io.write_string(w, "</div> <div class=\"box\"><span class=\"label\">index .items 3</span>")
	io.write_string(w, fmt.aprintf("%v", data.items[3]))
	io.write_string(w, "</div> </div> </div>")
	io.write_string(w, "<div class=\"demo\"> <h2>11. Nested Struct Access</h2> <p class=\"tpl\">")
	io.write_string(w, "{{range .products}}{{.name}} ({{.category}}) — {{range .tags}}[{{.}}] {{end}}{{end}}")
	io.write_string(w, "</p> <div class=\"box\">")
	for tmp_3 in data.products {
		io.write_string(w, tmp_3.name)
		io.write_string(w, "(")
		io.write_string(w, tmp_3.category)
		io.write_string(w, ") —")
		for tmp_4 in tmp_3.tags {
			io.write_string(w, "[")
			io.write_string(w, tmp_4)
			io.write_string(w, "]")
		}
	}
	io.write_string(w, "</div> </div>")
	io.write_string(w, "<div class=\"demo\"> <h2>12. Template Define / Call</h2> <p class=\"tpl\">")
	io.write_string(w, "{{define \"badge\"}}<span class=\"tag ...\">{{.name}}: {{.value}}</span>{{end}}")
	io.write_string(w, "</p> <p class=\"tpl\">")
	io.write_string(w, "{{range .demo_items}}{{template \"badge\" .}}{{end}}")
	io.write_string(w, "</p> <div class=\"box\">")
	for tmp_5 in data.demo_items {
		// {template "badge"}
		io.write_string(w, "<span class=\"tag")
		if tmp_5.active {
			io.write_string(w, "active")
		} else {
			io.write_string(w, "inactive")
		}
		io.write_string(w, "\">")
		io.write_string(w, tmp_5.name)
		io.write_string(w, ":")
		io.write_string(w, tmp_5.value)
		io.write_string(w, "</span>")
	}
	io.write_string(w, "</div> </div>")
	io.write_string(w, "<div class=\"demo\"> <h2>13. Block (Define with Default)</h2> <p class=\"tpl\">")
	io.write_string(w, "{{block \"sidebar\" .}}Default sidebar content{{end}}")
	io.write_string(w, "</p> <div class=\"box\">")
	// {template "sidebar"}
	io.write_string(w, "Default sidebar content")
	io.write_string(w, "</div> <p><small>The shop layout uses <code>block</code> for <code>extra_head</code> and <code>content</code> — this page overrides both.</small></p> </div>")
	io.write_string(w, "<div class=\"demo\"> <h2>14. HTML Auto-Escaping (XSS Prevention)</h2> <p>The template engine automatically escapes dangerous content based on context.</p> <h3>Script injection blocked</h3> <p class=\"tpl\">")
	io.write_string(w, "{{.html_dangerous}}")
	io.write_string(w, "</p> <div class=\"esc-compare\"> <div class=\"box\"><span class=\"label\">Raw input</span>&lt;script&gt;alert(\"xss\")&lt;/script&gt;</div> <div class=\"box\"><span class=\"label\">Rendered (escaped)</span>")
	io.write_string(w, data.html_dangerous)
	io.write_string(w, "</div> </div> <h3>Attribute injection blocked</h3> <p class=\"tpl\">")
	io.write_string(w, "<div title=\"{{.bio}}\">...</div>")
	io.write_string(w, "</p> <div class=\"box\"><span class=\"label\">Rendered</span><div title=\"")
	io.write_string(w, data.bio)
	io.write_string(w, "\">Hover to see escaped title attribute</div></div> <h3>Ampersands and special chars</h3> <div class=\"box\">")
	io.write_string(w, data.bio)
	io.write_string(w, "</div> </div>")
	io.write_string(w, "<div class=\"demo\"> <h2>15. Safe Content Types</h2> <p>Trusted content can bypass escaping using <code>Safe_HTML</code>, <code>Safe_URL</code>, etc.</p> <h3>Safe_HTML — renders raw HTML</h3> <p class=\"tpl\">")
	io.write_string(w, "{{.safe_html}}")
	io.write_string(w, "</p> <div class=\"box\">")
	io.write_string(w, data.safe_html)
	io.write_string(w, "</div> <h3>Safe_URL — preserves URL structure</h3> <p class=\"tpl\">")
	io.write_string(w, "<a href=\"{{.safe_url}}\">Link</a>")
	io.write_string(w, "</p> <div class=\"box\"><a href=\"")
	io.write_string(w, data.safe_url)
	io.write_string(w, "\">")
	io.write_string(w, data.safe_url)
	io.write_string(w, "</a></div> </div>")
	io.write_string(w, "<div class=\"demo\"> <h2>16. URL Context Escaping</h2> <h3>Dangerous protocol blocked</h3> <p class=\"tpl\">")
	io.write_string(w, "<a href=\"{{.url_dangerous}}\">click</a>")
	io.write_string(w, "</p> <div class=\"box\"><span class=\"label\">javascript: URL becomes safe</span><a href=\"")
	io.write_string(w, data.url_dangerous)
	io.write_string(w, "\">click me (safe!)</a></div> <h3>Query params percent-encoded</h3> <p class=\"tpl\">")
	io.write_string(w, "<a href=\"/search?q={{.bio}}\">search</a>")
	io.write_string(w, "</p> <div class=\"box\"><a href=\"/search?q=")
	io.write_string(w, data.bio)
	io.write_string(w, "\">search for bio text</a></div> </div>")
	io.write_string(w, "<div class=\"demo\"> <h2>17. JavaScript Context Escaping</h2> <p class=\"tpl\">")
	io.write_string(w, "<script>var user = \"{{.js_dangerous}}\";</script>")
	io.write_string(w, "</p> <div class=\"box\"><span class=\"label\">Rendered (view page source to see)</span><script>var _demo_user = \"")
	io.write_string(w, data.js_dangerous)
	io.write_string(w, "\";</script>JS variable safely set (check page source)</div> </div>")
	io.write_string(w, "<div class=\"demo\"> <h2>18. Whitespace Trimming</h2> <div class=\"grid2\"> <div class=\"box\"><span class=\"label\">trim left:")
	io.write_string(w, "hello  {{- \" world\"}}")
	io.write_string(w, "</span>[ hello")
	io.write_string(w, " world")
	io.write_string(w, "]</div> <div class=\"box\"><span class=\"label\">trim right:")
	io.write_string(w, "{{\"hello \" -}}  world")
	io.write_string(w, "</span>[")
	io.write_string(w, "hello ")
	io.write_string(w, "world ]</div> <div class=\"box\"><span class=\"label\">trim both:")
	io.write_string(w, "{{- \"compact\" -}}")
	io.write_string(w, "</span>[")
	io.write_string(w, "compact")
	io.write_string(w, "]</div> <div class=\"box\"><span class=\"label\">no trim</span>[")
	io.write_string(w, "spaced")
	io.write_string(w, "]</div> </div> </div>")
	io.write_string(w, "<div class=\"demo\"> <h2>19. Comments</h2> <p class=\"tpl\">")
	io.write_string(w, "before {{/* invisible comment */}} after")
	io.write_string(w, "</p> <div class=\"box\">before")
	io.write_string(w, "after</div> <p><small>Comments produce no output. This entire page also uses comments to separate sections.</small></p> </div>")
	io.write_string(w, "<div class=\"demo\"> <h2>20. Builtin Escape Functions</h2> <div class=\"grid2\"> <div class=\"box\"><span class=\"label\">html</span>")
	io.write_string(w, html_escape(data.html_dangerous))
	io.write_string(w, "</div> <div class=\"box\"><span class=\"label\">urlquery</span>")
	io.write_string(w, url_query_escape(data.bio))
	io.write_string(w, "</div> </div> </div>")
	io.write_string(w, "<div class=\"demo\"> <h2>21. Complex — Conditionals Inside Range</h2> <table class=\"spec\"> <tr><th>Product</th><th>Price</th><th>Status</th><th>Tags</th></tr>")
	for tmp_6 in data.products {
		io.write_string(w, "<tr> <td><a href=\"/product?id=")
		io.write_string(w, tmp_6.id)
		io.write_string(w, "\">")
		io.write_string(w, tmp_6.name)
		io.write_string(w, "</a></td> <td>")
		io.write_string(w, fmt.aprintf("$%.2f", tmp_6.price))
		io.write_string(w, "</td> <td>")
		if tmp_6.in_stock {
			io.write_string(w, "<span class=\"tag active\">In Stock</span>")
		} else {
			io.write_string(w, "<span class=\"tag inactive\">Sold Out</span>")
		}
		io.write_string(w, "</td> <td>")
		for _v_t, _v_i in tmp_6.tags {
			if _v_i != 0 {
				io.write_string(w, ",")
			}
			io.write_string(w, fmt.aprintf("%v", _v_t))
		}
		io.write_string(w, "</td> </tr>")
	}
	io.write_string(w, "</table> </div>")
	io.write_string(w, "<div class=\"demo\"> <h2>22. Layout Composition</h2> <div class=\"box\" style=\"font-family: system-ui;\"> <span class=\"label\">How this page works</span> This page uses <code>shop_layout.html</code> as the base layout, which defines <code>")
	io.write_string(w, "{{block \"extra_head\" .}}")
	io.write_string(w, "</code> and <code>")
	io.write_string(w, "{{block \"content\" .}}")
	io.write_string(w, "</code>. The <code>capability.html</code> template overrides both blocks using <code>")
	io.write_string(w, "{{define \"extra_head\"}}")
	io.write_string(w, "</code> and <code>")
	io.write_string(w, "{{define \"content\"}}")
	io.write_string(w, "</code>. The layout provides the header, nav, and footer. The page provides the styles and body. </div> </div>")
	io.write_string(w, "</div> <footer class=\"footer\"> <p>©")
	buf_5: [32]u8
	io.write_string(w, write_int(buf_5[:], i64(data.year)))
	io.write_string(w, "ShopOdin. All rights reserved.</p> </footer> </body> </html>")
}
