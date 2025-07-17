package loxi

import "core:mem"

import "base:runtime"

foreign import "dom_interface"

foreign dom_interface {
	read_in :: proc "contextless" (buffer: [1024]u8) -> int ---
	write_out :: proc "contextless" (out: string) ---
	write_err :: proc "contextless" (out: string) ---
}

@(export)
run_file :: proc() {
	context.allocator = runtime.default_wasm_allocator()

	init_vm()
	defer free_vm()

	buffer: [1024]u8
	n := read_in(buffer)

	source := buffer[:n]
	switch interpret(&source) {
	case .CompileError:
		write_err("Compile error\n")
	case .RuntimeError:
		write_err("Runtime error\n")
	case .Ok:
	}
}
