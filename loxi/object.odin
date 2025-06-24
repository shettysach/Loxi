package loxi

import "core:fmt"
import "core:hash"
import "core:strings"

ObjType :: enum {
	ObjString,
	ObjFunction,
	ObjClosure,
	ObjUpvalue,
}

Obj :: struct {
	type: ObjType,
	next: ^Obj,
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

ObjUpvalue :: struct {
	using obj:    Obj,
	location:     ^Value,
	closed:       Value,
	next_upvalue: ^ObjUpvalue,
}


allocate_object :: proc($T: typeid, type: ObjType) -> ^T {
	object := new(T)
	object.type = type
	object.next = vm.objects
	vm.objects = object
	return object
}

allocate_string :: proc(str: string) -> ^ObjString {
	obj_string := allocate_object(ObjString, .ObjString)
	obj_string.str = str
	vm.strings[str] = obj_string
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
	closure.upvalues = make([]^ObjUpvalue, upvalue_count) // NOTE: Dynamic needed?
	closure.upvalue_count = upvalue_count
	return closure
}

new_function :: proc() -> ^ObjFunction {
	return allocate_object(ObjFunction, .ObjFunction)
}

new_upvalue :: proc(slot: ^Value) -> ^ObjUpvalue {
	upvalue := allocate_object(ObjUpvalue, .ObjUpvalue)
	upvalue.location = slot
	upvalue.closed = Nil{}
	return upvalue
}

free_object :: proc(obj: ^Obj) {
	switch obj.type {
	case .ObjString:
		obj_string := cast(^ObjString)obj
		delete(obj_string.str)
		free(obj_string)
	case .ObjClosure:
		closure := cast(^ObjClosure)obj
		delete(closure.upvalues)
		free(closure)
	case .ObjFunction:
		function := cast(^ObjFunction)obj
		free_chunk(&function.chunk)
		free(function)
	case .ObjUpvalue:
		upvalue := cast(^Upvalue)obj
		free(upvalue)
	}
}

print_object :: proc(object: ^Obj) {
	switch object.type {
	case .ObjString:
		fmt.printf((^ObjString)(object).str)
	case .ObjClosure:
		function := (^ObjClosure)(object).function
		print_function(function)
	case .ObjFunction:
		function := (^ObjFunction)(object)
		print_function(function)
	case .ObjUpvalue:
		fmt.print("upvalue")
	}
}

print_function :: proc(function: ^ObjFunction) {
	name := function.name
	if len(name) == 0 do fmt.print("<script>")
	else do fmt.printf("<fn %s>", name)
}
