package tpls

import "core:io"

render_forgot_password :: proc(w: io.Writer, data: ^Forgot_Password_Data) {
	io.write_string(w, "<!--\n@type_of(year) int\n-->\n<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n  <meta charset=\"utf-8\">\n  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n  <title>")
	io.write_string(w, _ohtml_html_escape(data.title))
	io.write_string(w, " — ShopOdin</title>\n  <style>\n    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }\n    body { font-family: system-ui, sans-serif; color: #1a1a1a; background: #f0f4ff; display: flex; flex-direction: column; min-height: 100vh; }\n    a { color: #2563eb; text-decoration: none; }\n    a:hover { text-decoration: underline; }\n    .auth-header { text-align: center; padding: 2rem 1rem 0; }\n    .auth-header h1 { font-size: 1.5rem; }\n    .auth-header h1 a { color: #1a1a1a; }\n    .auth-wrap { flex: 1; display: flex; align-items: center; justify-content: center; padding: 2rem; }\n    .auth-box { background: #fff; border-radius: 12px; box-shadow: 0 4px 12px rgba(0,0,0,0.08); padding: 2.5rem; width: 100%; max-width: 420px; }\n    .auth-box h2 { font-size: 1.35rem; margin-bottom: 0.25rem; }\n    .auth-box .subtitle { color: #666; margin-bottom: 1.5rem; font-size: 0.9rem; }\n    .field { margin-bottom: 1.25rem; }\n    .field label { display: block; font-weight: 600; margin-bottom: 0.35rem; font-size: 0.9rem; }\n    .field input { width: 100%; padding: 0.6rem 0.75rem; border: 1px solid #d1d5db; border-radius: 6px; font-size: 0.95rem; }\n    .field input:focus { outline: none; border-color: #2563eb; box-shadow: 0 0 0 3px rgba(37,99,235,0.15); }\n    .btn { display: block; width: 100%; background: #2563eb; color: #fff; padding: 0.75rem; border: none; border-radius: 6px; font-size: 1rem; font-weight: 600; cursor: pointer; text-align: center; }\n    .btn:hover { background: #1d4ed8; text-decoration: none; }\n    .auth-links { margin-top: 1.25rem; text-align: center; font-size: 0.85rem; color: #666; }\n    ")
	if len(data.error) > 0 {
		io.write_string(w, ".error-msg { background: #fef2f2; color: #dc2626; border: 1px solid #fecaca; border-radius: 6px; padding: 0.75rem; margin-bottom: 1.25rem; font-size: 0.9rem; }")
	}
	io.write_string(w, "\n    ")
	if len(data.success) > 0 {
		io.write_string(w, ".success-msg { background: #f0fdf4; color: #16a34a; border: 1px solid #bbf7d0; border-radius: 6px; padding: 0.75rem; margin-bottom: 1.25rem; font-size: 0.9rem; }")
	}
	io.write_string(w, "\n    .auth-footer { text-align: center; padding: 1.5rem; color: #999; font-size: 0.8rem; }\n  </style>\n</head>\n<body>\n\n<div class=\"auth-header\">\n  <h1><a href=\"/\">ShopOdin</a></h1>\n</div>\n\n<div class=\"auth-wrap\">\n  <div class=\"auth-box\">\n    ")
	if len(data.error) > 0 {
		io.write_string(w, "<div class=\"error-msg\">")
		io.write_string(w, _ohtml_html_escape(data.error))
		io.write_string(w, "</div>")
	}
	io.write_string(w, "\n    ")
	if len(data.success) > 0 {
		io.write_string(w, "<div class=\"success-msg\">")
		io.write_string(w, _ohtml_html_escape(data.success))
		io.write_string(w, "</div>")
	}
	io.write_string(w, "\n    ")
	// {template "content"}
	io.write_string(w, "\n<h2>Reset Password</h2>\n<p class=\"subtitle\">Enter your email and we'll send you a reset link.</p>\n\n<form method=\"post\" action=\"/forgot-password\">\n  <div class=\"field\">\n    <label for=\"email\">Email</label>\n    <input type=\"email\" id=\"email\" name=\"email\" placeholder=\"you@example.com\" value=\"")
	io.write_string(w, data.email)
	io.write_string(w, "\" required>\n  </div>\n\n  <button type=\"submit\" class=\"btn\">Send Reset Link</button>\n</form>\n\n<div class=\"auth-links\">\n  Remember your password? <a href=\"/login\">Sign in</a>\n</div>\n")
	io.write_string(w, "\n  </div>\n</div>\n\n<div class=\"auth-footer\">\n  <p>© ")
	_buf_0: [32]u8
	io.write_string(w, _ohtml_write_int(_buf_0[:], i64(data.year)))
	io.write_string(w, " ShopOdin</p>\n</div>\n\n</body>\n</html>\n")
	io.write_string(w, "\n")
}
