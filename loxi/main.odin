package loxi

import "core:mem"

foreign import "dom_interface"

foreign dom_interface {
	read_input :: proc "contextless" (buffer: [4096]u8) -> int ---
	write_output :: proc "contextless" (out: string) ---
}

main :: proc() {
	init_vm()
	defer free_vm()
	run_file()
}

@(export)
run_file :: proc() {
	buffer: [4096]u8
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
