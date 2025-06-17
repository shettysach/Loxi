package loxi

import "core:fmt"
import "core:hash"
import "core:strings"

ObjType :: enum {
	ObjString,
}

Obj :: struct {
	type: ObjType,
	next: ^Obj,
}

ObjString :: struct {
	using obj: Obj,
	str:       string,
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

free_object :: proc(obj: ^Obj) {
	switch obj.type {
	case .ObjString:
		obj_string := cast(^ObjString)obj
		delete(obj_string.str)
		free(obj_string)
	}
}

print_object :: proc(object: ^Obj) {
	switch object.type {
	case .ObjString:
		fmt.printf("\"%v\"", (cast(^ObjString)object).str)
	case:
		fmt.print(object)
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
