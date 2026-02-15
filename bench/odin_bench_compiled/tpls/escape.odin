package tpls

import "core:io"

render_escape :: proc(w: io.Writer, data: ^Escape_Data) {
	io.write_string(w, "<a href=\"")
	io.write_string(w, _ohtml_html_escape(_ohtml_url_query_escape(_ohtml_url_filter(data.URL))))
	io.write_string(w, "\">")
	io.write_string(w, _ohtml_html_escape(data.Title))
	io.write_string(w, "</a><script>var x = \"")
	io.write_string(w, _ohtml_js_escape(data.JSVal))
	io.write_string(w, "\";</script><style>.c{color:")
	io.write_string(w, _ohtml_css_escape(data.CSSVal))
	io.write_string(w, "}</style>\n")
}
