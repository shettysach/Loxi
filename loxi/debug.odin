package loxi

import "core:fmt"
import "core:mem"

// DEBUG_PRINT_CODE :: true
// DEBUG_TRACE_EXECUTION :: true

DEBUG_PRINT_CODE :: false
DEBUG_TRACE_EXECUTION :: false

disassemble_chunk :: proc(c: ^Chunk, name: string) {
	fmt.printfln("== %s ==", name)
	for offset: uint = 0; offset < len(c.code); do offset = disassemble_instruction(c, offset)
	fmt.println()
}

disassemble_instruction :: proc(c: ^Chunk, offset: uint) -> uint {
	fmt.printf("% 4d ", offset)

	if offset > 0 && c.lines[offset] == c.lines[offset - 1] do fmt.printf("   | ")
	else do fmt.printf("% 4d ", c.lines[offset])

	instruction := OpCode(c.code[offset])

	switch instruction {

	case .Return:
		return simple_instruction("RETURN", offset)
	case .Call:
		return byte_instruction("CALL", c, offset)
	case .Jump:
		return jump_instruction("JUMP", true, c, offset)
	case .JumpIfFalse:
		return jump_instruction("JUMP_IF_FALSE", true, c, offset)
	case .Loop:
		return jump_instruction("LOOP", false, c, offset)
	case .Constant:
		return constant_instruction("CONSTANT", c, offset)
	case .DefineGlobal:
		return constant_instruction("DEFINE_GLOBAL", c, offset)
	case .GetGlobal:
		return constant_instruction("GET_GLOBAL", c, offset)
	case .SetGlobal:
		return constant_instruction("SET_GLOBAL", c, offset)
	case .GetLocal:
		return byte_instruction("GET_LOCAL", c, offset)
	case .SetLocal:
		return byte_instruction("SET_LOCAL", c, offset)
	case .Nil:
		return simple_instruction("NIL", offset)
	case .True:
		return simple_instruction("TRUE", offset)
	case .False:
		return simple_instruction("FALSE", offset)
	case .Equal:
		return simple_instruction("EQUAL", offset)
	case .Greater:
		return simple_instruction("GREATER", offset)
	case .Less:
		return simple_instruction("LESS", offset)
	case .Not:
		return simple_instruction("NOT", offset)
	case .Negate:
		return simple_instruction("NEGATE", offset)
	case .Add:
		return simple_instruction("ADD", offset)
	case .Subtract:
		return simple_instruction("SUBTRACT", offset)
	case .Multiply:
		return simple_instruction("MULTIPLY", offset)
	case .Divide:
		return simple_instruction("DIVIDE", offset)
	case .Print:
		return simple_instruction("PRINT", offset)
	case .Pop:
		return simple_instruction("POP", offset)
	case:
		fmt.printf("Unknown opcode %d\n", instruction)
		return offset + 1
	}
}

simple_instruction :: proc(name: string, offset: uint) -> uint {
	fmt.println(name)
	return offset + 1
}

byte_instruction :: proc(name: string, c: ^Chunk, offset: uint) -> uint {
	slot := c.code[offset + 1]
	fmt.printfln("%-16s % 4d", name, slot)
	return offset + 2
}

constant_instruction :: proc(name: string, c: ^Chunk, offset: uint) -> uint {
	constant := c.code[offset + 1]
	fmt.printf("%-16s % 4d '", name, constant)
	print_value(c.constants[constant])
	fmt.println("'")
	return offset + 2
}

jump_instruction :: proc(name: string, sign: bool, chunk: ^Chunk, offset: uint) -> uint {
	jump := u16(chunk.code[offset + 1]) << 8
	jump |= u16(chunk.code[offset + 2])
	dest := offset + 3 + uint(jump) if sign else offset + 3 - uint(jump)
	fmt.printfln("%-16s % 4d -> % d", name, offset, dest)
	return offset + 3
}

disassemble_stack :: proc() {
	fmt.print("          ")
	for slot := &vm.stack[0]; slot < vm.stack_top; slot = mem.ptr_offset(slot, 1) {
		fmt.print("[ ")
		print_value(slot^)
		fmt.print(" ]")
	}
	fmt.println()
}
