package loxi

import "core:fmt"
import "core:mem"

GC_HEAP_GROW_FACTOR: uint = 2

collect_garbage :: proc() {
	when DEBUG_LOG_GC {
		fmt.println("-- gc begin")
		before := vm.bytes_allocated
	}

	mark_roots()
	trace_references()
	table_remove_white(&vm.strings)
	sweep()

	vm.next_gc = vm.bytes_allocated * GC_HEAP_GROW_FACTOR

	when DEBUG_LOG_GC {
		fmt.printfln("-- gc end")
		fmt.printfln(
			"   collected %v bytes (from %v to %v) next at %v",
			before - vm.bytes_allocated,
			before,
			vm.bytes_allocated,
			vm.next_gc,
		)
	}
}

mark_roots :: proc() {
	for slot := &vm.stack[0]; slot < vm.stack_top; slot = mem.ptr_offset(slot, 1) do mark_value(slot^)
	for i in 0 ..< vm.frame_count do mark_object(vm.frames[i].closure)
	for upvalue := vm.open_upvalues; upvalue != nil; upvalue = upvalue.next_upvalue do mark_object(upvalue)

	mark_table(&vm.globals)
	mark_compiler_roots()
	mark_object(vm.init_string)
}

mark_value :: proc(value: Value) {
	if object, ok := try_object(value); ok do mark_object(object)
}

mark_array :: proc(array: ^[dynamic]Value) {
	for v in array do mark_value(v)
}

mark_object :: proc(object: ^Obj) {
	if object == nil do return
	if object.is_marked do return

	when DEBUG_LOG_GC {
		fmt.printf("%p mark ", object)
		print_object(object)
		fmt.println()
	}

	object.is_marked = true
	append_elem(&vm.gray_stack, object)
}

mark_table :: proc(table: ^map[^ObjString]Value) {
	for k, v in table {
		mark_object(k)
		mark_value(v)
	}
}

mark_compiler_roots :: proc() {
	compiler := current
	for compiler != nil {
		mark_object(compiler.function)
		compiler = compiler.enclosing
	}
}

trace_references :: proc() {
	for o in vm.gray_stack do blacken_object(o)
	clear(&vm.gray_stack)
}

blacken_object :: proc(object: ^Obj) {
	when DEBUG_LOG_GC {
		fmt.printf("%p blacken ", object)
		print_object(object)
		fmt.println()
	}

	#partial switch object.type {
	case .ObjClosure:
		closure := cast(^ObjClosure)object
		mark_object(closure.function)
		for upval in closure.upvalues do mark_object(upval)
	case .ObjFunction:
		function := cast(^ObjFunction)object
		mark_object(function.name)
		mark_array(&function.chunk.constants)
	case .ObjUpvalue:
		mark_value((^ObjUpvalue)(object).closed)
	case .ObjClass:
		class := cast(^ObjClass)object
		mark_object(class.name)
		mark_table(&class.methods)
	case .ObjInstance:
		instance := cast(^ObjInstance)object
		mark_object(instance.class)
		mark_table(&instance.fields)
	case .ObjBoundMethod:
		bound := cast(^ObjBoundMethod)object
		mark_value(bound.reciever)
		mark_object(bound.method)
	case .ObjList:
		list := cast(^ObjList)object
		for item in list.items do mark_value(item)
	}
}

table_remove_white :: proc(table: ^map[string]^ObjString) {
	for k, v in table do if !v.is_marked do delete_key(table, k)
}

sweep :: proc() {
	previous: ^Obj = nil
	object := vm.objects
	for object != nil {
		if object.is_marked {
			object.is_marked = false
			previous = object
			object = object.next
		} else {
			unreached := object
			object = object.next
			if previous != nil do previous.next = object
			else do vm.objects = object

			free_object(unreached)
		}
	}
}
