package tpls

Nested_Data :: struct {
	Tags: []string,
	Name: string,
	Email: string,
	Show: bool,
	IsAdmin: bool,
}

Escape_Data :: struct {
	Title: string,
	JSVal: string,
	CSSVal: string,
	URL: string,
}

Complex_Sections_Item_Items_Item :: struct {
	Active: bool,
	Desc: string,
	Name: string,
}

Complex_Sections_Item :: struct {
	Heading: string,
	Items: []Complex_Sections_Item_Items_Item,
}

Complex_Data :: struct {
	Sections: []Complex_Sections_Item,
	Title: string,
	Footer: string,
}

Simple_Data :: struct {
	Count: int,
	Name: string,
}

Loop_Data :: struct {
	Items: []string,
}

