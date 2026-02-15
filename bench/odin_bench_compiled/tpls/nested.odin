package tpls

import "core:io"

render_nested :: proc(w: io.Writer, data: ^Nested_Data) {
	if data.Show {
		io.write_string(w, "<div class=\"user\">\n  <h1>")
		io.write_string(w, _ohtml_html_escape(data.Name))
		io.write_string(w, "</h1>\n  <p>Email: ")
		io.write_string(w, _ohtml_html_escape(data.Email))
		io.write_string(w, "</p>\n  ")
		if data.IsAdmin {
			io.write_string(w, "<span class=\"admin\">Admin</span>")
		}
		io.write_string(w, "\n  <ul>")
		for _tmp_0 in data.Tags {
			io.write_string(w, "<li>")
			io.write_string(w, _ohtml_html_escape(_tmp_0))
			io.write_string(w, "</li>")
		}
		io.write_string(w, "</ul>\n</div>")
	}
	io.write_string(w, "\n")
}
