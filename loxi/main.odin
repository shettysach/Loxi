package loxi

import "core:fmt"
import "core:os"

REPL :: #config(REPL, false)

main :: proc() {
	init_vm()
	defer free_vm()

	args := os.args

	when REPL {
		repl()
	} else do if len(args) == 2 {
		path := args[1]
		run_file(path)
	} else {
		fmt.println("Usage: ./loxi.bin <file>")
		os.exit(64)
	}
}

repl :: proc() {
	buffer: [1024]u8
	input := make([dynamic]u8)

	braces := 0
	in_str := false

	for {
		if braces == 0 do fmt.print("> ")
		else do fmt.print("• ")

		n, err := os.read(os.stdin, buffer[:])
		if n <= 1 && braces == 0 || err != nil do break

		line := buffer[:n]
		append(&input, ..line)

		for c in line {
			if c == '"' do in_str = !in_str
			else if !in_str {
				if c == '{' do braces += 1
				else if c == '}' do braces -= 1
			}
		}

		if braces == 0 {
			source := input[:]
			switch interpret(&source) {
			case .CompileError:
				os.exit(65)
			case .RuntimeError:
				os.exit(70)
			case .Ok:
			}

			clear(&input)
			braces = 0
		}
	}
}

run_file :: proc(path: string) {
	source, ok := os.read_entire_file(path)
	defer delete(source)

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
