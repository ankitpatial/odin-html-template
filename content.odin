package ohtml

// Safe content types — distinct strings that carry type information
// about what kind of safe content they contain. These prevent
// double-escaping by letting the escaper know the content is already safe.

Safe_CSS :: distinct string
Safe_HTML :: distinct string
Safe_HTML_Attr :: distinct string
Safe_JS :: distinct string
Safe_JS_Str :: distinct string
Safe_URL :: distinct string
Safe_Srcset :: distinct string

// Content_Type classifies the type of safe content.
Content_Type :: enum {
	Plain,
	CSS,
	HTML,
	HTML_Attr,
	JS,
	JS_Str,
	URL,
	Srcset,
	Unsafe,
}

// content_type_of detects the Content_Type of a value.
content_type_of :: proc(val: any) -> Content_Type {
	if val == nil {
		return .Plain
	}

	switch val.id {
	case Safe_CSS:
		return .CSS
	case Safe_HTML:
		return .HTML
	case Safe_HTML_Attr:
		return .HTML_Attr
	case Safe_JS:
		return .JS
	case Safe_JS_Str:
		return .JS_Str
	case Safe_URL:
		return .URL
	case Safe_Srcset:
		return .Srcset
	}

	return .Plain
}

// stringify converts a value to a string and reports its content type.
stringify :: proc(val: any) -> (string, Content_Type) {
	ct := content_type_of(val)
	if ct != .Plain {
		// Safe types are distinct strings — cast to string.
		switch ct {
		case .CSS:
			return string((^Safe_CSS)(val.data)^), ct
		case .HTML:
			return string((^Safe_HTML)(val.data)^), ct
		case .HTML_Attr:
			return string((^Safe_HTML_Attr)(val.data)^), ct
		case .JS:
			return string((^Safe_JS)(val.data)^), ct
		case .JS_Str:
			return string((^Safe_JS_Str)(val.data)^), ct
		case .URL:
			return string((^Safe_URL)(val.data)^), ct
		case .Srcset:
			return string((^Safe_Srcset)(val.data)^), ct
		case .Plain, .Unsafe:
		// fall through
		}
	}
	return sprint_value(val), .Plain
}
