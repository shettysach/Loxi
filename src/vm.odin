package loxi

import "core:fmt"
import "core:os"
import "core:strings"

STACK_MAX :: 256

VirtMach :: struct {
	chunk:     ^Chunk,
	stack:     [STACK_MAX]Value,
	stack_top: u8,
	objects:   ^Obj,
	ip:        uint,
}

vm := VirtMach{}

free_vm :: proc() {
	if vm.chunk != nil {
		free_chunk(vm.chunk)
		vm.chunk = nil
	}

	free_objects()
}

free_objects :: proc() {
	obj := vm.objects

	for obj != nil {
		next := obj.next
		free_object(obj)
		obj = next
	}
}

InterpretResult :: enum {
	Ok,
	CompileError,
	RuntimeError,
}

interpret :: proc(source: ^[]u8) -> InterpretResult {
	chunk := new(Chunk)

	if !compile(source, chunk) {
		return .CompileError
	}

	vm.chunk = chunk
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
			push(Nil{})

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
			#partial switch b in peek(0) {
			case f64:
				#partial switch a in peek(1) {
				case f64:
					_ = pop()
					_ = pop()
					push(a + b)
				case:
					runtime_error("Operands must be numbers or strings")
				}
			case ^Obj:
				#partial switch a in peek(1) {
				case ^Obj:
					_ = pop()
					_ = pop()
					push(concatenate(a, b))
				case:
					runtime_error("Operands must be numbers or strings")
				}
			case:
				runtime_error("Operands must be numbers or strings")
			}

		case .Subtract:
			b, b_ok := peek(0).(f64)
			a, a_ok := peek(1).(f64)

			if !b_ok || !a_ok {
				runtime_error("Operands must be numbers.")
				return .RuntimeError
			}

			_ = pop()
			_ = pop()
			push(a - b)

		case .Multiply:
			b, b_ok := peek(0).(f64)
			a, a_ok := peek(1).(f64)

			if !b_ok || !a_ok {
				runtime_error("Operands must be numbers.")
				return .RuntimeError
			}

			_ = pop()
			_ = pop()
			push(a * b)

		case .Divide:
			b, b_ok := peek(0).(f64)
			a, a_ok := peek(1).(f64)

			if !b_ok || !a_ok {
				runtime_error("Operands must be numbers.")
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
	return value == Nil{} || ok && !v
}

concatenate :: proc(a, b: ^Obj) -> Value {
	a_str := (^ObjString)(a).str
	b_str := (^ObjString)(b).str

	c_str := strings.concatenate({a_str, b_str})
	c_obj := cast(^Obj)take_string(c_str)

	return c_obj
}

values_equal :: proc(val_a, val_b: Value) -> bool {
	a, a_obj := val_a.(^Obj)
	b, b_obj := val_b.(^Obj)

	if a_obj && b_obj {
		return (^ObjString)(a).str == (^ObjString)(b).str
	} else {
		return val_a == val_b
	}

}

runtime_error :: proc(format: string, args: ..any) {
	fmt.eprintfln(format, args)

	instruction := vm.ip - 1 // NOTE: ?
	line := vm.chunk.lines[instruction]
	fmt.eprintf("[line %d] in script\n", line)

	vm.stack_top = 0
}
