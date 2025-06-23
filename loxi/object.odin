package loxi

import "core:fmt"
import "core:hash"
import "core:strings"

ObjType :: enum {
	ObjString,
	ObjFunction,
}

Obj :: struct {
	type: ObjType,
	next: ^Obj,
}

ObjString :: struct {
	using obj: Obj,
	str:       string,
}

ObjFunction :: struct {
	using obj: Obj,
	name:      string,
	chunk:     Chunk,
	arity:     u8,
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

new_function :: proc() -> ^ObjFunction {
	return allocate_object(ObjFunction, .ObjFunction)
}

free_object :: proc(obj: ^Obj) {
	switch obj.type {
	case .ObjString:
		obj_string := cast(^ObjString)obj
		delete(obj_string.str)
		free(obj_string)
	case .ObjFunction:
		function := cast(^ObjFunction)obj
		free_chunk(&function.chunk)
	}
}

print_object :: proc(object: ^Obj) {
	switch object.type {
	case .ObjString:
		fmt.printf((cast(^ObjString)object).str)
	case .ObjFunction:
		name := (^ObjFunction)(object).name
		if len(name) == 0 do fmt.print("<script>")
		else do fmt.printf("<fn %s>", name)
	}
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
