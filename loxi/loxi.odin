package loxi

import "core:os"
import "core:strings"


import "core:fmt"

main :: proc() {
	chunk := Chunk{}

	constant_0 := add_constant(&chunk, 1.2)
	write_chunk(&chunk, u8(OpCode.Constant), 123)
	write_chunk(&chunk, constant_0, 123)

	constant_1 := add_constant(&chunk, 3.4)
	write_chunk(&chunk, u8(OpCode.Constant), 123)
	write_chunk(&chunk, constant_1, 123)

	write_chunk(&chunk, u8(OpCode.Add), 123)

	constant_2 := add_constant(&chunk, 5.6)
	write_chunk(&chunk, u8(OpCode.Constant), 123)
	write_chunk(&chunk, constant_1, 123)

	write_chunk(&chunk, u8(OpCode.Divide), 123)
	write_chunk(&chunk, u8(OpCode.Negate), 123)

	write_chunk(&chunk, u8(OpCode.Return), 123)

	interpret(&chunk)
	free_vm()
}
