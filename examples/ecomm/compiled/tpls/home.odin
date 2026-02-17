package tpls

import "core:io"
import "core:fmt"

render_home :: proc(w: io.Writer, data: ^HomeData) {
	io.write_string(w, "<html lang=\"en\"> <head> <meta charset=\"utf-8\"> <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\"> <title>")
	io.write_string(w, html_escape(data.title))
	io.write_string(w, "— ShopOdin</title> <style> *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; } body { font-family: system-ui, sans-serif; color: #1a1a1a; background: #f5f5f5; } a { color: #2563eb; text-decoration: none; } a:hover { text-decoration: underline; } .header { background: #fff; border-bottom: 1px solid #e5e5e5; padding: 1rem 2rem; display: flex; align-items: center; justify-content: space-between; } .header h1 { font-size: 1.25rem; } .header nav a { margin-left: 1.5rem; font-size: 0.9rem; } .container { max-width: 1100px; margin: 0 auto; padding: 2rem; } .footer { text-align: center; padding: 2rem; color: #666; font-size: 0.85rem; border-top: 1px solid #e5e5e5; margin-top: 3rem; } </style>")
	// {template "extra_head"}
	io.write_string(w, "<style> .hero { background: linear-gradient(135deg, #2563eb, #7c3aed); color: #fff; padding: 3rem 2rem; border-radius: 8px; margin-bottom: 2rem; } .hero h2 { font-size: 2rem; margin-bottom: 0.5rem; } .hero p { opacity: 0.9; } .grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 1.5rem; } .card { background: #fff; border-radius: 8px; padding: 1.5rem; box-shadow: 0 1px 3px rgba(0,0,0,0.1); } .card h3 { margin-bottom: 0.5rem; } .price { font-size: 1.25rem; font-weight: 700; color: #059669; } .stock { color: #059669; font-size: 0.85rem; } .out { color: #dc2626; font-size: 0.85rem; } .tags { margin-top: 0.5rem; } .tag { display: inline-block; background: #e5e7eb; border-radius: 4px; padding: 2px 8px; font-size: 0.75rem; margin-right: 4px; } .section-title { font-size: 1.5rem; margin-bottom: 1rem; } </style>")
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
	io.write_string(w, "<section class=\"hero\"> <h2>Welcome to ShopOdin</h2> <p>Quality products, powered by the Odin programming language.</p> </section> <h2 class=\"section-title\">Featured Products</h2>")
	if len(data.products) > 0 {
		io.write_string(w, "<div class=\"grid\">")
		for tmp_0 in data.products {
			io.write_string(w, "<div class=\"card\"> <h3><a href=\"/product?id=")
			io.write_string(w, tmp_0.id)
			io.write_string(w, "\">")
			io.write_string(w, tmp_0.name)
			io.write_string(w, "</a></h3> <p class=\"price\">")
			io.write_string(w, fmt.aprintf("$%.2f", tmp_0.price))
			io.write_string(w, "</p> <p>")
			io.write_string(w, tmp_0.description)
			io.write_string(w, "</p>")
			if tmp_0.in_stock {
				io.write_string(w, "<span class=\"stock\">In Stock</span>")
			} else {
				io.write_string(w, "<span class=\"out\">Sold Out</span>")
			}
			if len(tmp_0.tags) > 0 {
				io.write_string(w, "<div class=\"tags\">")
				for tmp_1 in tmp_0.tags {
					io.write_string(w, "<span class=\"tag\">")
					io.write_string(w, tmp_1)
					io.write_string(w, "</span>")
				}
				io.write_string(w, "</div>")
			}
			io.write_string(w, "</div>")
		}
		io.write_string(w, "</div>")
	} else {
		io.write_string(w, "<p>No products available. Check back soon!</p>")
	}
	io.write_string(w, "</div> <footer class=\"footer\"> <p>©")
	buf_1: [32]u8
	io.write_string(w, write_int(buf_1[:], i64(data.year)))
	io.write_string(w, "ShopOdin. All rights reserved.</p> </footer> </body> </html>")
}
