package loxi

import "core:fmt"
import "core:strings"

ObjType :: enum {
	ObjString,
	ObjFunction,
	ObjNative,
	ObjClosure,
	ObjUpvalue,
	ObjClass,
	ObjInstance,
	ObjBoundMethod,
}

Obj :: struct {
	type:      ObjType,
	next:      ^Obj,
	is_marked: bool,
}

ObjString :: struct {
	using obj: Obj,
	str:       string,
}

ObjClosure :: struct {
	using obj:     Obj,
	function:      ^ObjFunction,
	upvalues:      []^ObjUpvalue,
	upvalue_count: u8,
}

ObjFunction :: struct {
	using obj:     Obj,
	chunk:         Chunk,
	name:          ^ObjString,
	arity:         u8,
	upvalue_count: u8,
}

ObjNative :: struct {
	using obj: Obj,
	function:  NativeFn,
}

NativeFn :: proc(args: []Value) -> Value

ObjUpvalue :: struct {
	using obj:    Obj,
	location:     ^Value,
	closed:       Value,
	next_upvalue: ^ObjUpvalue,
}

ObjClass :: struct {
	using obj: Obj,
	name:      ^ObjString,
	methods:   map[^ObjString]Value,
}

ObjInstance :: struct {
	using obj: Obj,
	class:     ^ObjClass,
	fields:    map[^ObjString]Value,
}

ObjBoundMethod :: struct {
	using obj: Obj,
	reciever:  Value,
	method:    ^ObjClosure,
}

allocate_object :: proc($T: typeid, type: ObjType) -> ^T {
	when DEBUG_STRESS_GC {
		collect_garbage()
	} else do if vm.bytes_allocated > vm.next_gc {
		collect_garbage()
	}

	object := new(T)
	object.type = type
	object.next = vm.objects
	vm.objects = object

	size: uint = size_of(T)
	vm.bytes_allocated += size

	when DEBUG_LOG_GC do fmt.printfln("%p allocate %v bytes for %v", object, size, type)

	return object
}

allocate_string :: proc(str: string) -> ^ObjString {
	obj_string := allocate_object(ObjString, .ObjString)
	obj_string.str = str

	vm.bytes_allocated += size_of(str)
	when DEBUG_LOG_GC do fmt.printfln(
		"%p intern string \"%s\" (%v bytes)",
		obj_string,
		str,
		size_of(str[0]) * len(str),
	)

	push(object_val(obj_string))
	vm.strings[str] = obj_string
	pop()

	return obj_string
}

copy_string :: proc(str: string) -> ^ObjString {
	interned, ok := vm.strings[str]
	if ok do return interned

	duplicate := strings.clone(str)
	return allocate_string(duplicate)
}

take_string :: proc(str: string) -> ^ObjString {
	interned, ok := vm.strings[str]
	if ok {
		delete(str)
		return interned
	}

	return allocate_string(str)
}

new_closure :: proc(function: ^ObjFunction) -> ^ObjClosure {
	closure := allocate_object(ObjClosure, .ObjClosure)
	closure.function = function
	upvalue_count := function.upvalue_count
	closure.upvalues = make([]^ObjUpvalue, upvalue_count)
	closure.upvalue_count = upvalue_count
	return closure
}

new_function :: proc() -> ^ObjFunction {
	function := allocate_object(ObjFunction, .ObjFunction)
	function.chunk = init_chunk()
	return function
}

new_native :: proc(function: NativeFn) -> ^ObjNative {
	native := allocate_object(ObjNative, .ObjNative)
	native.function = function
	return native
}

new_upvalue :: proc(slot: ^Value) -> ^ObjUpvalue {
	upvalue := allocate_object(ObjUpvalue, .ObjUpvalue)
	upvalue.location = slot
	upvalue.closed = NIL
	return upvalue
}

new_class :: proc(name: ^ObjString) -> ^ObjClass {
	class := allocate_object(ObjClass, .ObjClass)
	class.name = name
	class.methods = make(map[^ObjString]Value)
	return class
}

new_instance :: proc(class: ^ObjClass) -> ^ObjInstance {
	instance := allocate_object(ObjInstance, .ObjInstance)
	instance.class = class
	instance.fields = make(map[^ObjString]Value)
	return instance
}

new_bound_method :: proc(reciever: Value, method: ^ObjClosure) -> ^ObjBoundMethod {
	bound := allocate_object(ObjBoundMethod, .ObjBoundMethod)
	bound.reciever = reciever
	bound.method = method
	return bound
}

free_object :: proc(object: ^Obj) {
	when DEBUG_LOG_GC do fmt.printfln("%p free type %v", object, object.type)

	switch object.type {
	case .ObjString:
		obj := cast(^ObjString)object

		vm.bytes_allocated -= size_of(obj.str)
		delete(obj.str)

		vm.bytes_allocated -= size_of(ObjString)
		free(obj)

	case .ObjClosure:
		obj := cast(^ObjClosure)object

		vm.bytes_allocated -= size_of(obj.upvalues)
		delete(obj.upvalues)

		vm.bytes_allocated -= size_of(ObjClosure)
		free(obj)

	case .ObjFunction:
		obj := cast(^ObjFunction)object
		free_chunk(&obj.chunk)

		vm.bytes_allocated -= size_of(ObjFunction)
		free(obj)

	case .ObjNative:
		obj := cast(^ObjNative)object
		vm.bytes_allocated -= size_of(ObjNative)
		free(obj)

	case .ObjUpvalue:
		obj := cast(^ObjUpvalue)object
		vm.bytes_allocated -= size_of(ObjUpvalue)
		free(obj)

	case .ObjClass:
		obj := cast(^ObjClass)object
		vm.bytes_allocated -= size_of(obj.methods)
		delete(obj.methods)

		vm.bytes_allocated -= size_of(ObjClass)
		free(obj)

	case .ObjInstance:
		obj := cast(^ObjInstance)object
		vm.bytes_allocated -= size_of(obj.fields)
		delete(obj.fields)

		vm.bytes_allocated -= size_of(ObjInstance)
		free(obj)

	case .ObjBoundMethod:
		obj := cast(^ObjBoundMethod)object
		vm.bytes_allocated -= size_of(ObjBoundMethod)
		free(obj)
	}
}

print_object :: proc(object: ^Obj) {
	switch object.type {
	case .ObjString:
		write_out((^ObjString)(object).str)
	case .ObjClosure:
		function := (^ObjClosure)(object).function
		print_function(function)
	case .ObjFunction:
		function := cast(^ObjFunction)object
		print_function(function)
	case .ObjNative:
		write_out("<native fn>")
	case .ObjUpvalue:
		write_out("upvalue")
	case .ObjClass:
		class := cast(^ObjClass)object
		write_out(fmt.aprintf("<class %s>", class.name.str))
	case .ObjInstance:
		instance := cast(^ObjInstance)object
		write_out(fmt.aprintf("<instance %s>", instance.class.name.str))
	case .ObjBoundMethod:
		bound_method := cast(^ObjBoundMethod)object
		print_function(bound_method.method.function)
	}
}

print_function :: proc(function: ^ObjFunction) {
	name := function.name
	if name == nil do write_out("<script>")
	else do write_out(fmt.aprintf("<fn %s>", name.str))
}
