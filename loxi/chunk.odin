package loxi

OpCode :: enum u8 {
	Return,
	Call,
	Closure,
	Jump,
	JumpIfFalse,
	Loop,
	Constant,
	DefineGlobal,
	GetGlobal,
	SetGlobal,
	GetLocal,
	SetLocal,
	GetUpvalue,
	SetUpvalue,
	CloseUpvalue,
	Nil,
	True,
	False,
	Not,
	Equal,
	Greater,
	Less,
	Negate,
	Add,
	Subtract,
	Multiply,
	Divide,
	Print,
	Pop,
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

add_constant :: proc(c: ^Chunk, value: Value) -> uint {
	len := uint(len(c.constants))
	append_elem(&c.constants, value)
	return len
}
