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
	hash:      u32,
}

free_object :: proc(object: ^Obj) {
	switch object.type {
	case .ObjString:
		obj_string := cast(^ObjString)object
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
	duplicate := strings.clone(str) or_else panic("Couldn't copy string.")
	hash := hash_string(duplicate)

	// interned := table_find_string(&vm.strings, str, hash)
	// if interned != nil do return interned

	return allocate_string(duplicate, hash)
}

allocate_string :: proc(str: string, hash: u32) -> ^ObjString {
	obj_string := allocate_object(ObjString, .ObjString)
	obj_string.str = str
	obj_string.hash = hash
	// table_set(&vm.strings, obj_string, NIL_VAL())
	return obj_string
}

hash_string :: proc "contextless" (str: string) -> u32 {
	bytes := transmute([]u8)str
	return hash.fnv32a(bytes)
}

take_string :: proc(str: string) -> ^ObjString {
	hash := hash_string(str)

	// interned := table_find_string(&vm.strings, str, hash)
	// if interned != nil {
	// 	delete(str)
	// 	return interned
	// }

	return allocate_string(str, hash)
}

allocate_object :: proc($T: typeid, type: ObjType) -> ^T {
	object := new(T)
	object.type = type
	object.next = vm.objects
	vm.objects = object
	return object
}
