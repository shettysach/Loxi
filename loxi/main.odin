package loxi

import "core:fmt"
import "core:mem"

import "base:runtime"

foreign import "dom_interface"

foreign dom_interface {
	read_input :: proc "contextless" (buffer: [1024]u8) -> int ---
	write_output :: proc "contextless" (out: string) ---
}

global_wasm_alloc: runtime.WASM_Allocator

@(export)
setup :: proc() {
	runtime.wasm_allocator_init(&global_wasm_alloc, 64)
	context.allocator = runtime.wasm_allocator(&global_wasm_alloc)
}

@(export)
run_file :: proc() {
	init_vm()
	defer free_vm()

	buffer: [1024]u8
	n := read_input(buffer)

	source := buffer[:n]
	switch interpret(&source) {
	case .CompileError:
		write_output("Compile error\n")
	case .RuntimeError:
		write_output("Runtime error\n")
	case .Ok:
	}
}
