package loxi

import "core:bytes"
import "core:fmt"
import "core:os"
import "core:strings"

main :: proc() {
	defer free_vm()
	args := os.args

	if len(args) == 1 {
		repl()
	} else if len(args) == 2 {
		path := args[1]
		run_file(path)
	} else {
		fmt.println("Usage: loxi <file>")
		os.exit(64)
	}

}

repl :: proc() {
	buffer: [1024]u8
	for {
		fmt.print("-> ")
		n, err := os.read(os.stdin, buffer[:])

		if err != nil || n == 1 {
			fmt.println()
			break
		}

		line := buffer[:n]

		if bytes.equal(line, {'q', 'u', 'i', 't', 10}) {return}

		switch interpret(&line) {
		case .CompileError:
			os.exit(65)
		case .RuntimeError:
			os.exit(70)
		case .Ok:
		}
	}
}

run_file :: proc(path: string) {
	source, ok := os.read_entire_file(path, context.allocator)
	defer delete(source, context.allocator)

	if !ok {
		fmt.println("Failed to read file at path:", path)
		os.exit(74)
	}

	switch interpret(&source) {
	case .CompileError:
		os.exit(65)
	case .RuntimeError:
		os.exit(70)
	case .Ok:
	}
}
