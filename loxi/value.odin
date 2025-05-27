package loxi

import "core:fmt"

Value :: union {
	f64,
	bool,
}

print_value :: proc(value: Value) {
	fmt.print(value)
}
