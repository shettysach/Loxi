package loxi

import "core:fmt"
import "core:os"

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

		case .Nil:
			push(nil)

		case .True:
			push(true)

		case .False:
			push(false)

		case .Equal:
			b := pop()
			a := pop()
			push(values_equal(a, b))

		case .Greater:
			b, b_ok := peek(0).(f64)
			a, a_ok := peek(1).(f64)

			if !b_ok || !a_ok {
				runtime_error("Operand must be a number.")
				return .RuntimeError
			}

			_ = pop()
			_ = pop()
			push(a > b)

		case .Less:
			b, b_ok := peek(0).(f64)
			a, a_ok := peek(1).(f64)

			if !b_ok || !a_ok {
				runtime_error("Operand must be a number.")
				return .RuntimeError
			}

			_ = pop()
			_ = pop()
			push(a < b)

		case .Not:
			push(is_falsey(pop()))

		case .Negate:
			v, ok := peek(0).(f64)

			if !ok {
				runtime_error("Operand must be a number.")
				return .RuntimeError
			}

			_ = pop()
			push(-v)

		case .Add:
			b, b_ok := peek(0).(f64)
			a, a_ok := peek(1).(f64)

			if !b_ok || !a_ok {
				runtime_error("Operand must be a number.")
				return .RuntimeError
			}

			_ = pop()
			_ = pop()
			push(a + b)

		case .Subtract:
			b, b_ok := peek(0).(f64)
			a, a_ok := peek(1).(f64)

			if !b_ok || !a_ok {
				runtime_error("Operand must be a number.")
				return .RuntimeError
			}

			_ = pop()
			_ = pop()
			push(a - b)

		case .Multiply:
			b, b_ok := peek(0).(f64)
			a, a_ok := peek(1).(f64)

			if !b_ok || !a_ok {
				runtime_error("Operand must be a number.")
				return .RuntimeError
			}

			_ = pop()
			_ = pop()
			push(a * b)

		case .Divide:
			b, b_ok := peek(0).(f64)
			a, a_ok := peek(1).(f64)

			if !b_ok || !a_ok {
				runtime_error("Operand must be a number.")
				return .RuntimeError
			}

			_ = pop()
			_ = pop()
			push(a / b)

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

peek :: proc(distance: u8) -> Value {
	return vm.stack[vm.stack_top - 1 - distance]
}

is_falsey :: proc(value: Value) -> bool {
	v, ok := value.(bool)
	return value == nil || ok && !v
}

values_equal :: proc(a, b: Value) -> bool {
	return a == b
}

runtime_error :: proc(format: string, args: ..any) {
	fmt.eprintfln(format, args)

	instruction := vm.ip - 1 // NOTE: ?
	line := vm.chunk.lines[instruction]
	fmt.eprintf("[line %d] in script\n", line)

	vm.stack_top = 0
}
