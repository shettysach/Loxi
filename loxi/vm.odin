package loxi

import "core:fmt"
import "core:mem"
import "core:slice"
import "core:strings"
import "core:time"

FRAMES_MAX :: 64
STACK_MAX :: FRAMES_MAX * 256

VirtMach :: struct {
	frames:          [FRAMES_MAX]CallFrame,
	frame_count:     u8,
	stack:           [STACK_MAX]Value,
	stack_top:       ^Value,
	open_upvalues:   ^ObjUpvalue,
	objects:         ^Obj,
	globals:         map[string]Value,
	strings:         map[string]^ObjString,
	gray_stack:      [dynamic]^Obj,
	gray_count:      uint,
	bytes_allocated: uint,
	next_gc:         uint,
}

CallFrame :: struct {
	closure: ^ObjClosure,
	ip:      uint,
	slots:   ^Value,
}

vm := VirtMach{}

clock_native :: proc(args: []Value) -> Value {
	return number_val(f64(time.now()._nsec))
}

init_vm :: proc() {
	vm.stack_top = &vm.stack[0]
	vm.globals = make(map[string]Value)
	vm.strings = make(map[string]^ObjString)
	vm.gray_stack = make([dynamic]^Obj)
	vm.next_gc = 1024 * 1024
	define_native("clock", clock_native)
}

reset_stack :: proc() {
	vm.stack_top = &vm.stack[0]
	vm.frame_count = 0
}

free_vm :: proc() {
	vm.stack_top = nil
	vm.open_upvalues = nil

	delete(vm.globals)
	delete(vm.strings)
	delete(vm.gray_stack)

	free_objects()
	vm.objects = nil

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

	push(object_val(cast(^Obj)function))
	closure := new_closure(function)
	pop()
	push(object_val(cast(^Obj)closure))
	call(closure, 0)

	return run()
}

run :: proc() -> InterpretResult {
	when DEBUG_PRINT_CODE do fmt.printfln(
		"NaN boxing: %v, Size of Value: %v\n",
		NAN_BOXING,
		size_of(Value),
	)

	frame := &vm.frames[vm.frame_count - 1]

	for {
		when DEBUG_TRACE_EXECUTION {
			disassemble_stack()
			disassemble_instruction(&frame.closure.function.chunk, frame.ip)
		}

		instruction := OpCode(read_byte(frame))

		switch instruction {

		case .Return:
			result := pop()
			close_upvalues(frame.slots)
			vm.frame_count -= 1

			if vm.frame_count == 0 {
				pop()
				return .Ok
			}

			vm.stack_top = frame.slots
			push(result)
			frame = &vm.frames[vm.frame_count - 1]

		case .Closure:
			object := as_object(read_constant(frame))
			function := cast(^ObjFunction)object
			closure := new_closure(function)
			push(object_val(cast(^Obj)closure))

			for i in 0 ..< closure.upvalue_count {
				is_local := read_byte(frame) != 0
				index := read_byte(frame)
				if is_local {
					value := mem.ptr_offset(frame.slots, index)
					closure.upvalues[i] = capture_upvalue(value)
				} else {
					closure.upvalues[i] = frame.closure.upvalues[index]
				}
			}

		case .Invoke:
			method := read_string(frame)
			arg_count := read_byte(frame)

			if !invoke(method, arg_count) do return .RuntimeError

			frame = &vm.frames[vm.frame_count - 1]

		case .SuperInvoke:
			method := read_string(frame)
			arg_count := read_byte(frame)
			superclass := cast(^ObjClass)as_object(pop())

			if !invoke_from_class(superclass, method, arg_count) do return .RuntimeError

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

		case .SetUpvalue:
			slot := read_byte(frame)
			frame.closure.upvalues[slot].location^ = peek(0)

		case .GetUpvalue:
			slot := read_byte(frame)
			push(frame.closure.upvalues[slot].location^)

		case .CloseUpvalue:
			close_upvalues(mem.ptr_offset(vm.stack_top, -1))
			pop()

		case .GetProperty:
			object, ok := try_object(peek(0))

			if !ok || object.type != .ObjInstance {
				runtime_error("Only instances have properties.")
				return .RuntimeError
			}

			instance := cast(^ObjInstance)object
			name := read_string(frame)

			if value, ok := instance.fields[name]; ok {
				pop()
				push(value)
				break
			}

			if !bind_method(instance.class, name) do return .RuntimeError

		case .SetProperty:
			object, ok := try_object(peek(1))

			if !ok || object.type != .ObjInstance {
				runtime_error("Only instances have fields.")
				return .RuntimeError
			}

			instance := cast(^ObjInstance)object
			instance.fields[read_string(frame)] = peek(0)
			value := pop()
			pop()
			push(value)

		case .GetSuper:
			name := read_string(frame)
			superclass := cast(^ObjClass)as_object(pop())

			if !bind_method(superclass, name) do return .RuntimeError

		case .Class:
			push(object_val(new_class(read_string(frame))))

		case .Inherit:
			superclass := cast(^ObjClass)as_object(peek(1))
			if superclass.type != .ObjClass {
				runtime_error("Superclass must be a class.")
				return .RuntimeError
			}
			subclass := cast(^ObjClass)as_object(peek(0))
			for name, method in superclass.methods {
				superclass.methods[name] = method
			}
			pop()

		case .Method:
			define_method(read_string(frame))

		case .Nil:
			push(NIL)

		case .False:
			push(FALSE)

		case .True:
			push(TRUE)

		case .Equal:
			b := pop()
			a := pop()
			push(values_equal(a, b))

		case .Greater:
			b, b_ok := try_number(peek(0))
			a, a_ok := try_number(peek(1))

			if !b_ok || !a_ok {
				runtime_error("Operand must be a number.")
				return .RuntimeError
			}

			pop()
			pop()
			push(bool_val(a > b))

		case .Less:
			b, b_ok := try_number(peek(0))
			a, a_ok := try_number(peek(1))

			if !b_ok || !a_ok {
				runtime_error("Operand must be a number.")
				return .RuntimeError
			}

			pop()
			pop()
			push(bool_val(a < b))

		case .Not:
			push(bool_val(is_falsey(pop())))

		case .Negate:
			v, ok := try_number(peek(0))

			if !ok {
				runtime_error("Operand must be a number.")
				return .RuntimeError
			}

			pop()
			push(number_val(-v))

		case .Add:
			b, b_ok := try_number(peek(0))
			a, a_ok := try_number(peek(1))

			if a_ok && b_ok {
				pop()
				pop()
				push(number_val(a + b))
				break
			}

			b_obj, b_obj_ok := try_object(peek(0))
			a_obj, a_obj_ok := try_object(peek(1))

			if a_obj_ok && b_obj_ok && a_obj.type == .ObjString && b_obj.type == .ObjString {
				pop()
				pop()
				push(concatenate(a_obj, b_obj))
				break
			}

			runtime_error("Operands must be numbers or strings")
			return .RuntimeError

		case .Subtract:
			b, b_ok := try_number(peek(0))
			a, a_ok := try_number(peek(1))

			if !b_ok || !a_ok {
				runtime_error("Operands must be numbers.")
				return .RuntimeError
			}

			pop()
			pop()
			push(number_val(a - b))

		case .Multiply:
			b, b_ok := try_number(peek(0))
			a, a_ok := try_number(peek(1))

			if !b_ok || !a_ok {
				runtime_error("Operands must be numbers.")
				return .RuntimeError
			}

			pop()
			pop()
			push(number_val(a * b))

		case .Divide:
			b, b_ok := try_number(peek(0))
			a, a_ok := try_number(peek(1))

			if !b_ok || !a_ok {
				runtime_error("Operands must be numbers.")
				return .RuntimeError
			}

			pop()
			pop()
			push(number_val(a / b))

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
	byte := frame.closure.function.chunk.code[frame.ip]
	frame.ip += 1
	return byte
}

read_short :: proc(frame: ^CallFrame) -> u16 {
	ip := frame.ip
	frame.ip += 2
	code := frame.closure.function.chunk.code
	return u16(code[ip]) << 8 | u16(code[ip + 1])
}

read_constant :: proc(frame: ^CallFrame) -> Value {
	return frame.closure.function.chunk.constants[read_byte(frame)]
}

read_string :: proc(frame: ^CallFrame) -> string {
	obj := as_object(read_constant(frame))
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
	return mem.ptr_offset(vm.stack_top, -int(distance) - 1)^
}

call_value :: proc(callee: Value, arg_count: u8) -> bool {
	if obj, ok := try_object(callee); ok {
		#partial switch obj.type {

		case .ObjBoundMethod:
			bound := cast(^ObjBoundMethod)as_object(callee)
			mem.ptr_offset(vm.stack_top, -int(arg_count) - 1)^ = bound.reciever
			return call(bound.method, arg_count)

		case .ObjClass:
			class := cast(^ObjClass)as_object(callee)
			object := cast(^Obj)new_instance(class)
			mem.ptr_offset(vm.stack_top, -int(arg_count) - 1)^ = object_val(object)
			if initializer, ok := class.methods["init"]; ok {
				return call(cast(^ObjClosure)as_object(initializer), arg_count)
			} else if arg_count != 0 {
				runtime_error("Expected 0 arguments but got %d.", arg_count)
				return false
			}
			return true

		case .ObjClosure:
			return call(cast(^ObjClosure)obj, arg_count)

		case .ObjNative:
			object := cast(^ObjNative)as_object(callee)
			native := object.function
			args_ptr := mem.ptr_offset(vm.stack_top, -int(arg_count))
			args_slice := slice.from_ptr(args_ptr, int(arg_count))
			result := native(args_slice)
			vm.stack_top = mem.ptr_offset(vm.stack_top, -int(arg_count) + 1)
			push(result)
			return true
		}
	}

	runtime_error("Can only call functions and classes.")
	return false
}

invoke :: proc(name: string, arg_count: u8) -> bool {
	reciever := peek(arg_count)

	object, ok := try_object(reciever)
	if !ok || object.type != .ObjInstance {
		runtime_error("Only instances have methods.")
		return false
	}

	instance := cast(^ObjInstance)object

	if value, ok := instance.fields[name]; ok {
		mem.ptr_offset(vm.stack_top, -int(arg_count) - 1)^ = value
		return call_value(value, arg_count)
	}

	return invoke_from_class(instance.class, name, arg_count)
}

invoke_from_class :: proc(class: ^ObjClass, name: string, arg_count: u8) -> bool {
	if method, ok := class.methods[name]; ok {
		return call(cast(^ObjClosure)as_object(method), arg_count)
	}

	runtime_error("Undefined property '%s'.", name)
	return false
}

capture_upvalue :: proc(local: ^Value) -> ^ObjUpvalue {
	prev_upvalue: ^ObjUpvalue = nil
	upvalue := vm.open_upvalues

	for upvalue != nil && upvalue.location > local {
		prev_upvalue = upvalue
		upvalue = upvalue.next_upvalue
	}

	if upvalue != nil && upvalue.location == local do return upvalue

	created_upvalue := new_upvalue(local)
	created_upvalue.next_upvalue = upvalue

	if prev_upvalue == nil do vm.open_upvalues = created_upvalue
	else do prev_upvalue.next_upvalue = created_upvalue

	return created_upvalue
}

close_upvalues :: proc(last: ^Value) {
	for vm.open_upvalues != nil && vm.open_upvalues.location >= last {
		upvalue := vm.open_upvalues
		upvalue.closed = upvalue.location^
		upvalue.location = &upvalue.closed
		vm.open_upvalues = upvalue.next_upvalue
	}

}

define_method :: proc(name: string) {
	method := peek(0)
	class := cast(^ObjClass)as_object(peek(1))
	class.methods[name] = method
	pop()
}

bind_method :: proc(class: ^ObjClass, name: string) -> bool {
	method, ok := class.methods[name]

	if !ok {
		runtime_error("Undefined property '%s'.", name)
		return false
	}

	bound := new_bound_method(peek(0), cast(^ObjClosure)as_object(method))

	pop()
	push(object_val(cast(^Obj)bound))
	return true
}

call :: proc(closure: ^ObjClosure, arg_count: u8) -> bool {
	if arg_count != closure.function.arity {
		runtime_error("Expected %d arguments but got %d.", closure.function.arity, arg_count)
		return false
	}

	if vm.frame_count == FRAMES_MAX {
		runtime_error("Stack overflow.")
		return false
	}

	frame := &vm.frames[vm.frame_count]
	vm.frame_count += 1
	frame.closure = closure
	frame.ip = 0
	frame.slots = mem.ptr_offset(vm.stack_top, -int(arg_count) - 1)
	return true
}

is_falsey :: proc(value: Value) -> bool {
	bool, ok := try_bool(value)
	return value == NIL || ok && !bool
}

concatenate :: proc(a, b: ^Obj) -> Value {
	a_str := (^ObjString)(a).str
	b_str := (^ObjString)(b).str

	c_str := strings.concatenate({a_str, b_str})
	c_obj := cast(^Obj)take_string(c_str)

	return object_val(c_obj)
}

values_equal :: proc(val_a, val_b: Value) -> Value {
	a, a_ok := try_object(val_a)
	b, b_ok := try_object(val_b)

	if a_ok && b_ok do return bool_val(a == b)
	else do return bool_val(val_a == val_b)
}

runtime_error :: proc(format: string, args: ..any) {
	if len(args) == 0 do fmt.eprintfln(format)
	else do fmt.eprintfln(format, args)

	for i := vm.frame_count - 1;; i -= 1 {
		frame := &vm.frames[i]
		function := frame.closure.function
		instruction := frame.closure.function.chunk.code[frame.ip - 1]

		fname := len(function.name) == 0 ? "script" : function.name
		fmt.eprintfln("[line %d] in %s", function.chunk.lines[instruction], fname)

		if i == 0 do break
	}

	reset_stack()
}

define_native :: proc(name: string, function: NativeFn) {
	push(object_val(copy_string(name)))
	push(object_val(new_native(function)))
	vm.globals[name] = vm.stack[1]
	pop()
	pop()
}
