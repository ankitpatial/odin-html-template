package tpls

import "core:io"
import "core:fmt"

render_cart :: proc(w: io.Writer, data: ^CartData) {
	io.write_string(w, "<html lang=\"en\"> <head> <meta charset=\"utf-8\"> <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\"> <title>")
	io.write_string(w, html_escape(data.title))
	io.write_string(w, "— ShopOdin</title> <style> *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; } body { font-family: system-ui, sans-serif; color: #1a1a1a; background: #f5f5f5; } a { color: #2563eb; text-decoration: none; } a:hover { text-decoration: underline; } .header { background: #fff; border-bottom: 1px solid #e5e5e5; padding: 1rem 2rem; display: flex; align-items: center; justify-content: space-between; } .header h1 { font-size: 1.25rem; } .header nav a { margin-left: 1.5rem; font-size: 0.9rem; } .container { max-width: 1100px; margin: 0 auto; padding: 2rem; } .footer { text-align: center; padding: 2rem; color: #666; font-size: 0.85rem; border-top: 1px solid #e5e5e5; margin-top: 3rem; } </style>")
	// {template "extra_head"}
	io.write_string(w, "<style> .cart-item { display: flex; justify-content: space-between; align-items: center; background: #fff; border-radius: 8px; padding: 1.25rem 1.5rem; margin-bottom: 1rem; box-shadow: 0 1px 3px rgba(0,0,0,0.1); } .cart-item h3 { margin: 0 0 0.25rem; } .cart-item .price { font-weight: 700; color: #059669; font-size: 1.1rem; } .cart-item .desc { color: #666; font-size: 0.9rem; } .cart-summary { background: #fff; border-radius: 8px; padding: 1.5rem; margin-top: 1.5rem; box-shadow: 0 1px 3px rgba(0,0,0,0.1); text-align: right; } .cart-summary .total { font-size: 1.5rem; font-weight: 700; color: #1a1a1a; } .btn { display: inline-block; background: #2563eb; color: #fff; padding: 0.75rem 2rem; border-radius: 6px; font-weight: 600; margin-top: 1rem; } .btn:hover { background: #1d4ed8; text-decoration: none; } .empty { text-align: center; padding: 3rem; color: #666; } .section-title { font-size: 1.5rem; margin-bottom: 1rem; } </style>")
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
	io.write_string(w, "<h2 class=\"section-title\">Your Cart</h2>")
	if len(data.products) > 0 {
		for tmp_0 in data.products {
			io.write_string(w, "<div class=\"cart-item\"> <div> <h3><a href=\"/product?id=")
			io.write_string(w, tmp_0.id)
			io.write_string(w, "\">")
			io.write_string(w, tmp_0.name)
			io.write_string(w, "</a></h3> <p class=\"desc\">")
			io.write_string(w, tmp_0.description)
			io.write_string(w, "</p> </div> <div class=\"price\">")
			io.write_string(w, fmt.aprintf("$%.2f", tmp_0.price))
			io.write_string(w, "</div> </div>")
		}
		io.write_string(w, "<div class=\"cart-summary\"> <p class=\"total\">Total:")
		io.write_string(w, fmt.aprintf("$%.2f", data.cart_total))
		io.write_string(w, "</p> <a href=\"/checkout\" class=\"btn\">Proceed to Checkout</a> </div>")
	} else {
		io.write_string(w, "<div class=\"empty\"> <p>Your cart is empty.</p> <p><a href=\"/products\">Browse products</a></p> </div>")
	}
	io.write_string(w, "</div> <footer class=\"footer\"> <p>©")
	buf_1: [32]u8
	io.write_string(w, write_int(buf_1[:], i64(data.year)))
	io.write_string(w, "ShopOdin. All rights reserved.</p> </footer> </body> </html>")
}
