package tpls

import "core:io"

render_account :: proc(w: io.Writer, data: ^Account_Data) {
	io.write_string(w, "<!--\n@type_of(cart_count) int\n@type_of(year) int\n-->\n<html lang=\"en\">\n<head>\n  <meta charset=\"utf-8\">\n  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n  <title>")
	io.write_string(w, _ohtml_html_escape(data.title))
	io.write_string(w, " — ShopOdin</title>\n  <style>\n    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }\n    body { font-family: system-ui, sans-serif; color: #1a1a1a; background: #f5f5f5; }\n    a { color: #2563eb; text-decoration: none; }\n    a:hover { text-decoration: underline; }\n    .header { background: #fff; border-bottom: 1px solid #e5e5e5; padding: 1rem 2rem; display: flex; align-items: center; justify-content: space-between; }\n    .header h1 { font-size: 1.25rem; }\n    .header nav a { margin-left: 1.5rem; font-size: 0.9rem; }\n    .container { max-width: 1100px; margin: 0 auto; padding: 2rem; }\n    .footer { text-align: center; padding: 2rem; color: #666; font-size: 0.85rem; border-top: 1px solid #e5e5e5; margin-top: 3rem; }\n  </style>\n  ")
	// {template "extra_head"}
	io.write_string(w, "\n<style>\n  .account { max-width: 600px; }\n  .account h2 { font-size: 1.5rem; margin-bottom: 1.5rem; }\n  .info-card { background: #fff; border-radius: 8px; padding: 2rem; box-shadow: 0 1px 3px rgba(0,0,0,0.1); margin-bottom: 1.5rem; }\n  .info-row { display: flex; justify-content: space-between; padding: 0.75rem 0; border-bottom: 1px solid #f0f0f0; }\n  .info-row:last-child { border-bottom: none; }\n  .info-label { font-weight: 600; color: #666; font-size: 0.9rem; }\n  .info-value { color: #1a1a1a; }\n  .actions { display: flex; gap: 1rem; margin-top: 1rem; }\n  .btn { display: inline-block; background: #2563eb; color: #fff; padding: 0.6rem 1.25rem; border: none; border-radius: 6px; font-size: 0.9rem; font-weight: 600; cursor: pointer; text-align: center; }\n  .btn:hover { background: #1d4ed8; text-decoration: none; }\n  .btn-outline { background: transparent; color: #dc2626; border: 1px solid #dc2626; }\n  .btn-outline:hover { background: #fef2f2; text-decoration: none; }\n</style>\n")
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
	io.write_string(w, "\n<div class=\"account\">\n  <h2>My Account</h2>\n\n  <div class=\"info-card\">\n    <div class=\"info-row\">\n      <span class=\"info-label\">Name</span>\n      <span class=\"info-value\">")
	io.write_string(w, data.user_name)
	io.write_string(w, "</span>\n    </div>\n    <div class=\"info-row\">\n      <span class=\"info-label\">Email</span>\n      <span class=\"info-value\">")
	io.write_string(w, data.email)
	io.write_string(w, "</span>\n    </div>\n    <div class=\"info-row\">\n      <span class=\"info-label\">Member Since</span>\n      <span class=\"info-value\">")
	io.write_string(w, data.member_since)
	io.write_string(w, "</span>\n    </div>\n    <div class=\"info-row\">\n      <span class=\"info-label\">Orders</span>\n      <span class=\"info-value\">")
	_buf_1: [32]u8
	io.write_string(w, _ohtml_write_int(_buf_1[:], i64(data.order_count)))
	io.write_string(w, "</span>\n    </div>\n  </div>\n\n  <div class=\"actions\">\n    <a href=\"/cart\" class=\"btn\">View Cart</a>\n    <a href=\"/login\" class=\"btn btn-outline\">Sign Out</a>\n  </div>\n</div>\n")
	io.write_string(w, "\n</div>\n\n<footer class=\"footer\">\n  <p>© ")
	_buf_2: [32]u8
	io.write_string(w, _ohtml_write_int(_buf_2[:], i64(data.year)))
	io.write_string(w, " ShopOdin. All rights reserved.</p>\n</footer>\n\n</body>\n</html>\n<!--\n@type_of(order_count) int\n-->\n")
	io.write_string(w, "\n\n")
	io.write_string(w, "\n")
}
