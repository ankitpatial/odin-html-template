package tpls

import "core:io"

render_loop :: proc(w: io.Writer, data: ^Loop_Data) {
	io.write_string(w, "<ul>")
	for _tmp_0 in data.Items {
		io.write_string(w, "<li>")
		io.write_string(w, _ohtml_html_escape(_tmp_0))
		io.write_string(w, "</li>")
	}
	io.write_string(w, "</ul>\n")
}
