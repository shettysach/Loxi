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
	name:          string,
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
	name:      string,
	methods:   map[string]Value,
}

ObjInstance :: struct {
	using obj: Obj,
	class:     ^ObjClass,
	fields:    map[string]Value,
}

ObjBoundMethod :: struct {
	using obj: Obj,
	reciever:  Value,
	method:    ^ObjClosure,
}

allocate_object :: proc($T: typeid, type: ObjType) -> ^T {
	if vm.bytes_allocated > vm.next_gc do collect_garbage()

	object := new(T)
	object.type = type
	object.next = vm.objects
	vm.objects = object

	vm.bytes_allocated += size_of(T)
	when DEBUG_LOG_GC do fmt.printfln("%p allocate %v for %v", object, size_of(T), type)

	return object
}

allocate_string :: proc(str: string) -> ^ObjString {
	obj_string := allocate_object(ObjString, .ObjString)
	obj_string.str = str

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
	return allocate_object(ObjFunction, .ObjFunction)
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

new_class :: proc(name: string) -> ^ObjClass {
	class := allocate_object(ObjClass, .ObjClass)
	class.name = name
	class.methods = make(map[string]Value)
	return class
}

new_instance :: proc(class: ^ObjClass) -> ^ObjInstance {
	instance := allocate_object(ObjInstance, .ObjInstance)
	instance.class = class
	instance.fields = make(map[string]Value)
	return instance
}

new_bound_method :: proc(reciever: Value, method: ^ObjClosure) -> ^ObjBoundMethod {
	bound := allocate_object(ObjBoundMethod, .ObjBoundMethod)
	bound.reciever = reciever
	bound.method = method
	return bound
}

free_object :: proc(object: ^Obj) {
	// TODO: Inaccurate. Needs to include fields etc
	when DEBUG_LOG_GC do fmt.printfln("%p free type %v", object, object.type)

	switch object.type {
	case .ObjString:
		obj_string := cast(^ObjString)object

		vm.bytes_allocated -= size_of(obj_string.str)
		delete(obj_string.str)

		vm.bytes_allocated -= size_of(obj_string)
		free(obj_string)

	case .ObjClosure:
		closure := cast(^ObjClosure)object

		vm.bytes_allocated -= size_of(closure.upvalues)
		delete(closure.upvalues)

		vm.bytes_allocated -= size_of(closure)
		free(closure)

	case .ObjFunction:
		function := cast(^ObjFunction)object

		vm.bytes_allocated -= size_of(function.chunk)
		free_chunk(&function.chunk)

		when REPL {
			vm.bytes_allocated -= size_of(function.name)
			delete(function.name)
		}

		vm.bytes_allocated -= size_of(function)
		free(function)

	case .ObjNative:
		native := cast(^ObjUpvalue)object
		free(native)

	case .ObjUpvalue:
		upvalue := cast(^ObjUpvalue)object

		vm.bytes_allocated -= size_of(upvalue)
		free(upvalue)

	case .ObjClass:
		class := cast(^ObjClass)object

		vm.bytes_allocated -= size_of(class.methods)
		delete(class.methods)

		vm.bytes_allocated -= size_of(class)
		free(class)

	case .ObjInstance:
		instance := cast(^ObjInstance)object

		vm.bytes_allocated -= size_of(instance.fields)
		delete(instance.fields)

		vm.bytes_allocated -= size_of(instance)
		free(instance)

	case .ObjBoundMethod:
		bound := cast(^ObjBoundMethod)object

		vm.bytes_allocated -= size_of(bound)
		free(bound)

	}
}

print_object :: proc(object: ^Obj) {
	switch object.type {
	case .ObjString:
		fmt.print((^ObjString)(object).str)
	case .ObjClosure:
		function := (^ObjClosure)(object).function
		print_function(function)
	case .ObjFunction:
		function := cast(^ObjFunction)object
		print_function(function)
	case .ObjNative:
		fmt.print("<native fn>")
	case .ObjUpvalue:
		fmt.print("upvalue")
	case .ObjClass:
		class := cast(^ObjClass)object
		fmt.printf("<class %s>", class.name)
	case .ObjInstance:
		instance := cast(^ObjInstance)object
		fmt.printf("<instance %s>", instance.class.name)
	case .ObjBoundMethod:
		bound_method := cast(^ObjBoundMethod)object
		print_function(bound_method.method.function)
	}
}

print_function :: proc(function: ^ObjFunction) {
	name := function.name
	if len(name) == 0 do fmt.print("<script>")
	else do fmt.printf("<fn %s>", name)
}
