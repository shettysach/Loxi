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

InterpretResult :: enum {
	Ok,
	CompileError,
	RuntimeError,
}

interpret :: proc(source: ^[]u8) -> InterpretResult {
	chunk := Chunk{}

	if !compile(source, &chunk) {
		return .CompileError
	}

	vm.chunk = &chunk
	vm.ip = 0

	return run()
}

run :: proc() -> InterpretResult {
	for {
		if DEBUG_TRACE_EXECUTION {
			_ = disassemble_instruction(vm.chunk, vm.ip)
			disassemble_stack()
		}

		instruction := OpCode(read_byte())

		switch instruction {

		case .Return:
			print_value(pop())
			fmt.println()
			return .Ok

		case .Constant:
			constant := read_constant()
			push(constant)

		case .Negate:
			push(-pop())

		case .Add:
			binary_op(add)

		case .Subtract:
			binary_op(sub)

		case .Multiply:
			binary_op(mul)

		case .Divide:
			binary_op(div)

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
