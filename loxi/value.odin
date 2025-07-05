package loxi

import "core:fmt"

NAN_BOXING :: #config(NAN_BOXING, false)

when NAN_BOXING {

	Value :: distinct u64

	NIL :: QNAN | 0b01
	FALSE :: QNAN | 0b10
	TRUE :: QNAN | 0b11

	QNAN: Value : 0x7ffc000000000000
	SIGN_BIT: Value : 0x8000000000000000

} else {

	Value :: union {
		f64,
		bool,
		^Obj,
		Nil,
	}

	NIL :: Nil{}
	FALSE :: false
	TRUE :: true


	Nil :: struct {
	}
}

number_val :: proc(number: f64) -> Value {
	return transmute(Value)number when NAN_BOXING else number
}

try_number :: proc(value: Value) -> (f64, bool) {
	when NAN_BOXING {
		return transmute(f64)value, value & QNAN != QNAN
	} else {
		return value.(f64)
	}
}

bool_val :: #force_inline proc(b: bool) -> Value {
	return b ? TRUE : FALSE
}

try_bool :: proc(value: Value) -> (bool, bool) {
	when NAN_BOXING {
		return value == TRUE, value | 1 == TRUE
	} else {
		return value.(bool)
	}
}

object_val :: proc(object: ^Obj) -> Value {
	return SIGN_BIT | QNAN | cast(Value)uintptr(object) when NAN_BOXING else object
}

as_object :: proc(value: Value) -> ^Obj {
	return cast(^Obj)uintptr(value & ~(SIGN_BIT | QNAN)) when NAN_BOXING else value.(^Obj)
}

try_object :: proc(value: Value) -> (^Obj, bool) {
	when NAN_BOXING {
		return as_object(value), value & (QNAN | SIGN_BIT) == QNAN | SIGN_BIT
	} else {
		return value.(^Obj)
	}
}

print_value :: proc(value: Value) {
	when NAN_BOXING {
		if number, ok := try_number(value); ok do fmt.print(number)
		else if bool, ok := try_bool(value); ok do fmt.print(bool)
		else if object, ok := try_object(value); ok do print_object(object)
		else if value == NIL do fmt.print("nil")
	} else {
		if object, ok := value.(^Obj); ok do print_object(object)
		else do fmt.print(value)
	}
}

