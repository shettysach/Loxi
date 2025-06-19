package loxi

import "core:fmt"
import "core:strconv"

Parser :: struct {
	current:    Token,
	previous:   Token,
	line:       uint,
	had_error:  bool,
	panic_mode: bool,
}

ParseRule :: struct {
	prefix:     ParseFn,
	infix:      ParseFn,
	precedence: Precedence,
}

ParseFn :: proc(can_assign: bool)

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

Compiler :: struct {
	locals:      [256]Local,
	local_count: u8,
	scope_depth: u8,
}

Local :: struct {
	name:  Token,
	depth: Maybe(u8),
}

parser := Parser{}
compiler := Compiler{}
compiling_chunk := &Chunk{}

compile :: proc(source: ^[]u8, chunk: ^Chunk) -> bool {
	init_scanner(source)
	compiler = Compiler{}
	compiling_chunk = chunk
	parser = Parser{}

	advance()

	for !match(.Eof) {
		declaration()
	}

	end_compiler()
	return !parser.had_error
}

end_compiler :: proc() {
	emit_return()

	if DEBUG_PRINT_CODE && !parser.had_error {
		disassemble_chunk(current_chunk(), "code")
	}

}

begin_scope :: #force_inline proc() {
	compiler.scope_depth += 1
}

end_scope :: proc() {
	compiler.scope_depth -= 1

	for compiler.local_count > 0 &&
	    compiler.locals[compiler.local_count - 1].depth.(u8) > compiler.scope_depth {
		emit_code(OpCode.Pop)
		compiler.local_count -= 1
	}
}

declaration :: proc() {
	if match(.Var) do var_declaration()
	else do statement()

	if parser.panic_mode do synchronize()
}

statement :: proc() {
	if match(.Print) {
		print_statement()
	} else if match(.If) {
		if_statement()
	} else if match(.While) {
		while_statement()
	} else if match(.For) {
		for_statement()
	} else if match(.LeftBrace) {
		begin_scope()
		block()
		end_scope()
	} else {
		expression_statement()
	}
}

print_statement :: proc() {
	expression()
	consume(.Semicolon, "Expect ; after value")
	emit_code(OpCode.Print)
}

expression_statement :: proc() {
	expression()
	consume(.Semicolon, "Expect ; after expression")
	emit_code(OpCode.Pop)
}

if_statement :: proc() {
	consume(.LeftParen, "Expect '(' after 'if'.")
	expression()
	consume(.RightParen, "Expect ')' after condition.")

	then_jump := emit_jump(OpCode.JumpIfFalse)
	emit_code(OpCode.Pop)
	statement()

	else_jump := emit_jump(OpCode.Jump)

	patch_jump(then_jump)

	if match(.Else) do statement()
	patch_jump(else_jump)
}

while_statement :: proc() {
	loop_start := len(current_chunk().code)
	consume(.LeftParen, "Expect '(' after 'while'.")
	expression()
	consume(.RightParen, "Expect ')' after condition.")

	exit_jump := emit_jump(OpCode.JumpIfFalse)
	emit_code(OpCode.Pop)
	statement()

	emit_loop(loop_start)

	patch_jump(exit_jump)
	emit_code(OpCode.Pop)
}

for_statement :: proc() {
	begin_scope()
	consume(.LeftParen, "Expect '(' after 'for'.")

	if match(.Semicolon) {
		// No initiaizer
	} else if match(.Var) {
		var_declaration()
	} else {
		expression_statement()
	}

	loop_start := len(current_chunk().code)
	// consume(.Semicolon, "Expect ';'.")

	exit_jump: Maybe(uint) = nil
	if !match(.Semicolon) {
		expression()
		consume(.Semicolon, "Expect ';' after loop condition.")

		exit_jump = emit_jump(OpCode.JumpIfFalse)
		emit_code(.Pop)
	}
	// consume(.Semicolon, "Expect ';'.")
	// consume(.LeftParen, "Expect ')' after for clauses.")

	if !match(.RightParen) {
		body_jump := emit_jump(OpCode.Jump)
		increment_start := len(current_chunk().code)
		expression()
		emit_code(.Pop)
		consume(.RightParen, "Expect ')' after for clauses.")

		emit_loop(loop_start)
		loop_start = increment_start
		patch_jump(body_jump)
	}

	statement()
	emit_loop(loop_start)

	if jump, ok := exit_jump.(uint); ok {
		patch_jump(jump)
		emit_code(OpCode.Pop)
	}

	end_scope()
}

var_declaration :: proc() {
	global := parse_variable("Expect variable name.")

	if (match(.Equal)) do expression()
	else do emit_code(OpCode.Nil)
	consume(.Semicolon, "Expect ';' after variable declaration.")

	define_variable(global)
}

synchronize :: proc() {
	parser.panic_mode = false

	for parser.current.ttype != .Eof {
		if parser.previous.ttype != .Semicolon do return

		#partial switch parser.current.ttype {
		case .Class:
			return
		case .Fun:
			return
		case .Var:
			return
		case .For:
			return
		case .If:
			return
		case .While:
			return
		case .Print:
			return
		case .Return:
			return
		}

		advance()
	}
}

expression :: proc() {
	parse_precedence(.Assignment)
}

block :: proc() {
	for !check(.RightBrace) && !check(.Eof) do declaration()
	consume(.RightBrace, "Expect '}' after block.")
}

grouping :: proc(can_assign: bool) {
	expression()
	consume(.RightParen, "Expect ')' after expression")
}

@(private = "file")
number :: proc(can_assign: bool) {
	value := strconv.atof(parser.previous.lexeme)
	emit_constant(value)
}

string_parse :: proc(can_assign: bool) {
	lexeme := parser.previous.lexeme
	trimmed := lexeme[1:len(lexeme) - 1]
	object := cast(^Obj)copy_string(trimmed)
	emit_constant(Value(object))
}

named_variable :: proc(name: ^Token, can_assign: bool) {
	get_op: u8 = 0
	set_op: u8 = 0
	arg, ok := resolve_local(&compiler, name)

	if ok {
		get_op = u8(OpCode.GetLocal)
		set_op = u8(OpCode.SetLocal)
	} else {
		arg := identifier_constant(name)
		get_op = u8(OpCode.GetGlobal)
		set_op = u8(OpCode.SetGlobal)
	}

	if can_assign && match(.Equal) {
		expression()
		emit_bytes(set_op, arg)
	} else {
		emit_bytes(get_op, arg)
	}
}

variable :: proc(can_assign: bool) {
	named_variable(&parser.previous, can_assign)
}

unary :: proc(can_assign: bool) {
	op_type := parser.previous.ttype

	parse_precedence(.Unary)

	#partial switch op_type {
	case .Bang:
		emit_code(OpCode.Not)
	case .Minus:
		emit_code(OpCode.Negate)
	case:
		return
	}
}

binary :: proc(can_assign: bool) {
	op_type := parser.previous.ttype
	rule := get_rule(op_type)

	parse_precedence(Precedence(u8(rule.precedence) + 1))

	#partial switch op_type {
	case .BangEqual:
		emit_bytes(u8(OpCode.Equal), u8(OpCode.Not))
	case .EqualEqual:
		emit_code(OpCode.Equal)
	case .Greater:
		emit_code(OpCode.Greater)
	case .GreaterEqual:
		emit_bytes(u8(OpCode.Less), u8(OpCode.Not))
	case .Less:
		emit_code(OpCode.Less)
	case .LessEqual:
		emit_bytes(u8(OpCode.Greater), u8(OpCode.Not))
	case .Plus:
		emit_code(OpCode.Add)
	case .Minus:
		emit_code(OpCode.Subtract)
	case .Star:
		emit_code(OpCode.Multiply)
	case .Slash:
		emit_code(OpCode.Divide)
	case:
		return
	}
}

literal :: proc(can_assign: bool) {
	op_type := parser.previous.ttype

	#partial switch op_type {
	case .False:
		emit_code(OpCode.False)
	case .Nil:
		emit_code(OpCode.Nil)
	case .True:
		emit_code(OpCode.True)
	case:
		return
	}
}

parse_precedence :: proc(precedence: Precedence) {
	advance()
	prefix_rule := get_rule(parser.previous.ttype).prefix

	if prefix_rule == nil {
		error_at_current("Expect expression")
		return
	}

	can_assign := precedence <= .Assignment
	prefix_rule(can_assign)

	for precedence <= get_rule(parser.current.ttype).precedence {
		advance()
		infix_rule := get_rule(parser.previous.ttype).infix
		infix_rule(can_assign)
	}

	if can_assign && match(.Equal) {
		error_at_current("Invalid assignment target.")
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
	TokenType.Identifier   = ParseRule{variable, nil, .Comparison},
	TokenType.String       = ParseRule{string_parse, nil, .None},
	TokenType.Number       = ParseRule{number, nil, .None},
	TokenType.And          = ParseRule{nil, and_parse, .And},
	TokenType.Class        = ParseRule{nil, nil, .None},
	TokenType.Else         = ParseRule{nil, nil, .None},
	TokenType.False        = ParseRule{literal, nil, .None},
	TokenType.For          = ParseRule{nil, nil, .None},
	TokenType.Fun          = ParseRule{nil, nil, .None},
	TokenType.If           = ParseRule{nil, nil, .None},
	TokenType.Nil          = ParseRule{literal, nil, .None},
	TokenType.Or           = ParseRule{nil, or_parse, .Or},
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

parse_variable :: proc(error_msg: string) -> u8 {
	consume(.Identifier, error_msg)

	declare_variable()
	if compiler.scope_depth > 0 do return 0

	return identifier_constant(&parser.previous)
}

mark_initialized :: proc() {
	compiler.locals[compiler.local_count - 1].depth = compiler.scope_depth
}

define_variable :: proc(global: u8) {
	if compiler.scope_depth > 0 {
		mark_initialized()
		return
	}
	emit_bytes(u8(OpCode.DefineGlobal), global)
}

declare_variable :: proc() {
	if compiler.scope_depth == 0 do return
	name := &parser.previous

	for i in compiler.local_count - 1 ..= 0 {
		local := &compiler.locals[i]
		if local.depth != nil && local.depth.(u8) < compiler.scope_depth do break
		if identifiers_equal(name, &local.name) {
			error_at_current("Already a variable with this name in this scope.")
		}
	}

	add_local(name^)
}

and_parse :: proc(can_assign: bool) {
	end_jump := emit_jump(OpCode.JumpIfFalse)

	emit_code(OpCode.Pop)
	parse_precedence(.And)

	patch_jump(end_jump)
}

or_parse :: proc(can_assign: bool) {
	else_jump := emit_jump(OpCode.JumpIfFalse)
	end_jump := emit_jump(OpCode.Jump)

	patch_jump(else_jump)
	emit_code(OpCode.Pop)

	parse_precedence(.Or)
	patch_jump(end_jump)
}

identifier_constant :: proc(name: ^Token) -> u8 {
	obj := cast(^Obj)copy_string(name.lexeme)
	val := Value(obj)
	return make_constant(val)
}

identifiers_equal :: proc(a: ^Token, b: ^Token) -> bool {
	return a.lexeme == b.lexeme
}

resolve_local :: proc(compiler: ^Compiler, name: ^Token) -> (u8, bool) {
	for i in compiler.local_count - 1 ..= 0 {
		local := &compiler.locals[i]
		if identifiers_equal(name, &local.name) {
			if (local.depth == nil) {
				error_at_current("Can't read local variable in its own initializer.")
			}
			return i, true
		}
	}

	return 0, false
}

add_local :: proc(name: Token) {
	if compiler.local_count >= 255 {
		error_at_current("Too many local variables in the function.")
		return
	}

	local := &compiler.locals[compiler.local_count]
	compiler.local_count += 1
	local.name = name
	local.depth = nil
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

@(private = "file")
match :: proc(ttype: TokenType) -> bool {
	if !check(ttype) do return false
	advance()
	return true
}

check :: #force_inline proc(ttype: TokenType) -> bool {
	return parser.current.ttype == ttype
}

emit_byte :: proc(byte: u8) {
	write_chunk(current_chunk(), byte, parser.previous.line)
}

emit_code :: proc(opcode: OpCode) {
	write_chunk(current_chunk(), u8(opcode), parser.previous.line)
}

emit_return :: proc() {
	emit_code(OpCode.Return)
}

emit_bytes :: proc(byte1, byte2: u8) {
	emit_byte(byte1)
	emit_byte(byte2)
}

emit_constant :: proc(value: Value) {
	emit_bytes(u8(OpCode.Constant), make_constant(value))
}

emit_loop :: proc(loop_start: int) {
	emit_code(OpCode.Loop)

	offset := len(current_chunk().code) - loop_start + 2
	if offset > 0xffff do error_at_current("Loop body too large")

	emit_byte(u8(offset >> 8) & 0xff)
	emit_byte(u8(offset) & 0xff)
}


emit_jump :: proc(instruction: OpCode) -> uint {
	emit_code(instruction)
	emit_byte(0xff)
	emit_byte(0xff)
	return len(current_chunk().code) - 2
}

patch_jump :: proc(offset: uint) {
	jump := cast(uint)len(current_chunk().code) - offset - 2

	if jump > 0xffff {
		error_at_current("Too much code to jump over.")
	}

	current_chunk().code[offset] = u8((jump >> 8) & 0xff)
	current_chunk().code[offset + 1] = u8(jump & 0xff)
}

make_constant :: proc(value: Value) -> u8 {
	constant := add_constant(current_chunk(), value)

	if constant > max(u8) {
		error_at_current("Too many constants in 1 chunk.")
		return 0
	}

	return constant
}

current_chunk :: #force_inline proc() -> ^Chunk {
	return compiling_chunk
}

error_at :: proc(token: ^Token, msg: string) {
	if parser.panic_mode {return}
	parser.panic_mode = true

	fmt.eprintf("[line %d] Error", token.line)

	if (token.ttype == .Eof) do fmt.eprint(" at end")
	else if (token.ttype != .Error) do fmt.eprintf(" at '%s'", token.lexeme)

	fmt.eprintf(": %s\n", msg)
	parser.had_error = true
}

error_at_previous :: #force_inline proc(msg: string) {
	error_at(&parser.previous, msg)
}

error_at_current :: #force_inline proc(msg: string) {
	error_at(&parser.current, msg)
}
