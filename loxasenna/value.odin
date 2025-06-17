package loxi

import "core:fmt"

Nil :: struct {
}

Value :: union #no_nil {
	f64,
	bool,
	Nil,
	^Obj,
}

print_value :: proc(value: Value) {
	#partial switch v in value {
	case ^Obj:
		print_object(v)
	case:
		fmt.print(value)
	}
}

is_obj_type :: proc(value: Value, type: ObjType) -> bool {
	obj, ok := value.(^Obj)
	return ok && obj.type == type
}

is_string :: proc(value: Value) -> bool {
	return is_obj_type(value, .ObjString)
}
