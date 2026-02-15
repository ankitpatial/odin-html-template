package tpls

import "core:io"

render_complex :: proc(w: io.Writer, data: ^Complex_Data) {
	io.write_string(w, "<!DOCTYPE html>\n<html>\n<head><title>")
	io.write_string(w, _ohtml_html_escape(data.Title))
	io.write_string(w, "</title></head>\n<body>\n  <h1>")
	io.write_string(w, _ohtml_html_escape(data.Title))
	io.write_string(w, "</h1>\n  ")
	for _tmp_0 in data.Sections {
		io.write_string(w, "\n  <section>\n    <h2>")
		io.write_string(w, _ohtml_html_escape(_tmp_0.Heading))
		io.write_string(w, "</h2>\n    ")
		if len(_tmp_0.Items) > 0 {
			io.write_string(w, "\n    <ul>\n      ")
			for _tmp_1 in _tmp_0.Items {
				io.write_string(w, "\n      <li>")
				io.write_string(w, _ohtml_html_escape(_tmp_1.Name))
				io.write_string(w, " - ")
				io.write_string(w, _ohtml_html_escape(_tmp_1.Desc))
				if _tmp_1.Active {
					io.write_string(w, " (active)")
				}
				io.write_string(w, "</li>\n      ")
			}
			io.write_string(w, "\n    </ul>\n    ")
		} else {
			io.write_string(w, "\n    <p>No items.</p>\n    ")
		}
		io.write_string(w, "\n  </section>\n  ")
	}
	io.write_string(w, "\n  <footer>")
	io.write_string(w, _ohtml_html_escape(data.Footer))
	io.write_string(w, "</footer>\n</body>\n</html>\n")
}
