package tpls

ForgotPasswordData :: struct {
	year: int,
	title: string,
	error: string,
	success: string,
	email: string,
}

ShopLayoutData :: struct {
	title: string,
	cart_count: int,
	user_name: string,
	year: int,
}

HomeProductsItem :: struct {
	price: f64,
	description: string,
	id: string,
	in_stock: bool,
	name: string,
	tags: []string,
}

HomeData :: struct {
	year: int,
	title: string,
	cart_count: int,
	user_name: string,
	products: []HomeProductsItem,
}

ProductProductItemSpecsItem :: struct {
	value: string,
	label: string,
}

ProductProductItem :: struct {
	price: f64,
	sku: string,
	in_stock: bool,
	name: string,
	specs: []ProductProductItemSpecsItem,
	id: string,
	tags: []string,
	category: string,
	description: string,
}

ProductData :: struct {
	product: ProductProductItem,
	title: string,
	cart_count: int,
	user_name: string,
	year: int,
}

AuthLayoutData :: struct {
	title: string,
	error: string,
	success: string,
	year: int,
}

LoginData :: struct {
	year: int,
	title: string,
	error: string,
	success: string,
	email: string,
}

AccountData :: struct {
	cart_count: int,
	user_name: string,
	year: int,
	title: string,
	order_count: int,
	email: string,
	member_since: string,
}

CapabilityProductsItem :: struct {
	id: string,
	price: f64,
	in_stock: bool,
	category: string,
	tags: []string,
	name: string,
}

CapabilityDemoItemsItem :: struct {
	name: string,
	active: bool,
	value: string,
}

CapabilityData :: struct {
	html_dangerous: string,
	user_name: string,
	count: int,
	products: []CapabilityProductsItem,
	js_dangerous: string,
	cart_count: int,
	url_dangerous: string,
	role: string,
	safe_url: string,
	safe_html: string,
	is_admin: bool,
	demo_items: []CapabilityDemoItemsItem,
	items: []string,
	title: string,
	bio: string,
	year: int,
	greeting: string,
	price: f64,
	empty_list: []string,
}

CartProductsItem :: struct {
	name: string,
	id: string,
	description: string,
	price: f64,
}

CartData :: struct {
	products: []CartProductsItem,
	year: int,
	title: string,
	cart_count: int,
	user_name: string,
	cart_total: f64,
}

