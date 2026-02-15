package tpls

import "core:io"

render_simple :: proc(w: io.Writer, data: ^Simple_Data) {
	io.write_string(w, "<!--\n@type_of(Count) int\n-->\nHello, ")
	io.write_string(w, _ohtml_html_escape(data.Name))
	io.write_string(w, "! You have ")
	_buf_0: [32]u8
	io.write_string(w, _ohtml_write_int(_buf_0[:], i64(data.Count)))
	io.write_string(w, " items.\n")
}
