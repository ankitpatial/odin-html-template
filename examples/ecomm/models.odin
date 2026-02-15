package ecomm

import ohtml "../.."

// ---------------------------------------------------------------------------
// Data types
// ---------------------------------------------------------------------------

Spec :: struct {
	label: string,
	value: string,
}

Product :: struct {
	id:          string,
	name:        string,
	price:       f64,
	description: string,
	in_stock:    bool,
	tags:        []string,
	sku:         string,
	category:    string,
	specs:       []Spec,
}

// Page data passed to templates — flat struct so field access works directly.
Shop_Page :: struct {
	title:      string,
	user_name:  string,
	cart_count: int,
	year:       int,
	products:   []Product,
	product:    Product,
	cart_total: f64,
}

Demo_Item :: struct {
	name:   string,
	value:  int,
	active: bool,
}

Capability_Page :: struct {
	title:          string,
	user_name:      string,
	cart_count:     int,
	year:           int,
	// demo data
	greeting:       string,
	count:          int,
	price:          f64,
	is_admin:       bool,
	role:           string,
	items:          []string,
	products:       []Product,
	demo_items:     []Demo_Item,
	empty_list:     []string,
	html_dangerous: string,
	url_dangerous:  string,
	js_dangerous:   string,
	safe_html:      ohtml.Safe_HTML,
	safe_url:       ohtml.Safe_URL,
	bio:            string,
}

Account_Page :: struct {
	title:        string,
	user_name:    string,
	cart_count:   int,
	year:         int,
	email:        string,
	member_since: string,
	order_count:  int,
}

Auth_Page :: struct {
	title:   string,
	year:    int,
	email:   string,
	error:   string,
	success: string,
}

// ---------------------------------------------------------------------------
// Sample data
// ---------------------------------------------------------------------------

PRODUCTS := []Product {
	{
		id = "1",
		name = "Wireless Headphones",
		price = 79.99,
		description = "Premium noise-cancelling headphones with 30hr battery life.",
		in_stock = true,
		tags = {"electronics", "audio", "bestseller"},
		sku = "WH-1000",
		category = "Audio",
		specs = {
			{label = "Driver Size", value = "40mm"},
			{label = "Battery", value = "30 hours"},
			{label = "Connectivity", value = "Bluetooth 5.2"},
			{label = "Weight", value = "250g"},
		},
	},
	{
		id = "2",
		name = "Mechanical Keyboard",
		price = 149.00,
		description = "Full-size mechanical keyboard with Cherry MX switches and RGB.",
		in_stock = true,
		tags = {"electronics", "peripherals"},
		sku = "KB-MX100",
		category = "Peripherals",
		specs = {
			{label = "Switch Type", value = "Cherry MX Brown"},
			{label = "Layout", value = "Full-size (104 keys)"},
			{label = "Backlight", value = "RGB per-key"},
			{label = "Interface", value = "USB-C"},
		},
	},
	{
		id = "3",
		name = "Standing Desk Mat",
		price = 34.50,
		description = "Anti-fatigue mat for standing desks. Ergonomic cushion design.",
		in_stock = false,
		tags = {"office", "ergonomics"},
		sku = "DM-ERG20",
		category = "Office",
		specs = {},
	},
}

TPL_DIR :: "examples/ecomm/tpls/"

// ---------------------------------------------------------------------------
// Template cache — parsed once at startup, executed per request
// ---------------------------------------------------------------------------

Template_Cache :: struct {
	templates: map[string]^ohtml.Template,
	sources:   map[string]string, // keep source text alive — AST nodes reference it
}
