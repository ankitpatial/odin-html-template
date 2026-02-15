package tpls

import "core:io"
import "core:fmt"

render_product :: proc(w: io.Writer, data: ^Product_Data) {
	io.write_string(w, "<!--\n@type_of(cart_count) int\n@type_of(year) int\n-->\n<html lang=\"en\">\n<head>\n  <meta charset=\"utf-8\">\n  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n  <title>")
	io.write_string(w, _ohtml_html_escape(data.title))
	io.write_string(w, " — ShopOdin</title>\n  <style>\n    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }\n    body { font-family: system-ui, sans-serif; color: #1a1a1a; background: #f5f5f5; }\n    a { color: #2563eb; text-decoration: none; }\n    a:hover { text-decoration: underline; }\n    .header { background: #fff; border-bottom: 1px solid #e5e5e5; padding: 1rem 2rem; display: flex; align-items: center; justify-content: space-between; }\n    .header h1 { font-size: 1.25rem; }\n    .header nav a { margin-left: 1.5rem; font-size: 0.9rem; }\n    .container { max-width: 1100px; margin: 0 auto; padding: 2rem; }\n    .footer { text-align: center; padding: 2rem; color: #666; font-size: 0.85rem; border-top: 1px solid #e5e5e5; margin-top: 3rem; }\n  </style>\n  ")
	// {template "extra_head"}
	io.write_string(w, "\n<style>\n  .product { background: #fff; border-radius: 8px; padding: 2rem; box-shadow: 0 1px 3px rgba(0,0,0,0.1); }\n  .product h2 { font-size: 1.75rem; margin-bottom: 0.5rem; }\n  .product .price { font-size: 1.5rem; font-weight: 700; color: #059669; margin-bottom: 1rem; }\n  .product .desc { margin-bottom: 1.5rem; line-height: 1.6; color: #444; }\n  .product .meta { display: flex; gap: 2rem; margin-bottom: 1.5rem; font-size: 0.9rem; color: #666; }\n  .stock { color: #059669; font-weight: 600; }\n  .out { color: #dc2626; font-weight: 600; }\n  .tags { margin-bottom: 1.5rem; }\n  .tag { display: inline-block; background: #e5e7eb; border-radius: 4px; padding: 2px 8px; font-size: 0.8rem; margin-right: 4px; }\n  .specs { margin-bottom: 1.5rem; }\n  .specs h3 { font-size: 1rem; margin-bottom: 0.5rem; }\n  .specs table { width: 100%; border-collapse: collapse; }\n  .specs td { padding: 0.4rem 0; border-bottom: 1px solid #eee; }\n  .specs td:first-child { font-weight: 600; width: 30%; color: #555; }\n  .btn { display: inline-block; background: #2563eb; color: #fff; padding: 0.75rem 2rem; border-radius: 6px; font-weight: 600; }\n  .btn:hover { background: #1d4ed8; text-decoration: none; }\n  .btn-disabled { background: #9ca3af; cursor: not-allowed; }\n  .breadcrumb { margin-bottom: 1.5rem; font-size: 0.85rem; color: #888; }\n  .breadcrumb a { color: #2563eb; }\n</style>\n")
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
	io.write_string(w, "\n<div class=\"breadcrumb\">\n  <a href=\"/\">Home</a> / <a href=\"/products\">Products</a> / ")
	io.write_string(w, data.product.name)
	io.write_string(w, "\n</div>\n\n")
	io.write_string(w, "\n<div class=\"product\">\n  <h2>")
	io.write_string(w, data.product.name)
	io.write_string(w, "</h2>\n  <p class=\"price\">")
	io.write_string(w, fmt.aprintf("$%.2f", data.product.price))
	io.write_string(w, "</p>\n  <p class=\"desc\">")
	io.write_string(w, data.product.description)
	io.write_string(w, "</p>\n\n  <div class=\"meta\">\n    <span>")
	if data.product.in_stock {
		io.write_string(w, "<span class=\"stock\">In Stock</span>")
	} else {
		io.write_string(w, "<span class=\"out\">Out of Stock</span>")
	}
	io.write_string(w, "</span>\n    <span>SKU: ")
	io.write_string(w, data.product.sku)
	io.write_string(w, "</span>\n    <span>Category: ")
	io.write_string(w, data.product.category)
	io.write_string(w, "</span>\n  </div>\n\n  ")
	if len(data.product.tags) > 0 {
		io.write_string(w, "\n  <div class=\"tags\">\n    ")
		for _tmp_0 in data.product.tags {
			io.write_string(w, "<span class=\"tag\">")
			io.write_string(w, _tmp_0)
			io.write_string(w, "</span>")
		}
		io.write_string(w, "\n  </div>\n  ")
	}
	io.write_string(w, "\n\n  ")
	if len(data.product.specs) > 0 {
		io.write_string(w, "\n  <div class=\"specs\">\n    <h3>Specifications</h3>\n    <table>\n      ")
		for _tmp_1 in data.product.specs {
			io.write_string(w, "\n      <tr><td>")
			io.write_string(w, _tmp_1.label)
			io.write_string(w, "</td><td>")
			io.write_string(w, _tmp_1.value)
			io.write_string(w, "</td></tr>\n      ")
		}
		io.write_string(w, "\n    </table>\n  </div>\n  ")
	}
	io.write_string(w, "\n\n  ")
	if data.product.in_stock {
		io.write_string(w, "\n  <a href=\"/cart/add?id=")
		io.write_string(w, data.product.id)
		io.write_string(w, "\" class=\"btn\">Add to Cart</a>\n  ")
	} else {
		io.write_string(w, "\n  <span class=\"btn btn-disabled\">Out of Stock</span>\n  ")
	}
	io.write_string(w, "\n</div>\n")
	io.write_string(w, "\n")
	io.write_string(w, "\n</div>\n\n<footer class=\"footer\">\n  <p>© ")
	_buf_1: [32]u8
	io.write_string(w, _ohtml_write_int(_buf_1[:], i64(data.year)))
	io.write_string(w, " ShopOdin. All rights reserved.</p>\n</footer>\n\n</body>\n</html>\n")
	io.write_string(w, "\n\n")
	io.write_string(w, "\n")
}
