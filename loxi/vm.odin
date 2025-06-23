package loxi

import "core:fmt"
import "core:mem"
import "core:os"
import "core:strings"

FRAMES_MAX :: 64
STACK_MAX :: FRAMES_MAX * 256

VirtMach :: struct {
	frames:      [FRAMES_MAX]CallFrame,
	frame_count: u8,
	stack:       [STACK_MAX]Value,
	stack_top:   ^Value,
	objects:     ^Obj,
	globals:     map[string]Value,
	strings:     map[string]^ObjString,
}

CallFrame :: struct {
	function: ^ObjFunction,
	ip:       uint,
	slots:    ^Value,
}

vm := VirtMach{}

init_vm :: proc() {
	reset_stack()
	vm.globals = make(map[string]Value)
	vm.strings = make(map[string]^ObjString)
}

reset_stack :: #force_inline proc() {
	vm.stack_top = &vm.stack[0]
	vm.frame_count = 0
}

free_vm :: proc() {
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
	function := compile(source)

	if function == nil do return .CompileError

	push(cast(^Obj)function)
	call(function, 0)

	return run()
}

run :: proc() -> InterpretResult {
	frame := &vm.frames[vm.frame_count - 1]

	for {
		if DEBUG_TRACE_EXECUTION {
			disassemble_stack()
			disassemble_instruction(&frame.function.chunk, frame.ip)
		}

		instruction := OpCode(read_byte(frame))

		switch instruction {

		case .Return:
			result := pop()
			vm.frame_count -= 1

			if vm.frame_count == 0 {
				pop()
				return .Ok
			}

			vm.stack_top = frame.slots
			push(result)
			frame = &vm.frames[vm.frame_count - 1]

		case .Call:
			arg_count := read_byte(frame)
			if !call_value(peek(arg_count), arg_count) do return .RuntimeError
			frame = &vm.frames[vm.frame_count - 1]

		case .Jump:
			offset := read_short(frame)
			frame.ip += uint(offset)

		case .JumpIfFalse:
			offset := read_short(frame)
			if is_falsey(peek(0)) do frame.ip += uint(offset)

		case .Loop:
			offset := read_short(frame)
			frame.ip -= uint(offset)

		case .Constant:
			constant := read_constant(frame)
			push(constant)

		case .DefineGlobal:
			name := read_string(frame)
			vm.globals[name] = peek(0)
			pop()

		case .SetGlobal:
			name := read_string(frame)
			if !(name in vm.globals) {
				runtime_error("Undefined variable '%s'.", name)
				return .RuntimeError
			}
			vm.globals[name] = peek(0)

		case .GetGlobal:
			name := read_string(frame)
			value, ok := vm.globals[name]
			if !ok {
				runtime_error("Undefined variable '%s'.", name)
				return .RuntimeError
			}
			push(value)

		case .SetLocal:
			slot := read_byte(frame)
			mem.ptr_offset(frame.slots, slot)^ = peek(0)

		case .GetLocal:
			slot := read_byte(frame)
			push(mem.ptr_offset(frame.slots, slot)^)

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


read_byte :: proc(frame: ^CallFrame) -> u8 {
	byte := frame.function.chunk.code[frame.ip]
	frame.ip += 1
	return byte
}

read_short :: proc(frame: ^CallFrame) -> u16 {
	ip := frame.ip
	frame.ip += 2
	code := frame.function.chunk.code
	return u16(code[ip]) << 8 | u16(code[ip + 1])
}

read_constant :: proc(frame: ^CallFrame) -> Value {
	return frame.function.chunk.constants[read_byte(frame)]
}

read_string :: proc(frame: ^CallFrame) -> string {
	obj := read_constant(frame).(^Obj)
	str := (^ObjString)(obj).str
	return str
}

push :: proc(v: Value) {
	vm.stack_top^ = v
	vm.stack_top = mem.ptr_offset(vm.stack_top, 1)
}

pop :: proc() -> Value {
	vm.stack_top = mem.ptr_offset(vm.stack_top, -1)
	return vm.stack_top^
}

@(private = "file")
peek :: proc(distance: u8) -> Value {
	return mem.ptr_offset(vm.stack_top, -i16(distance) - 1)^
}

call_value :: proc(callee: Value, arg_count: u8) -> bool {
	if obj, ok := callee.(^Obj); ok {
		#partial switch obj.type {
		case .ObjFunction:
			return call(cast(^ObjFunction)obj, arg_count)
		}
	}

	runtime_error("Can only call functions and classes.")
	return false
}

call :: proc(fun: ^ObjFunction, arg_count: u8) -> bool {
	if arg_count != fun.arity {
		runtime_error("Expected %d arguments but got %d.", fun.arity, arg_count)
		return false
	}

	if vm.frame_count == FRAMES_MAX {
		runtime_error("Stack overflow.")
		return false
	}

	frame := &vm.frames[vm.frame_count]
	vm.frame_count += 1
	frame.function = fun
	frame.ip = 0
	frame.slots = mem.ptr_offset(vm.stack_top, -i16(arg_count) - 1)
	return true
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
	a, a_ok := val_a.(^Obj)
	b, b_ok := val_b.(^Obj)

	if a_ok && b_ok do return a == b
	else do return val_a == val_b
}

runtime_error :: proc(format: string, args: ..any) {
	if len(args) == 0 do fmt.eprintfln(format)
	else do fmt.eprintfln(format, args)

	for i := vm.frame_count - 1;; i -= 1 {
		frame := &vm.frames[i]
		function := frame.function
		code := frame.function.chunk.code
		instruction := code[frame.ip - 1]

		fname := len(function.name) == 0 ? "script" : function.name
		fmt.eprintfln("[line %d] in %s", function.chunk.lines[instruction], fname)

		if i == 0 do break
	}

	reset_stack()
}
