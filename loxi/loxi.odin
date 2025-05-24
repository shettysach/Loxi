package loxi

import "core:os"
import "core:strings"

main :: proc() {
	chunk := Chunk{}

	constant := add_constant(&chunk, 1.2)

	write_chunk(&chunk, u8(OpCode.Constant), 123)
	write_chunk(&chunk, constant, 123)

	write_chunk(&chunk, u8(OpCode.Constant), 123)
	write_chunk(&chunk, constant, 123)

	write_chunk(&chunk, u8(OpCode.Return), 123)

	disassemble_chunk(&chunk, "test_chunk")

	free_chunk(&chunk)

}
