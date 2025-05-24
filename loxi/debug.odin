package loxi

import "core:fmt"

disassemble_chunk :: proc(c: ^Chunk, name: string) {
	fmt.printfln("== %s ==\n", name)
	for offset := 0; offset < len(c.code); do offset = disassemble_instruction(c, offset)
}

disassemble_instruction :: proc(c: ^Chunk, offset: int) -> int {
	fmt.printf("%4d ", offset)
	if offset > 0 && c.lines[offset] == c.lines[offset - 1] {
		fmt.printf("   | ")
	} else {
		fmt.printf("%4d ", c.lines[offset])
	}

	instruction := OpCode(c.code[offset])

	switch instruction {
	case OpCode.Return:
		return simple_instruction("OP_RETURN", offset)
	case OpCode.Constant:
		return constant_instruction("OP_CONSTANT", c, offset)
	case:
		fmt.printf("Unknown opcode %d\n", instruction)
		return offset + 1
	}
}

simple_instruction :: proc(name: string, offset: int) -> int {
	fmt.println(name)
	return offset + 1
}

constant_instruction :: proc(name: string, c: ^Chunk, offset: int) -> int {
	constant := c.code[offset + 1]
	fmt.printf("%-16s %4d '", name, constant)
	print_value(c.constants[constant])
	fmt.println("'")
	return offset + 2
}
