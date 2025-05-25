package loxi

OpCode :: enum u8 {
	Return,
	Constant,
	Negate,
	Add,
	Subtract,
	Multiply,
	Divide,
}

Chunk :: struct {
	code:      [dynamic]u8,
	constants: [dynamic]Value,
	lines:     [dynamic]uint,
}

free_chunk :: proc(c: ^Chunk) {
	delete(c.code)
	delete(c.constants)
	delete(c.lines)
}

write_chunk :: proc(c: ^Chunk, byte: u8, line: uint) {
	append_elem(&c.code, byte)
	append_elem(&c.lines, line)
}

add_constant :: proc(c: ^Chunk, value: Value) -> u8 {
	len := u8(len(c.constants))
	append_elem(&c.constants, value)
	return len
}
