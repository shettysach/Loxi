package loxi

import "core:fmt"
import "core:mem"

DEBUG_PRINT_CODE :: #config(PRINT_CODE, false)
DEBUG_TRACE_EXECUTION :: #config(TRACE_EXECUTION, false)
DEBUG_LOG_GC :: #config(LOG_GC, false)

disassemble_chunk :: proc(c: ^Chunk, name: string) {
	fmt.printfln("== %s ==", name)
	for offset: uint = 0; offset < len(c.code); do offset = disassemble_instruction(c, offset)
	fmt.println()
}

disassemble_instruction :: proc(chunk: ^Chunk, offset: uint) -> uint {
	offset := offset
	fmt.printf("% 4d ", offset)

	if offset > 0 && chunk.lines[offset] == chunk.lines[offset - 1] do fmt.printf("   | ")
	else do fmt.printf("% 4d ", chunk.lines[offset])

	instruction := OpCode(chunk.code[offset])

	switch instruction {

	case .Return:
		return simple_instruction("RETURN", offset)
	case .Call:
		return byte_instruction("CALL", chunk, offset)
	case .Invoke:
		return invoke_instruction("INVOKE", chunk, offset)
	case .SuperInvoke:
		return invoke_instruction("SUPER_INVOKE", chunk, offset)
	case .Jump:
		return jump_instruction("JUMP", true, chunk, offset)
	case .JumpIfFalse:
		return jump_instruction("JUMP_IF_FALSE", true, chunk, offset)
	case .Loop:
		return jump_instruction("LOOP", false, chunk, offset)
	case .Constant:
		return constant_instruction("CONSTANT", chunk, offset)
	case .DefineGlobal:
		return constant_instruction("DEFINE_GLOBAL", chunk, offset)
	case .GetGlobal:
		return constant_instruction("GET_GLOBAL", chunk, offset)
	case .SetGlobal:
		return constant_instruction("SET_GLOBAL", chunk, offset)
	case .GetLocal:
		return byte_instruction("GET_LOCAL", chunk, offset)
	case .SetLocal:
		return byte_instruction("SET_LOCAL", chunk, offset)
	case .GetUpvalue:
		return byte_instruction("GET_UPVAL", chunk, offset)
	case .SetUpvalue:
		return byte_instruction("SET_UPVAL", chunk, offset)
	case .CloseUpvalue:
		return simple_instruction("CLOSE_UPVAL", offset)
	case .GetProperty:
		return constant_instruction("GET_PROPERTY", chunk, offset)
	case .SetProperty:
		return constant_instruction("SET_PROPERTY", chunk, offset)
	case .GetSuper:
		return constant_instruction("GET_SUPER", chunk, offset)
	case .Class:
		return constant_instruction("CLASS", chunk, offset)
	case .Inherit:
		return simple_instruction("INHERIT", offset)
	case .Method:
		return constant_instruction("METHOD", chunk, offset)
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
	case .Closure:
		offset += 1
		constant := chunk.code[offset];offset += 1
		fmt.printf("%-16s % 4d '", "CLOSURE", constant)
		print_value(chunk.constants[constant])
		fmt.println()

		function := cast(^ObjFunction)as_object(chunk.constants[constant])

		for j in 0 ..< function.upvalue_count {
			is_local := chunk.code[offset] != 0
			offset += 1
			index := chunk.code[offset]
			offset += 1
			fmt.printfln(
				"% 4d      |                     %s %d",
				offset - 2,
				is_local ? "local" : "upvalue",
				index,
			)
		}

		return offset
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

invoke_instruction :: proc(name: string, c: ^Chunk, offset: uint) -> uint {
	constant := c.code[offset + 1]
	arg_count := c.code[offset + 2]
	fmt.printf("%-16s (%d args) % 4d '", name, arg_count, constant)
	print_value(c.constants[constant])
	fmt.println("'")
	return offset + 3
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
