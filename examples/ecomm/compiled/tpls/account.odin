package tpls

import "core:io"

render_account :: proc(w: io.Writer, data: ^AccountData) {
	io.write_string(w, "<html lang=\"en\"> <head> <meta charset=\"utf-8\"> <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\"> <title>")
	io.write_string(w, html_escape(data.title))
	io.write_string(w, "— ShopOdin</title> <style> *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; } body { font-family: system-ui, sans-serif; color: #1a1a1a; background: #f5f5f5; } a { color: #2563eb; text-decoration: none; } a:hover { text-decoration: underline; } .header { background: #fff; border-bottom: 1px solid #e5e5e5; padding: 1rem 2rem; display: flex; align-items: center; justify-content: space-between; } .header h1 { font-size: 1.25rem; } .header nav a { margin-left: 1.5rem; font-size: 0.9rem; } .container { max-width: 1100px; margin: 0 auto; padding: 2rem; } .footer { text-align: center; padding: 2rem; color: #666; font-size: 0.85rem; border-top: 1px solid #e5e5e5; margin-top: 3rem; } </style>")
	// {template "extra_head"}
	io.write_string(w, "<style> .account { max-width: 600px; } .account h2 { font-size: 1.5rem; margin-bottom: 1.5rem; } .info-card { background: #fff; border-radius: 8px; padding: 2rem; box-shadow: 0 1px 3px rgba(0,0,0,0.1); margin-bottom: 1.5rem; } .info-row { display: flex; justify-content: space-between; padding: 0.75rem 0; border-bottom: 1px solid #f0f0f0; } .info-row:last-child { border-bottom: none; } .info-label { font-weight: 600; color: #666; font-size: 0.9rem; } .info-value { color: #1a1a1a; } .actions { display: flex; gap: 1rem; margin-top: 1rem; } .btn { display: inline-block; background: #2563eb; color: #fff; padding: 0.6rem 1.25rem; border: none; border-radius: 6px; font-size: 0.9rem; font-weight: 600; cursor: pointer; text-align: center; } .btn:hover { background: #1d4ed8; text-decoration: none; } .btn-outline { background: transparent; color: #dc2626; border: 1px solid #dc2626; } .btn-outline:hover { background: #fef2f2; text-decoration: none; } </style>")
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
	io.write_string(w, "<div class=\"account\"> <h2>My Account</h2> <div class=\"info-card\"> <div class=\"info-row\"> <span class=\"info-label\">Name</span> <span class=\"info-value\">")
	io.write_string(w, data.user_name)
	io.write_string(w, "</span> </div> <div class=\"info-row\"> <span class=\"info-label\">Email</span> <span class=\"info-value\">")
	io.write_string(w, data.email)
	io.write_string(w, "</span> </div> <div class=\"info-row\"> <span class=\"info-label\">Member Since</span> <span class=\"info-value\">")
	io.write_string(w, data.member_since)
	io.write_string(w, "</span> </div> <div class=\"info-row\"> <span class=\"info-label\">Orders</span> <span class=\"info-value\">")
	buf_1: [32]u8
	io.write_string(w, write_int(buf_1[:], i64(data.order_count)))
	io.write_string(w, "</span> </div> </div> <div class=\"actions\"> <a href=\"/cart\" class=\"btn\">View Cart</a> <a href=\"/login\" class=\"btn btn-outline\">Sign Out</a> </div> </div>")
	io.write_string(w, "</div> <footer class=\"footer\"> <p>©")
	buf_2: [32]u8
	io.write_string(w, write_int(buf_2[:], i64(data.year)))
	io.write_string(w, "ShopOdin. All rights reserved.</p> </footer> </body> </html>")
}
