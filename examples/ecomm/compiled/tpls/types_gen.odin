package tpls

Forgot_Password_Data :: struct {
	success: string,
	title: string,
	error: string,
	year: int,
	email: string,
}

Home_Products_Item :: struct {
	description: string,
	name: string,
	price: f64,
	in_stock: bool,
	id: string,
	tags: []string,
}

Home_Data :: struct {
	title: string,
	cart_count: int,
	user_name: string,
	products: []Home_Products_Item,
	year: int,
}

Product_Product_Item_Specs_Item :: struct {
	value: string,
	label: string,
}

Product_Product_Item :: struct {
	tags: []string,
	id: string,
	category: string,
	name: string,
	specs: []Product_Product_Item_Specs_Item,
	description: string,
	price: f64,
	sku: string,
	in_stock: bool,
}

Product_Data :: struct {
	product: Product_Product_Item,
	title: string,
	cart_count: int,
	user_name: string,
	year: int,
}

Login_Data :: struct {
	email: string,
	title: string,
	error: string,
	success: string,
	year: int,
}

Account_Data :: struct {
	title: string,
	cart_count: int,
	order_count: int,
	member_since: string,
	user_name: string,
	email: string,
	year: int,
}

Capability_Demo_Items_Item :: struct {
	value: string,
	active: bool,
	name: string,
}

Capability_Products_Item :: struct {
	id: string,
	price: f64,
	in_stock: bool,
	category: string,
	tags: []string,
	name: string,
}

Capability_Data :: struct {
	greeting: string,
	safe_html: string,
	price: f64,
	html_dangerous: string,
	user_name: string,
	is_admin: bool,
	demo_items: []Capability_Demo_Items_Item,
	js_dangerous: string,
	items: []string,
	title: string,
	role: string,
	bio: string,
	year: int,
	safe_url: string,
	empty_list: []string,
	count: int,
	products: []Capability_Products_Item,
	cart_count: int,
	url_dangerous: string,
}

Cart_Products_Item :: struct {
	description: string,
	name: string,
	price: f64,
	id: string,
}

Cart_Data :: struct {
	products: []Cart_Products_Item,
	title: string,
	user_name: string,
	year: int,
	cart_count: int,
	cart_total: f64,
}

