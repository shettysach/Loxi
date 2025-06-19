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
	globals:   map[string]Value,
	strings:   map[string]^ObjString,
	ip:        uint,
}


vm := VirtMach {
	globals = make(map[string]Value),
	strings = make(map[string]^ObjString),
}

free_vm :: proc() {
	if vm.chunk != nil {
		free_chunk(vm.chunk)
		vm.chunk = nil
	}
	delete(vm.globals)
	delete(vm.strings)
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

	if !compile(source, chunk) do return .CompileError

	vm.chunk = chunk
	vm.ip = 0
	return run()
}

run :: proc() -> InterpretResult {
	for {
		if DEBUG_TRACE_EXECUTION {
			disassemble_instruction(vm.chunk, vm.ip)
			disassemble_stack()
		}

		instruction := OpCode(read_byte())

		switch instruction {

		case .Return:
			return .Ok

		case .Jump:
			offset := read_short()
			vm.ip += uint(offset)

		case .JumpIfFalse:
			offset := read_short()
			if is_falsey(peek(0)) do vm.ip += uint(offset)

		case .Loop:
			offset := read_short()
			vm.ip -= uint(offset)

		case .Constant:
			constant := read_constant()
			push(constant)

		case .DefineGlobal:
			name := read_string()
			vm.globals[name] = peek(0)
			pop()

		case .GetGlobal:
			name := read_string()
			value, ok := vm.globals[name]
			if !ok {
				runtime_error("Undefined variable '%s'.", name)
				return .RuntimeError
			}
			push(value)

		case .SetGlobal:
			name := read_string()
			if !(name in vm.globals) {
				runtime_error("Undefined variable '%s'.", name)
				return .RuntimeError
			}
			vm.globals[name] = peek(0)

		case .GetLocal:
			slot := read_byte()
			push(vm.stack[slot])

		case .SetLocal:
			slot := read_byte()
			vm.stack[slot] = peek(0)

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

			pop()
			pop()
			push(a > b)

		case .Less:
			b, b_ok := peek(0).(f64)
			a, a_ok := peek(1).(f64)

			if !b_ok || !a_ok {
				runtime_error("Operand must be a number.")
				return .RuntimeError
			}

			pop()
			pop()
			push(a < b)

		case .Not:
			push(is_falsey(pop()))

		case .Negate:
			v, ok := peek(0).(f64)

			if !ok {
				runtime_error("Operand must be a number.")
				return .RuntimeError
			}

			pop()
			push(-v)

		case .Add:
			b, b_ok := peek(0).(f64)
			a, a_ok := peek(1).(f64)

			if a_ok && b_ok {
				pop()
				pop()
				push(a + b)
				break
			}

			b_obj, b_obj_ok := peek(0).(^Obj)
			a_obj, a_obj_ok := peek(1).(^Obj)

			if a_obj_ok && b_obj_ok && a_obj.type == .ObjString && b_obj.type == .ObjString {
				pop()
				pop()
				push(concatenate(a_obj, b_obj))
				break
			}

			runtime_error("Operands must be numbers or strings")
			return .RuntimeError

		case .Subtract:
			b, b_ok := peek(0).(f64)
			a, a_ok := peek(1).(f64)

			if !b_ok || !a_ok {
				runtime_error("Operands must be numbers.")
				return .RuntimeError
			}

			pop()
			pop()
			push(a - b)

		case .Multiply:
			b, b_ok := peek(0).(f64)
			a, a_ok := peek(1).(f64)

			if !b_ok || !a_ok {
				runtime_error("Operands must be numbers.")
				return .RuntimeError
			}

			pop()
			pop()
			push(a * b)

		case .Divide:
			b, b_ok := peek(0).(f64)
			a, a_ok := peek(1).(f64)

			if !b_ok || !a_ok {
				runtime_error("Operands must be numbers.")
				return .RuntimeError
			}

			pop()
			pop()
			push(a / b)

		case .Print:
			print_value(pop())
			fmt.println()

		case .Pop:
			pop()
		}
	}

	return .Ok
}


read_byte :: proc() -> u8 {
	byte := vm.chunk.code[vm.ip]
	vm.ip += 1
	return byte
}

read_short :: proc() -> u16 {
	ip := vm.ip
	vm.ip += 2
	code := vm.chunk.code
	return u16(code[ip]) << 8 | u16(code[ip + 1])
}

read_constant :: proc() -> Value {
	return vm.chunk.constants[read_byte()]
}

read_string :: proc() -> string {
	obj := read_constant().(^Obj)
	str := (^ObjString)(obj).str
	return str
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

	if a_obj && b_obj do return a == b
	else do return val_a == val_b
}

runtime_error :: proc(format: string, args: ..any) {
	fmt.eprintfln(format, args)

	instruction := vm.ip - 1 // NOTE: ?
	line := vm.chunk.lines[instruction]
	fmt.eprintf("[line %d] in script\n", line)

	vm.stack_top = 0
}
