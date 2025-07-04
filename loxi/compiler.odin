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
	enclosing:   ^Compiler,
	function:    ^ObjFunction,
	locals:      [256]Local,
	upvalues:    [256]Upvalue,
	ftype:       FunctionType,
	local_count: u8,
	scope_depth: u8,
}

ClassCompiler :: struct {
	enclosing: ^ClassCompiler,
	has_super: bool,
}

FunctionType :: enum {
	Function,
	Initializer,
	Method,
	Script,
}

Local :: struct {
	name:        string,
	depth:       Maybe(u8),
	is_captured: bool,
}

Upvalue :: struct {
	index:    u8,
	is_local: bool,
}

parser := Parser{}
current: ^Compiler = nil
current_class: ^ClassCompiler = nil

compile :: proc(source: ^[]u8) -> ^ObjFunction {
	init_scanner(source)

	parser = Parser{}

	compiler := Compiler{}
	init_compiler(&compiler, .Script)

	advance()
	for !match(.Eof) do declaration()

	return parser.had_error ? nil : end_compiler()
}

init_compiler :: proc(compiler: ^Compiler, type: FunctionType) {
	compiler.enclosing = current
	compiler.function = new_function()
	compiler.ftype = type
	compiler.local_count = 0
	compiler.scope_depth = 0

	current = compiler

	if type != .Script do when REPL {
		current.function.name = strings.clone(parser.previous.lexeme)
	} else {
		current.function.name = parser.previous.lexeme
	}

	local := &current.locals[current.local_count]
	current.local_count += 1
	local.depth = 0
	local.is_captured = false

	if (type != .Function) {
		local.name = "this"
	} else {
		local.name = ""
	}
}

end_compiler :: proc() -> ^ObjFunction {
	emit_return()
	function := current.function

	when DEBUG_PRINT_CODE do if !parser.had_error {
		fname := len(function.name) == 0 ? "script" : function.name
		disassemble_chunk(current_chunk(), fname)
	}

	current = current.enclosing
	return function
}

begin_scope :: #force_inline proc() {
	current.scope_depth += 1
}

end_scope :: proc() {
	current.scope_depth -= 1

	for current.local_count > 0 &&
	    current.locals[current.local_count - 1].depth.(u8) > current.scope_depth {

		if current.locals[current.local_count - 1].is_captured do emit_code(.CloseUpvalue)
		else do emit_code(.Pop)

		current.local_count -= 1
	}
}

declaration :: proc() {
	if match(.Class) do class_declaration()
	else if match(.Fun) do function_declaration()
	else if match(.Var) do var_declaration()
	else do statement()

	if parser.panic_mode do synchronize()
}

statement :: proc() {
	if match(.Print) {
		print_statement()
	} else if match(.If) {
		if_statement()
	} else if match(.Return) {
		return_statement()
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

expression_statement :: proc() {
	expression()
	consume(.Semicolon, "Expect ; after expression")
	emit_code(OpCode.Pop)
}

print_statement :: proc() {
	expression()
	consume(.Semicolon, "Expect ; after value")
	emit_code(OpCode.Print)
}

return_statement :: proc() {
	if current.ftype == .Script do error_at_previous("Can't return from top-level code.")

	if match(.Semicolon) {
		emit_return()
	} else {
		if current.ftype == .Initializer do error_at_previous("Can't return from an initializer.")

		expression()
		consume(.Semicolon, "Expect ';' after return value.")
		emit_code(.Return)
	}
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
	loop_start: uint = len(current_chunk().code)
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

	if match(.Semicolon) { 	// No initializer
	} else if match(.Var) do var_declaration()
	else do expression_statement()

	loop_start: uint = len(current_chunk().code)

	exit_jump: Maybe(uint) = nil
	if !match(.Semicolon) {
		expression()
		consume(.Semicolon, "Expect ';' after loop condition.")

		exit_jump = emit_jump(OpCode.JumpIfFalse)
		emit_code(.Pop)
	}

	if !match(.RightParen) {
		body_jump := emit_jump(OpCode.Jump)
		increment_start: uint = len(current_chunk().code)
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

function_statement :: proc(ftype: FunctionType) {
	compiler := Compiler{}
	init_compiler(&compiler, ftype)
	begin_scope()

	consume(.LeftParen, "Expect '(' after function name.")

	if !check(.RightParen) {
		for {
			current.function.arity += 1
			if current.function.arity > 255 do error_at_current("Can't have more than 255 parameters")
			constant := parse_variable("Expect parameter name")
			define_variable(constant)

			if !match(.Comma) do break
		}
	}

	consume(.RightParen, "Expect ')' after parameters.")
	consume(.LeftBrace, "Expect '{' before function body.")
	block()

	function := end_compiler()
	emit_bytes(u8(OpCode.Closure), make_constant(cast(^Obj)function))

	for i in 0 ..< function.upvalue_count {
		emit_byte(compiler.upvalues[i].is_local ? 1 : 0)
		emit_byte(compiler.upvalues[i].index)
	}
}

method :: proc() {
	consume(.Identifier, "Expect method name.")
	constant := identifier_constant(parser.previous.lexeme)

	type: FunctionType = parser.previous.lexeme == "init" ? .Initializer : .Method

	function_statement(type)
	emit_bytes(u8(OpCode.Method), constant)
}

var_declaration :: proc() {
	global := parse_variable("Expect variable name.")

	if match(.Equal) do expression()
	else do emit_code(OpCode.Nil)
	consume(.Semicolon, "Expect ';' after variable declaration.")

	define_variable(global)
}


function_declaration :: proc() {
	global := parse_variable("Expect function name.")
	mark_initialized()
	function_statement(.Function)
	define_variable(global)
}

class_declaration :: proc() {
	consume(.Identifier, "Expect class name.")
	class_name := parser.previous.lexeme
	name_constant := identifier_constant(parser.previous.lexeme)
	declare_variable()

	emit_bytes(u8(OpCode.Class), name_constant)
	define_variable(name_constant)

	class_compiler := ClassCompiler {
		enclosing = current_class,
		has_super = false,
	}
	current_class = &class_compiler

	if match(.Less) {
		consume(.Identifier, "Expect superclass name.")
		variable(false)
		if class_name == parser.previous.lexeme {
			error_at_previous("A class can't inherit from itself.")
		}

		begin_scope()
		add_local("super")
		define_variable(0)

		named_variable(class_name, false)
		emit_code(OpCode.Inherit)
		class_compiler.has_super = true
	}

	named_variable(class_name, false)
	consume(.LeftBrace, "Expect '{' before class body.")
	for !check(.RightBrace) && !check(.LeftBrace) do method()
	consume(.RightBrace, "Expect '}' before class body.")
	emit_code(OpCode.Pop)

	if class_compiler.has_super do end_scope()

	current_class = current_class.enclosing
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

named_variable :: proc(name: string, can_assign: bool) {
	get_op: u8 = 0
	set_op: u8 = 0
	arg, is_local := resolve_local(current, name).(u8)

	if is_local {
		get_op = u8(OpCode.GetLocal)
		set_op = u8(OpCode.SetLocal)
	} else if upvalue, is_upval := resolve_upvalue(current, name).(u8); is_upval {
		arg = upvalue
		get_op = u8(OpCode.GetUpvalue)
		set_op = u8(OpCode.SetUpvalue)
	} else {
		arg = identifier_constant(name)
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
	named_variable(parser.previous.lexeme, can_assign)
}

this :: proc(can_assign: bool) {
	if current_class == nil {
		error_at_previous("Can't use 'this' outside of class.")
		return
	}

	variable(false)
}

super :: proc(can_assign: bool) {
	if current_class == nil do error_at_previous("Can't use 'super' outside of a class.")
	else if !current_class.has_super do error_at_previous("Can't use 'super' with no superclass")

	consume(.Dot, "Expect '.' after 'super'.")
	consume(.Identifier, "Expect superclass method name.")
	name := identifier_constant(parser.previous.lexeme)

	named_variable("this", false)
	if match(.LeftParen) {
		arg_count := argument_list()
		named_variable("super", false)
		emit_bytes(u8(OpCode.SuperInvoke), name)
		emit_byte(arg_count)
	} else {
		named_variable("super", false)
		emit_bytes(u8(OpCode.GetSuper), name)
	}
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

@(private = "file")
call :: proc(can_assign: bool) {
	arg_count := argument_list()
	emit_bytes(u8(OpCode.Call), arg_count)
}

dot :: proc(can_assign: bool) {
	consume(.Identifier, "Expect property name after '.'.")
	name := identifier_constant(parser.previous.lexeme)

	if can_assign && match(.Equal) {
		expression()
		emit_bytes(u8(OpCode.SetProperty), name)
	} else if match(.LeftParen) {
		arg_count := argument_list()
		emit_bytes(u8(OpCode.Invoke), name)
		emit_byte(arg_count)
	} else {
		emit_bytes(u8(OpCode.GetProperty), name)
	}

}

argument_list :: proc() -> u8 {
	arg_count: u8 = 0
	if !check(.RightParen) {
		for {
			expression()
			if current.function.arity > 255 do error_at_current("Can't have more than 255 parameters")

			arg_count += 1
			if !match(.Comma) do break
		}
	}
	consume(.RightParen, "Expect ')' after arguments.")
	return arg_count
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
	TokenType.LeftParen    = ParseRule{grouping, call, .Call},
	TokenType.RightParen   = ParseRule{nil, nil, .None},
	TokenType.LeftBrace    = ParseRule{nil, nil, .None},
	TokenType.RightBrace   = ParseRule{nil, nil, .None},
	TokenType.Comma        = ParseRule{nil, nil, .None},
	TokenType.Dot          = ParseRule{nil, dot, .Call},
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
	TokenType.Identifier   = ParseRule{variable, nil, .None},
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
	TokenType.Super        = ParseRule{super, nil, .None},
	TokenType.This         = ParseRule{this, nil, .None},
	TokenType.True         = ParseRule{literal, nil, .None},
	TokenType.Var          = ParseRule{nil, nil, .None},
	TokenType.While        = ParseRule{nil, nil, .None},
	TokenType.Error        = ParseRule{nil, nil, .None},
	TokenType.Eof          = ParseRule{nil, nil, .None},
}

parse_variable :: proc(error_msg: string) -> u8 {
	consume(.Identifier, error_msg)

	declare_variable()
	if current.scope_depth > 0 do return 0

	return identifier_constant(parser.previous.lexeme)
}

mark_initialized :: proc() {
	if current.scope_depth == 0 do return
	current.locals[current.local_count - 1].depth = current.scope_depth
}

define_variable :: proc(global: u8) {
	if current.scope_depth != 0 {
		mark_initialized()
		return
	}
	emit_bytes(u8(OpCode.DefineGlobal), global)
}

declare_variable :: proc() {
	if current.scope_depth == 0 do return
	name := parser.previous.lexeme

	for i in current.local_count - 1 ..= 0 {
		local := &current.locals[i]
		if local.depth != nil && local.depth.(u8) < current.scope_depth do break
		if name == local.name do error_at_previous("Already a variable with this name in this scope.")
	}

	add_local(name)
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

identifier_constant :: proc(name: string) -> u8 {
	obj := cast(^Obj)copy_string(name)
	return make_constant(obj)
}

resolve_local :: proc(compiler: ^Compiler, name: string) -> Maybe(u8) {
	for i := compiler.local_count - 1;; i -= 1 {
		local := &compiler.locals[i]
		if name == local.name {
			if local.depth == nil do error_at_previous("Can't read local variable in its own initializer.")
			return i
		}

		if i == 0 do break
	}

	return nil
}

resolve_upvalue :: proc(compiler: ^Compiler, name: string) -> Maybe(u8) {
	if compiler.enclosing == nil do return nil
	if local, ok := resolve_local(compiler.enclosing, name).(u8); ok {
		compiler.enclosing.locals[local].is_captured = true
		return add_upvalue(compiler, local, true)
	}
	if upvalue, ok := resolve_upvalue(compiler.enclosing, name).(u8); ok {
		return add_upvalue(compiler, upvalue, false)
	}
	return nil
}

add_local :: proc(name: string) {
	if current.local_count == 255 {
		error_at_previous("Too many local variables in the function.")
		return
	}

	local := &current.locals[current.local_count]
	current.local_count += 1
	local.name = name // NOTE: Clone for repl?
	local.depth = nil
	local.is_captured = false
}

add_upvalue :: proc(compiler: ^Compiler, index: u8, is_local: bool) -> u8 {
	upvalue_count := compiler.function.upvalue_count

	for i in 0 ..< upvalue_count {
		upvalue := &compiler.upvalues[i]
		if upvalue.index == index && upvalue.is_local == is_local do return i
	}

	if upvalue_count == 255 {
		error_at_previous("Too many closure variables in function")
		return 0
	}

	compiler.upvalues[upvalue_count].is_local = is_local
	compiler.upvalues[upvalue_count].index = index
	retval := compiler.function.upvalue_count
	compiler.function.upvalue_count += 1
	return upvalue_count // WARN: Book returns `compiler->function->upvalueCount++`
}

@(private = "file")
advance :: proc() {
	parser.previous = parser.current

	for {
		parser.current = scan_token()
		if (parser.current.ttype != .Error) do break
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
	emit_byte(u8(opcode))
}

emit_return :: proc() {
	if current.ftype == .Initializer do emit_bytes(u8(OpCode.GetLocal), 0)
	else do emit_code(OpCode.Nil)

	emit_code(OpCode.Return)
}

emit_bytes :: proc(byte1, byte2: u8) {
	emit_byte(byte1)
	emit_byte(byte2)
}

emit_constant :: proc(value: Value) {
	emit_bytes(u8(OpCode.Constant), make_constant(value))
}

emit_loop :: proc(loop_start: uint) {
	emit_code(OpCode.Loop)

	offset: uint = len(current_chunk().code) - loop_start + 2
	if offset > 0xffff do error_at_previous("Loop body too large")

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
	jump: uint = len(current_chunk().code) - offset - 2

	if jump > 0xffff do error_at_previous("Too much code to jump over.")

	current_chunk().code[offset] = u8(jump >> 8) & 0xff
	current_chunk().code[offset + 1] = u8(jump & 0xff)
}

make_constant :: proc(value: Value) -> u8 {
	constant := add_constant(current_chunk(), value)

	if constant > 255 {
		error_at_previous("Too many constants in 1 chunk.")
		return 0
	}

	return u8(constant)
}

current_chunk :: proc() -> ^Chunk {
	return &current.function.chunk
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
