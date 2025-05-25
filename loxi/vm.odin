package loxi

import "core:fmt"

STACK_MAX :: 256

VirtMach :: struct {
	chunk:     ^Chunk,
	stack:     [STACK_MAX]Value,
	stack_top: u8,
	ip:        uint,
}

vm := VirtMach{}

free_vm :: proc() {
	free_chunk(vm.chunk)
}

InterpretResult :: enum u8 {
	Ok,
	CompileError,
	RuntimeError,
}

interpret :: proc(c: ^Chunk) -> InterpretResult {
	vm.chunk = c
	vm.ip = 0
	return run()
}

run :: proc() -> InterpretResult {
	for {
		if DEBUG_TRACE_EXECUTION {
			fmt.println()
			for slot: u8 = 0; slot < vm.stack_top; slot += 1 {
				fmt.print("[ ")
				print_value(vm.stack[slot])
				fmt.println(" ]")
			}
			fmt.println()

			disassemble_instruction(vm.chunk, vm.ip)
		}

		instruction := OpCode(read_byte())

		switch instruction {

		case .Return:
			fmt.println()
			print_value(pop())
			fmt.println()
			return .Ok

		case .Constant:
			constant := read_constant()
			push(constant)
			break

		case .Negate:
			push(-pop())
			break

		case .Add:
			binary_op(add)
			break

		case .Subtract:
			binary_op(sub)
			break

		case .Multiply:
			binary_op(mul)
			break

		case .Divide:
			binary_op(div)
			break


		case:
		}
	}

	return .Ok
}


read_byte :: proc() -> u8 {
	byte := vm.chunk.code[vm.ip]
	vm.ip += 1
	return byte
}

read_constant :: proc() -> Value {
	return vm.chunk.constants[read_byte()]
}

push :: proc(v: Value) {
	vm.stack[vm.stack_top] = v
	vm.stack_top += 1
}

pop :: proc() -> Value {
	vm.stack_top -= 1
	return vm.stack[vm.stack_top]
}

binary_op :: proc(op: proc(a, b: f64) -> f64) {
	b := pop()
	a := pop()
	push(op(a, b))
}

add :: proc(a, b: f64) -> f64 {return a + b}
sub :: proc(a, b: f64) -> f64 {return a - b}
mul :: proc(a, b: f64) -> f64 {return a * b}
div :: proc(a, b: f64) -> f64 {return a / b}
