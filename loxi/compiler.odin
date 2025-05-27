package loxi

import "core:fmt"
import "core:strconv"

compile :: proc(source: ^[]u8, chunk: ^Chunk) -> bool {
	init_scanner(source)
	compiling_chunk = chunk

	parser.line = 0
	parser.had_error = false
	parser.panic_mode = false

	advance()
	expression()
	consume(.Eof, "Expect EOF")

	end_compiler()
	return !parser.had_error
}

end_compiler :: proc() {
	emit_return()

	if DEBUG_PRINT_CODE {
		if !parser.had_error {
			disassemble_chunk(current_chunk(), "code")
		}
	}
}

Parser :: struct {
	current:    Token,
	previous:   Token,
	line:       uint,
	had_error:  bool,
	panic_mode: bool,
}

parser := Parser{}
compiling_chunk := &Chunk{}

expression :: proc() {
	parse_precedence(.Assignment)
}

grouping :: proc() {
	expression()
	consume(.RightParen, "Expect ')' after expression")
}

@(private = "file")
number :: proc() {
	value := strconv.atof(parser.previous.lexeme)
	emit_constant(value)
}

unary :: proc() {
	op_type := parser.previous.ttype

	parse_precedence(.Unary)

	#partial switch op_type {
	case .Bang:
		emit_byte(u8(OpCode.Not))
	case .Minus:
		emit_byte(u8(OpCode.Negate))
	case:
		return
	}
}

binary :: proc() {
	op_type := parser.previous.ttype
	rule := get_rule(op_type)

	parse_precedence(Precedence(u8(rule.precedence) + 1))

	#partial switch op_type {
	case .BangEqual:
		emit_bytes(u8(OpCode.Equal), u8(OpCode.Not))
	case .EqualEqual:
		emit_byte(u8(OpCode.Equal))
	case .Greater:
		emit_byte(u8(OpCode.Greater))
	case .GreaterEqual:
		emit_bytes(u8(OpCode.Less), u8(OpCode.Not))
	case .Less:
		emit_byte(u8(OpCode.Less))
	case .LessEqual:
		emit_bytes(u8(OpCode.Greater), u8(OpCode.Not))
	case .Plus:
		emit_byte(u8(OpCode.Add))
	case .Minus:
		emit_byte(u8(OpCode.Subtract))
	case .Star:
		emit_byte(u8(OpCode.Multiply))
	case .Slash:
		emit_byte(u8(OpCode.Divide))
	case:
		return
	}
}

literal :: proc() {
	op_type := parser.previous.ttype

	#partial switch op_type {
	case .False:
		emit_byte(u8(OpCode.False))
	case .Nil:
		emit_byte(u8(OpCode.Nil))
	case .True:
		emit_byte(u8(OpCode.True))
	case:
		return
	}
}


Precedence :: enum {
	None,
	Assignment,
	Or,
	And,
	Equality,
	Comparison,
	Term,
	Factor,
	Unary,
	Call,
	Primary,
}

ParseRule :: struct {
	prefix:     ParseFn,
	infix:      ParseFn,
	precedence: Precedence,
}

ParseFn :: proc()

parse_precedence :: proc(precedence: Precedence) {
	advance()
	prefix_rule := get_rule(parser.previous.ttype).prefix

	if prefix_rule == nil {
		error_at_current("Expect expression")
		return
	}

	prefix_rule()

	for precedence <= get_rule(parser.current.ttype).precedence {
		advance()
		infix_rule := get_rule(parser.previous.ttype).infix
		infix_rule()
	}
}

get_rule :: proc(ttype: TokenType) -> ^ParseRule {
	return &rules[ttype]
}

@(rodata)
rules := []ParseRule {
	TokenType.LeftParen    = ParseRule{grouping, nil, .None},
	TokenType.RightParen   = ParseRule{nil, nil, .None},
	TokenType.LeftBrace    = ParseRule{nil, nil, .None},
	TokenType.RightBrace   = ParseRule{nil, nil, .None},
	TokenType.Comma        = ParseRule{nil, nil, .None},
	TokenType.Dot          = ParseRule{nil, nil, .None},
	TokenType.Minus        = ParseRule{unary, binary, .Term},
	TokenType.Plus         = ParseRule{nil, binary, .Term},
	TokenType.Semicolon    = ParseRule{nil, nil, .None},
	TokenType.Slash        = ParseRule{nil, binary, .Factor},
	TokenType.Star         = ParseRule{nil, binary, .Factor},
	TokenType.Bang         = ParseRule{unary, nil, .None},
	TokenType.BangEqual    = ParseRule{nil, binary, .Equality},
	TokenType.Equal        = ParseRule{nil, nil, .None},
	TokenType.EqualEqual   = ParseRule{nil, binary, .Equality},
	TokenType.Greater      = ParseRule{nil, binary, .Comparison},
	TokenType.GreaterEqual = ParseRule{nil, binary, .Comparison},
	TokenType.Less         = ParseRule{nil, binary, .Comparison},
	TokenType.LessEqual    = ParseRule{nil, binary, .Comparison},
	TokenType.Identifier   = ParseRule{nil, binary, .Comparison},
	TokenType.String       = ParseRule{nil, nil, .None},
	TokenType.Number       = ParseRule{number, nil, .None},
	TokenType.And          = ParseRule{nil, nil, .None},
	TokenType.Class        = ParseRule{nil, nil, .None},
	TokenType.Else         = ParseRule{nil, nil, .None},
	TokenType.False        = ParseRule{literal, nil, .None},
	TokenType.For          = ParseRule{nil, nil, .None},
	TokenType.Fun          = ParseRule{nil, nil, .None},
	TokenType.If           = ParseRule{nil, nil, .None},
	TokenType.Nil          = ParseRule{literal, nil, .None},
	TokenType.Or           = ParseRule{nil, nil, .None},
	TokenType.Print        = ParseRule{nil, nil, .None},
	TokenType.Return       = ParseRule{nil, nil, .None},
	TokenType.Super        = ParseRule{nil, nil, .None},
	TokenType.This         = ParseRule{nil, nil, .None},
	TokenType.True         = ParseRule{literal, nil, .None},
	TokenType.Var          = ParseRule{nil, nil, .None},
	TokenType.While        = ParseRule{nil, nil, .None},
	TokenType.Error        = ParseRule{nil, nil, .None},
	TokenType.Eof          = ParseRule{nil, nil, .None},
}

@(private = "file")
advance :: proc() {
	parser.previous = parser.current

	for {
		parser.current = scan_token()
		if (parser.current.ttype != .Error) {break}
		error_at_current(parser.current.lexeme)
	}
}

consume :: proc(ttype: TokenType, msg: string) {
	if (parser.current.ttype == ttype) {
		advance()
		return
	}

	error_at_current(msg)
}

emit_byte :: proc(byte: u8) {
	write_chunk(current_chunk(), byte, parser.previous.line)
}

emit_return :: proc() {
	emit_byte(u8(OpCode.Return))
}

emit_bytes :: proc(byte1, byte2: u8) {
	emit_byte(byte1)
	emit_byte(byte2)
}

emit_constant :: proc(value: Value) {
	emit_bytes(u8(OpCode.Constant), make_constant(value))
}

make_constant :: proc(value: Value) -> u8 {
	constant := add_constant(current_chunk(), value)

	if constant > max(u8) {
		error_at_current("Too many constants in 1 chunk.")
		return 0
	}

	return constant

}

current_chunk :: proc() -> ^Chunk {
	return compiling_chunk
}

error_at_previous :: proc(msg: string) {
	error_at(&parser.previous, msg)
}

error_at_current :: proc(msg: string) {
	error_at(&parser.current, msg)
}

error_at :: proc(token: ^Token, msg: string) {
	if parser.panic_mode {return}
	parser.panic_mode = true

	fmt.eprintf("[line %d] Error", token.line)

	if (token.ttype == .Eof) {
		fmt.eprint(" at end")
	} else if (token.ttype != .Error) {
		fmt.eprintf(" at '%s'", token.lexeme)
	}

	fmt.eprintf(": %s\n", msg)
	parser.had_error = true
}
