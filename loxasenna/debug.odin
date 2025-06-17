package loxi

import "core:fmt"

DEBUG_PRINT_CODE :: false
DEBUG_TRACE_EXECUTION :: false

disassemble_chunk :: proc(c: ^Chunk, name: string) {
	fmt.printfln("== %s ==\n", name)
	for offset: uint = 0; offset < len(c.code); do offset = disassemble_instruction(c, offset)
	fmt.println()
}

disassemble_instruction :: proc(c: ^Chunk, offset: uint) -> uint {
	fmt.printf("%4d ", offset)
	if offset > 0 && c.lines[offset] == c.lines[offset - 1] {
		fmt.printf("   | ")
	} else {
		fmt.printf("%4d ", c.lines[offset])
	}

	instruction := OpCode(c.code[offset])

	switch instruction {

	case .Return:
		return simple_instruction("OP_RETURN", offset)
	case .Constant:
		return constant_instruction("OP_CONSTANT", c, offset)
	case .DefineGlobal:
		return constant_instruction("OP_DEFINE_GLOBAL", c, offset)
	case .GetGlobal:
		return constant_instruction("OP_GET_GLOBAL", c, offset)
	case .SetGlobal:
		return constant_instruction("OP_SET_GLOBAL", c, offset)
	case .Nil:
		return simple_instruction("OP_NIL", offset)
	case .True:
		return simple_instruction("OP_TRUE", offset)
	case .False:
		return simple_instruction("OP_FALSE", offset)
	case .Equal:
		return simple_instruction("OP_EQUAL", offset)
	case .Greater:
		return simple_instruction("OP_GREATER", offset)
	case .Less:
		return simple_instruction("OP_LESS", offset)
	case .Not:
		return simple_instruction("OP_NOT", offset)
	case .Negate:
		return simple_instruction("OP_NEGATE", offset)
	case .Add:
		return simple_instruction("OP_ADD", offset)
	case .Subtract:
		return simple_instruction("OP_SUBTRACT", offset)
	case .Multiply:
		return simple_instruction("OP_MULTIPLY", offset)
	case .Divide:
		return simple_instruction("OP_DIVIDE", offset)
	case .Print:
		return simple_instruction("OP_PRINT", offset)
	case .Pop:
		return simple_instruction("OP_POP", offset)
	case:
		fmt.printf("Unknown opcode %d\n", instruction)
		return offset + 1

	}
}

simple_instruction :: proc(name: string, offset: uint) -> uint {
	fmt.println(name)
	return offset + 1
}

constant_instruction :: proc(name: string, c: ^Chunk, offset: uint) -> uint {
	constant := c.code[offset + 1]
	fmt.printf("%-16s %4d '", name, constant)
	print_value(c.constants[constant])
	fmt.println("'")
	return offset + 2
}

disassemble_stack :: proc() {
	fmt.println("< bot >")
	for slot: u8 = 0; slot < vm.stack_top; slot += 1 {
		fmt.print("[ ")
		print_value(vm.stack[slot])
		fmt.println(" ]")
	}
	fmt.println("< top >\n")
}
