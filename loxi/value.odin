package loxi

import "core:fmt"

Value :: f64

print_value :: proc(value: Value) {
	fmt.printf("%g", value)
}
