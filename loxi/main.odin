package loxi

import "core:mem"

import "base:runtime"

foreign import "dom_interface"

foreign dom_interface {
	read_in :: proc "contextless" (buffer: [4096]u8) -> int ---
	write_out :: proc "contextless" (out: string) ---
	write_err :: proc "contextless" (out: string) ---
}

@(export)
run_file :: proc() {
	context.allocator = runtime.default_wasm_allocator()

	init_vm()
	defer free_vm()

	buffer: [4096]u8
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

repl_buf: [dynamic]u8
repl_braces: int
repl_in_str: bool

@(export)
init_repl :: proc() {
	context.allocator = runtime.default_wasm_allocator()
	init_vm()
	repl_buf = make([dynamic]u8)
	repl_braces = 0
	repl_in_str = false
}

@(export)
repl_line :: proc() -> int {
	context.allocator = runtime.default_wasm_allocator()

	buffer: [4096]u8
	n := read_in(buffer)
	line := buffer[:n]

	append(&repl_buf, ..line)

	for c in line {
		if c == '"' do repl_in_str = !repl_in_str
		else if !repl_in_str {
			if c == '{' do repl_braces += 1
			else if c == '}' do repl_braces -= 1
		}
	}

	if repl_braces <= 0 {
		repl_braces = 0
		source := repl_buf[:]
		if interpret(&source) != .Ok do reset_stack()
		clear(&repl_buf)
		repl_in_str = false
		return 0
	}

	return repl_braces
}

@(export)
free_repl :: proc() {
	context.allocator = runtime.default_wasm_allocator()
	delete(repl_buf)
	free_vm()
}
