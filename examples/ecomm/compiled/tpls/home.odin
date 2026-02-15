package tpls

import "core:io"
import "core:fmt"

render_home :: proc(w: io.Writer, data: ^Home_Data) {
	io.write_string(w, "<!--\n@type_of(cart_count) int\n@type_of(year) int\n-->\n<html lang=\"en\">\n<head>\n  <meta charset=\"utf-8\">\n  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n  <title>")
	io.write_string(w, _ohtml_html_escape(data.title))
	io.write_string(w, " — ShopOdin</title>\n  <style>\n    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }\n    body { font-family: system-ui, sans-serif; color: #1a1a1a; background: #f5f5f5; }\n    a { color: #2563eb; text-decoration: none; }\n    a:hover { text-decoration: underline; }\n    .header { background: #fff; border-bottom: 1px solid #e5e5e5; padding: 1rem 2rem; display: flex; align-items: center; justify-content: space-between; }\n    .header h1 { font-size: 1.25rem; }\n    .header nav a { margin-left: 1.5rem; font-size: 0.9rem; }\n    .container { max-width: 1100px; margin: 0 auto; padding: 2rem; }\n    .footer { text-align: center; padding: 2rem; color: #666; font-size: 0.85rem; border-top: 1px solid #e5e5e5; margin-top: 3rem; }\n  </style>\n  ")
	// {template "extra_head"}
	io.write_string(w, "\n<style>\n  .hero { background: linear-gradient(135deg, #2563eb, #7c3aed); color: #fff; padding: 3rem 2rem; border-radius: 8px; margin-bottom: 2rem; }\n  .hero h2 { font-size: 2rem; margin-bottom: 0.5rem; }\n  .hero p { opacity: 0.9; }\n  .grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 1.5rem; }\n  .card { background: #fff; border-radius: 8px; padding: 1.5rem; box-shadow: 0 1px 3px rgba(0,0,0,0.1); }\n  .card h3 { margin-bottom: 0.5rem; }\n  .price { font-size: 1.25rem; font-weight: 700; color: #059669; }\n  .stock { color: #059669; font-size: 0.85rem; }\n  .out { color: #dc2626; font-size: 0.85rem; }\n  .tags { margin-top: 0.5rem; }\n  .tag { display: inline-block; background: #e5e7eb; border-radius: 4px; padding: 2px 8px; font-size: 0.75rem; margin-right: 4px; }\n  .section-title { font-size: 1.5rem; margin-bottom: 1rem; }\n</style>\n")
	io.write_string(w, "\n</head>\n<body>\n\n<header class=\"header\">\n  <h1><a href=\"/\">ShopOdin</a></h1>\n  <nav>\n    <a href=\"/\">Home</a>\n    <a href=\"/products\">Products</a>\n    ")
	if len(data.user_name) > 0 {
		io.write_string(w, "<a href=\"/account\">")
		io.write_string(w, _ohtml_html_escape(data.user_name))
		io.write_string(w, "</a>")
	} else {
		io.write_string(w, "<a href=\"/login\">Sign In</a>")
	}
	io.write_string(w, "\n    <a href=\"/cart\">Cart (")
	_buf_0: [32]u8
	io.write_string(w, _ohtml_write_int(_buf_0[:], i64(data.cart_count)))
	io.write_string(w, ")</a>\n    <a href=\"/capability\">Capability</a>\n  </nav>\n</header>\n\n<div class=\"container\">\n  ")
	// {template "content"}
	io.write_string(w, "\n<section class=\"hero\">\n  <h2>Welcome to ShopOdin</h2>\n  <p>Quality products, powered by the Odin programming language.</p>\n</section>\n\n<h2 class=\"section-title\">Featured Products</h2>\n\n")
	if len(data.products) > 0 {
		io.write_string(w, "\n<div class=\"grid\">\n  ")
		for _tmp_0 in data.products {
			io.write_string(w, "\n  <div class=\"card\">\n    <h3><a href=\"/product?id=")
			io.write_string(w, _tmp_0.id)
			io.write_string(w, "\">")
			io.write_string(w, _tmp_0.name)
			io.write_string(w, "</a></h3>\n    <p class=\"price\">")
			io.write_string(w, fmt.aprintf("$%.2f", _tmp_0.price))
			io.write_string(w, "</p>\n    <p>")
			io.write_string(w, _tmp_0.description)
			io.write_string(w, "</p>\n    ")
			if _tmp_0.in_stock {
				io.write_string(w, "<span class=\"stock\">In Stock</span>")
			} else {
				io.write_string(w, "<span class=\"out\">Sold Out</span>")
			}
			io.write_string(w, "\n    ")
			if len(_tmp_0.tags) > 0 {
				io.write_string(w, "<div class=\"tags\">")
				for _tmp_1 in _tmp_0.tags {
					io.write_string(w, "<span class=\"tag\">")
					io.write_string(w, _tmp_1)
					io.write_string(w, "</span>")
				}
				io.write_string(w, "</div>")
			}
			io.write_string(w, "\n  </div>\n  ")
		}
		io.write_string(w, "\n</div>\n")
	} else {
		io.write_string(w, "\n<p>No products available. Check back soon!</p>\n")
	}
	io.write_string(w, "\n")
	io.write_string(w, "\n</div>\n\n<footer class=\"footer\">\n  <p>© ")
	_buf_1: [32]u8
	io.write_string(w, _ohtml_write_int(_buf_1[:], i64(data.year)))
	io.write_string(w, " ShopOdin. All rights reserved.</p>\n</footer>\n\n</body>\n</html>\n")
	io.write_string(w, "\n\n")
	io.write_string(w, "\n")
}
