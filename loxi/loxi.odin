package loxi

import "core:fmt"
import "core:os"
import "core:strings"

main :: proc() {
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

	free_vm()
}

repl :: proc() {
	fmt.println("ᛚᛟᚲᛁ")
	buffer: [1024]u8
	for {
		fmt.print("-> ")
		n, err := os.read(os.stdin, buffer[:])
		if err != nil || n == 0 {
			fmt.println()
			break
		}

		line := buffer[:n]

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
