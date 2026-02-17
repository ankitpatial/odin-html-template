package compiled

import "core:fmt"
import "core:log"
import "core:net"
import "core:strings"
import "core:time"

import http "../deps/odin-http"
import "tpls"

main :: proc() {
	context.logger = log.create_console_logger()

	router: http.Router
	http.router_init(&router)
	defer http.router_destroy(&router)

	http.route_get(&router, "/", http.handler(handle_home))
	http.route_get(&router, "/products", http.handler(handle_products))
	http.route_get(&router, "/product", http.handler(handle_product))
	http.route_get(&router, "/cart", http.handler(handle_cart))
	http.route_get(&router, "/capability", http.handler(handle_capability))
	http.route_get(&router, "/account", http.handler(handle_account))
	http.route_get(&router, "/login", http.handler(handle_login))
	http.route_post(&router, "/login", http.handler(handle_login_post))
	http.route_all(&router, "(.*)", http.handler(handle_not_found))

	s: http.Server
	http.server_shutdown_on_interrupt(&s)

	fmt.println("ShopOdin (compiled) running at http://localhost:8081")
	fmt.println("Press Ctrl+C to stop.")

	err := http.listen_and_serve(
		&s,
		http.router_handler(&router),
		net.Endpoint{address = net.IP4_Any, port = 8081},
	)
	if err != nil {
		log.errorf("server error: %v", err)
	}
}

// ---------------------------------------------------------------------------
// Sample product data
// ---------------------------------------------------------------------------

PRODUCTS_HOME := []tpls.HomeProductsItem {
	{
		id = "1",
		name = "Wireless Headphones",
		price = 79.99,
		description = "Premium noise-cancelling headphones with 30hr battery life.",
		in_stock = true,
		tags = {"electronics", "audio", "bestseller"},
	},
	{
		id = "2",
		name = "Mechanical Keyboard",
		price = 149.00,
		description = "Full-size mechanical keyboard with Cherry MX switches and RGB.",
		in_stock = true,
		tags = {"electronics", "peripherals"},
	},
	{
		id = "3",
		name = "Standing Desk Mat",
		price = 34.50,
		description = "Anti-fatigue mat for standing desks. Ergonomic cushion design.",
		in_stock = false,
		tags = {"office", "ergonomics"},
	},
}

PRODUCTS_DETAIL := []Product_Full {
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

Product_Full :: tpls.ProductProductItem

// ---------------------------------------------------------------------------
// Handlers
// ---------------------------------------------------------------------------

handle_home :: proc(req: ^http.Request, res: ^http.Response) {
	data := tpls.HomeData {
		title      = "Home",
		user_name  = "Alice",
		cart_count = 2,
		year       = 2026,
		products   = PRODUCTS_HOME,
	}

	b := strings.builder_make()
	defer strings.builder_destroy(&b)
	w := strings.to_writer(&b)

	sw: time.Stopwatch
	time.stopwatch_start(&sw)
	tpls.render_home(w, &data)
	time.stopwatch_stop(&sw)
	log.infof("render home | %v", time.stopwatch_duration(sw))

	http.respond_html(res, strings.to_string(b))
}

handle_products :: proc(req: ^http.Request, res: ^http.Response) {
	data := tpls.HomeData {
		title      = "Products",
		user_name  = "Alice",
		cart_count = 2,
		year       = 2026,
		products   = PRODUCTS_HOME,
	}

	b := strings.builder_make()
	defer strings.builder_destroy(&b)
	w := strings.to_writer(&b)

	sw: time.Stopwatch
	time.stopwatch_start(&sw)
	tpls.render_home(w, &data)
	time.stopwatch_stop(&sw)
	log.infof("render products | %v", time.stopwatch_duration(sw))

	http.respond_html(res, strings.to_string(b))
}

handle_product :: proc(req: ^http.Request, res: ^http.Response) {
	id := http.query_get(req.url, "id") or_else "1"

	product: Product_Full
	found := false
	for p in PRODUCTS_DETAIL {
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

	data := tpls.ProductData {
		title      = product.name,
		user_name  = "Alice",
		cart_count = 2,
		year       = 2026,
		product    = product,
	}

	b := strings.builder_make()
	defer strings.builder_destroy(&b)
	w := strings.to_writer(&b)

	sw: time.Stopwatch
	time.stopwatch_start(&sw)
	tpls.render_product(w, &data)
	time.stopwatch_stop(&sw)
	log.infof("render product | %v", time.stopwatch_duration(sw))

	http.respond_html(res, strings.to_string(b))
}

handle_cart :: proc(req: ^http.Request, res: ^http.Response) {
	cart_items := []tpls.CartProductsItem {
		{
			id = "1",
			name = "Wireless Headphones",
			price = 79.99,
			description = "Premium noise-cancelling headphones with 30hr battery life.",
		},
		{
			id = "2",
			name = "Mechanical Keyboard",
			price = 149.00,
			description = "Full-size mechanical keyboard with Cherry MX switches and RGB.",
		},
	}

	total: f64
	for p in cart_items {
		total += p.price
	}

	data := tpls.CartData {
		title      = "Your Cart",
		user_name  = "Alice",
		cart_count = 2,
		year       = 2026,
		products   = cart_items,
		cart_total = total,
	}

	b := strings.builder_make()
	defer strings.builder_destroy(&b)
	w := strings.to_writer(&b)

	sw: time.Stopwatch
	time.stopwatch_start(&sw)
	tpls.render_cart(w, &data)
	time.stopwatch_stop(&sw)
	log.infof("render cart | %v", time.stopwatch_duration(sw))

	http.respond_html(res, strings.to_string(b))
}

handle_capability :: proc(req: ^http.Request, res: ^http.Response) {
	data := tpls.CapabilityData {
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
		products       = {
			{
				id = "1",
				name = "Wireless Headphones",
				price = 79.99,
				in_stock = true,
				category = "Audio",
				tags = {"electronics", "audio", "bestseller"},
			},
			{
				id = "2",
				name = "Mechanical Keyboard",
				price = 149.00,
				in_stock = true,
				category = "Peripherals",
				tags = {"electronics", "peripherals"},
			},
			{
				id = "3",
				name = "Standing Desk Mat",
				price = 34.50,
				in_stock = false,
				category = "Office",
				tags = {"office", "ergonomics"},
			},
		},
		demo_items     = {
			{name = "Alpha", value = "10", active = true},
			{name = "Beta", value = "20", active = false},
			{name = "Gamma", value = "30", active = true},
		},
		empty_list     = {},
		html_dangerous = `<script>alert("xss")</script>`,
		url_dangerous  = `javascript:alert(1)`,
		js_dangerous   = `"; document.cookie; "`,
		safe_html      = `<em>this is <strong>trusted</strong> HTML</em>`,
		safe_url       = `/products?sort=name&dir=asc`,
		bio            = `Alice "the coder" & friends <team>`,
	}

	b := strings.builder_make()
	defer strings.builder_destroy(&b)
	w := strings.to_writer(&b)

	sw: time.Stopwatch
	time.stopwatch_start(&sw)
	tpls.render_capability(w, &data)
	time.stopwatch_stop(&sw)
	log.infof("render capability | %v", time.stopwatch_duration(sw))

	http.respond_html(res, strings.to_string(b))
}

handle_account :: proc(req: ^http.Request, res: ^http.Response) {
	data := tpls.AccountData {
		title        = "My Account",
		user_name    = "Alice",
		cart_count   = 2,
		year         = 2026,
		email        = "alice@example.com",
		member_since = "January 2025",
		order_count  = 7,
	}

	b := strings.builder_make()
	defer strings.builder_destroy(&b)
	w := strings.to_writer(&b)

	sw: time.Stopwatch
	time.stopwatch_start(&sw)
	tpls.render_account(w, &data)
	time.stopwatch_stop(&sw)
	log.infof("render account | %v", time.stopwatch_duration(sw))

	http.respond_html(res, strings.to_string(b))
}

handle_login :: proc(req: ^http.Request, res: ^http.Response) {
	data := tpls.LoginData {
		title = "Sign In",
		year  = 2026,
	}

	b := strings.builder_make()
	defer strings.builder_destroy(&b)
	w := strings.to_writer(&b)

	sw: time.Stopwatch
	time.stopwatch_start(&sw)
	tpls.render_login(w, &data)
	time.stopwatch_stop(&sw)
	log.infof("render login | %v", time.stopwatch_duration(sw))

	http.respond_html(res, strings.to_string(b))
}

handle_login_post :: proc(req: ^http.Request, res: ^http.Response) {
	http.body(req, -1, res, proc(user_data: rawptr, body: http.Body, err: http.Body_Error) {
		res := cast(^http.Response)user_data

		if err != nil {
			http.respond_with_status(res, http.body_error_status(err))
			return
		}

		form, form_ok := http.body_url_encoded(body)
		email := form["email"] if form_ok else ""

		data := tpls.LoginData {
			title = "Sign In",
			year  = 2026,
			email = email,
			error = "Invalid email or password. Please try again.",
		}

		b := strings.builder_make()
		defer strings.builder_destroy(&b)
		w := strings.to_writer(&b)

		sw: time.Stopwatch
		time.stopwatch_start(&sw)
		tpls.render_login(w, &data)
		time.stopwatch_stop(&sw)
		log.infof("render login_post | %v", time.stopwatch_duration(sw))

		http.respond_html(res, strings.to_string(b))
	})
}

handle_not_found :: proc(req: ^http.Request, res: ^http.Response) {
	http.respond_html(res, "<h1>404 — Page Not Found</h1>", .Not_Found)
}
