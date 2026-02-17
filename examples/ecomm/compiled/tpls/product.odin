package tpls

import "core:io"
import "core:fmt"

render_product :: proc(w: io.Writer, data: ^ProductData) {
	io.write_string(w, "<html lang=\"en\"> <head> <meta charset=\"utf-8\"> <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\"> <title>")
	io.write_string(w, html_escape(data.title))
	io.write_string(w, "— ShopOdin</title> <style> *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; } body { font-family: system-ui, sans-serif; color: #1a1a1a; background: #f5f5f5; } a { color: #2563eb; text-decoration: none; } a:hover { text-decoration: underline; } .header { background: #fff; border-bottom: 1px solid #e5e5e5; padding: 1rem 2rem; display: flex; align-items: center; justify-content: space-between; } .header h1 { font-size: 1.25rem; } .header nav a { margin-left: 1.5rem; font-size: 0.9rem; } .container { max-width: 1100px; margin: 0 auto; padding: 2rem; } .footer { text-align: center; padding: 2rem; color: #666; font-size: 0.85rem; border-top: 1px solid #e5e5e5; margin-top: 3rem; } </style>")
	// {template "extra_head"}
	io.write_string(w, "<style> .product { background: #fff; border-radius: 8px; padding: 2rem; box-shadow: 0 1px 3px rgba(0,0,0,0.1); } .product h2 { font-size: 1.75rem; margin-bottom: 0.5rem; } .product .price { font-size: 1.5rem; font-weight: 700; color: #059669; margin-bottom: 1rem; } .product .desc { margin-bottom: 1.5rem; line-height: 1.6; color: #444; } .product .meta { display: flex; gap: 2rem; margin-bottom: 1.5rem; font-size: 0.9rem; color: #666; } .stock { color: #059669; font-weight: 600; } .out { color: #dc2626; font-weight: 600; } .tags { margin-bottom: 1.5rem; } .tag { display: inline-block; background: #e5e7eb; border-radius: 4px; padding: 2px 8px; font-size: 0.8rem; margin-right: 4px; } .specs { margin-bottom: 1.5rem; } .specs h3 { font-size: 1rem; margin-bottom: 0.5rem; } .specs table { width: 100%; border-collapse: collapse; } .specs td { padding: 0.4rem 0; border-bottom: 1px solid #eee; } .specs td:first-child { font-weight: 600; width: 30%; color: #555; } .btn { display: inline-block; background: #2563eb; color: #fff; padding: 0.75rem 2rem; border-radius: 6px; font-weight: 600; } .btn:hover { background: #1d4ed8; text-decoration: none; } .btn-disabled { background: #9ca3af; cursor: not-allowed; } .breadcrumb { margin-bottom: 1.5rem; font-size: 0.85rem; color: #888; } .breadcrumb a { color: #2563eb; } </style>")
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
	io.write_string(w, "<div class=\"breadcrumb\"> <a href=\"/\">Home</a> / <a href=\"/products\">Products</a> /")
	io.write_string(w, data.product.name)
	io.write_string(w, "</div>")
	io.write_string(w, "<div class=\"product\"> <h2>")
	io.write_string(w, data.product.name)
	io.write_string(w, "</h2> <p class=\"price\">")
	io.write_string(w, fmt.aprintf("$%.2f", data.product.price))
	io.write_string(w, "</p> <p class=\"desc\">")
	io.write_string(w, data.product.description)
	io.write_string(w, "</p> <div class=\"meta\"> <span>")
	if data.product.in_stock {
		io.write_string(w, "<span class=\"stock\">In Stock</span>")
	} else {
		io.write_string(w, "<span class=\"out\">Out of Stock</span>")
	}
	io.write_string(w, "</span> <span>SKU:")
	io.write_string(w, data.product.sku)
	io.write_string(w, "</span> <span>Category:")
	io.write_string(w, data.product.category)
	io.write_string(w, "</span> </div>")
	if len(data.product.tags) > 0 {
		io.write_string(w, "<div class=\"tags\">")
		for tmp_0 in data.product.tags {
			io.write_string(w, "<span class=\"tag\">")
			io.write_string(w, tmp_0)
			io.write_string(w, "</span>")
		}
		io.write_string(w, "</div>")
	}
	if len(data.product.specs) > 0 {
		io.write_string(w, "<div class=\"specs\"> <h3>Specifications</h3> <table>")
		for tmp_1 in data.product.specs {
			io.write_string(w, "<tr><td>")
			io.write_string(w, tmp_1.label)
			io.write_string(w, "</td><td>")
			io.write_string(w, tmp_1.value)
			io.write_string(w, "</td></tr>")
		}
		io.write_string(w, "</table> </div>")
	}
	if data.product.in_stock {
		io.write_string(w, "<a href=\"/cart/add?id=")
		io.write_string(w, data.product.id)
		io.write_string(w, "\" class=\"btn\">Add to Cart</a>")
	} else {
		io.write_string(w, "<span class=\"btn btn-disabled\">Out of Stock</span>")
	}
	io.write_string(w, "</div>")
	io.write_string(w, "</div> <footer class=\"footer\"> <p>©")
	buf_1: [32]u8
	io.write_string(w, write_int(buf_1[:], i64(data.year)))
	io.write_string(w, "ShopOdin. All rights reserved.</p> </footer> </body> </html>")
}
