package ecomm

import "core:fmt"
import "core:log"
import "core:os"
import "core:strings"
import "core:time"

import ohtml "../.."
import http "deps/odin-http"

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

cache: Template_Cache

// cache_load reads layout + page files, parses, escapes, and stores the result.
cache_load :: proc(name: string, layout_file: string, page_file: string) -> bool {
	layout_bytes, lok := os.read_entire_file_from_filename(layout_file)
	if !lok {
		log.errorf("could not read %s", layout_file)
		return false
	}
	defer delete(layout_bytes)

	page_bytes, pok := os.read_entire_file_from_filename(page_file)
	if !pok {
		log.errorf("could not read %s", page_file)
		return false
	}
	defer delete(page_bytes)

	combined := strings.concatenate({string(layout_bytes), string(page_bytes)})

	t := ohtml.template_new(name)

	_, parse_err := ohtml.template_parse(t, combined)
	if parse_err.kind != .None {
		log.errorf("parse %s: %s", name, parse_err.msg)
		if parse_err.msg != "" {delete(parse_err.msg)}
		ohtml.template_destroy(t)
		return false
	}

	esc_err := ohtml.escape_template(t)
	if esc_err.kind != .None {
		log.errorf("escape %s: %s", name, esc_err.msg)
		if esc_err.msg != "" {delete(esc_err.msg)}
		ohtml.template_destroy(t)
		return false
	}

	cache.templates[name] = t
	cache.sources[name] = combined
	return true
}

cache_init :: proc() -> bool {
	cache.templates = make(map[string]^ohtml.Template)
	cache.sources = make(map[string]string)

	ok := true
	ok = cache_load("home", TPL_DIR + "shop_layout.html", TPL_DIR + "home.html") && ok
	ok = cache_load("product", TPL_DIR + "shop_layout.html", TPL_DIR + "product.html") && ok
	ok = cache_load("cart", TPL_DIR + "shop_layout.html", TPL_DIR + "cart.html") && ok
	ok = cache_load("capability", TPL_DIR + "shop_layout.html", TPL_DIR + "capability.html") && ok
	ok = cache_load("login", TPL_DIR + "auth_layout.html", TPL_DIR + "login.html") && ok
	ok =
		cache_load(
			"forgot_password",
			TPL_DIR + "auth_layout.html",
			TPL_DIR + "forgot_password.html",
		) &&
		ok
	return ok
}

cache_destroy :: proc() {
	for _, t in cache.templates {
		ohtml.template_destroy(t)
	}
	delete(cache.templates)
	for _, src in cache.sources {
		delete(src)
	}
	delete(cache.sources)
}

// ---------------------------------------------------------------------------
// Template rendering — execute only (templates already parsed)
// ---------------------------------------------------------------------------

render_page :: proc(name: string, data: any) -> (string, bool) {
	t, found := cache.templates[name]
	if !found {
		log.errorf("template %q not found in cache", name)
		return "", false
	}

	start := time.now()
	result, exec_err := ohtml.execute_to_string(t, data)
	dur := time.since(start)

	if exec_err.kind != .None {
		log.errorf("exec %s: %s", name, exec_err.msg)
		if exec_err.msg != "" {delete(exec_err.msg)}
		return "", false
	}

	log.infof("render %s | exec=%v", name, dur)
	return result, true
}

// ---------------------------------------------------------------------------
// Handlers
// ---------------------------------------------------------------------------

handle_home :: proc(req: ^http.Request, res: ^http.Response) {
	data := Shop_Page {
		title      = "Home",
		user_name  = "Alice",
		cart_count = 2,
		year       = 2026,
		products   = PRODUCTS,
	}

	html, ok := render_page("home", data)
	if !ok {
		http.respond_with_status(res, .Internal_Server_Error)
		return
	}
	defer delete(html)
	http.respond_html(res, html)
}

handle_product :: proc(req: ^http.Request, res: ^http.Response) {
	id := http.query_get(req.url, "id") or_else "1"

	product: Product
	found := false
	for p in PRODUCTS {
		if p.id == id {
			product = p
			found = true
			break
		}
	}
	if !found {
		http.respond_html(res, "<h1>Product not found</h1>", .Not_Found)
		return
	}

	data := Shop_Page {
		title      = product.name,
		user_name  = "Alice",
		cart_count = 2,
		year       = 2026,
		product    = product,
	}

	html, ok := render_page("product", data)
	if !ok {
		http.respond_with_status(res, .Internal_Server_Error)
		return
	}
	defer delete(html)
	http.respond_html(res, html)
}

handle_login :: proc(req: ^http.Request, res: ^http.Response) {
	data := Auth_Page {
		title = "Sign In",
		year  = 2026,
	}

	html, ok := render_page("login", data)
	if !ok {
		http.respond_with_status(res, .Internal_Server_Error)
		return
	}
	defer delete(html)
	http.respond_html(res, html)
}

handle_login_post :: proc(req: ^http.Request, res: ^http.Response) {
	// Simulate login failure for demo purposes.
	http.body(req, -1, res, proc(user_data: rawptr, body: http.Body, err: http.Body_Error) {
		res := cast(^http.Response)user_data

		if err != nil {
			http.respond_with_status(res, http.body_error_status(err))
			return
		}

		form, form_ok := http.body_url_encoded(body)
		email := form["email"] if form_ok else ""

		data := Auth_Page {
			title = "Sign In",
			year  = 2026,
			email = email,
			error = "Invalid email or password. Please try again.",
		}

		html, ok := render_page("login", data)
		if !ok {
			http.respond_with_status(res, .Internal_Server_Error)
			return
		}
		defer delete(html)
		http.respond_html(res, html)
	})
}

handle_forgot :: proc(req: ^http.Request, res: ^http.Response) {
	data := Auth_Page {
		title = "Reset Password",
		year  = 2026,
	}

	html, ok := render_page("forgot_password", data)
	if !ok {
		http.respond_with_status(res, .Internal_Server_Error)
		return
	}
	defer delete(html)
	http.respond_html(res, html)
}

handle_forgot_post :: proc(req: ^http.Request, res: ^http.Response) {
	http.body(req, -1, res, proc(user_data: rawptr, body: http.Body, err: http.Body_Error) {
		res := cast(^http.Response)user_data

		if err != nil {
			http.respond_with_status(res, http.body_error_status(err))
			return
		}

		form, form_ok := http.body_url_encoded(body)
		email := form["email"] if form_ok else ""

		data := Auth_Page {
			title   = "Reset Password",
			year    = 2026,
			email   = email,
			success = "Reset link sent! Check your inbox.",
		}

		html, ok := render_page("forgot_password", data)
		if !ok {
			http.respond_with_status(res, .Internal_Server_Error)
			return
		}
		defer delete(html)
		http.respond_html(res, html)
	})
}

handle_cart :: proc(req: ^http.Request, res: ^http.Response) {
	cart_items := PRODUCTS[:2] // simulate 2 items in cart
	total: f64
	for p in cart_items {
		total += p.price
	}

	data := Shop_Page {
		title      = "Your Cart",
		user_name  = "Alice",
		cart_count = 2,
		year       = 2026,
		products   = cart_items,
		cart_total = total,
	}

	html, ok := render_page("cart", data)
	if !ok {
		http.respond_with_status(res, .Internal_Server_Error)
		return
	}
	defer delete(html)
	http.respond_html(res, html)
}

handle_products :: proc(req: ^http.Request, res: ^http.Response) {
	// Same as home — just shows all products.
	data := Shop_Page {
		title      = "Products",
		user_name  = "Alice",
		cart_count = 2,
		year       = 2026,
		products   = PRODUCTS,
	}

	html, ok := render_page("home", data)
	if !ok {
		http.respond_with_status(res, .Internal_Server_Error)
		return
	}
	defer delete(html)
	http.respond_html(res, html)
}

handle_capability :: proc(req: ^http.Request, res: ^http.Response) {
	data := Capability_Page {
		title          = "Template Capabilities",
		user_name      = "Alice",
		cart_count     = 2,
		year           = 2026,
		greeting       = "Hello from ohtml!",
		count          = 42,
		price          = 19.99,
		is_admin       = true,
		role           = "editor",
		items          = {"Odin", "Go", "Rust", "Zig", "C"},
		products       = PRODUCTS,
		demo_items     = {
			{name = "Alpha", value = 10, active = true},
			{name = "Beta", value = 20, active = false},
			{name = "Gamma", value = 30, active = true},
		},
		empty_list     = {},
		html_dangerous = `<script>alert("xss")</script>`,
		url_dangerous  = `javascript:alert(1)`,
		js_dangerous   = `"; document.cookie; "`,
		safe_html      = ohtml.Safe_HTML(`<em>this is <strong>trusted</strong> HTML</em>`),
		safe_url       = ohtml.Safe_URL(`/products?sort=name&dir=asc`),
		bio            = `Alice "the coder" & friends <team>`,
	}

	html, ok := render_page("capability", data)
	if !ok {
		http.respond_with_status(res, .Internal_Server_Error)
		return
	}
	defer delete(html)
	http.respond_html(res, html)
}

handle_not_found :: proc(req: ^http.Request, res: ^http.Response) {
	http.respond_html(res, "<h1>404 — Page Not Found</h1>", .Not_Found)
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

main :: proc() {
	context.logger = log.create_console_logger()

	// Parse all templates once at startup.
	if !cache_init() {
		log.error("failed to load templates")
		return
	}
	defer cache_destroy()

	router: http.Router
	http.router_init(&router)
	defer http.router_destroy(&router)

	// Shop pages
	http.route_get(&router, "/", http.handler(handle_home))
	http.route_get(&router, "/products", http.handler(handle_products))
	http.route_get(&router, "/product", http.handler(handle_product))
	http.route_get(&router, "/cart", http.handler(handle_cart))
	http.route_get(&router, "/capability", http.handler(handle_capability))

	// Auth pages
	http.route_get(&router, "/login", http.handler(handle_login))
	http.route_post(&router, "/login", http.handler(handle_login_post))
	http.route_get(&router, "/forgot%-password", http.handler(handle_forgot))
	http.route_post(&router, "/forgot%-password", http.handler(handle_forgot_post))

	// Catch-all
	http.route_all(&router, "(.*)", http.handler(handle_not_found))

	s: http.Server
	http.server_shutdown_on_interrupt(&s)

	fmt.println("ShopOdin running at http://localhost:8080")
	fmt.println("  /              — Home (product listing)")
	fmt.println("  /product?id=1  — Product detail")
	fmt.println("  /login         — Login page")
	fmt.println("  /forgot-password — Forgot password")
	fmt.println()
	fmt.println("Press Ctrl+C to stop.")

	err := http.listen_and_serve(&s, http.router_handler(&router))
	if err != nil {
		log.errorf("server error: %v", err)
	}
}
