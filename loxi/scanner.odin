package loxi

import "core:strings"
import "core:unicode"

Scanner :: struct {
	source:  ^[]u8,
	start:   uint,
	current: uint,
	line:    uint,
}

scanner := Scanner{}

init_scanner :: proc(source: ^[]u8) {
	scanner.source = source
	scanner.start = 0
	scanner.current = 0
	scanner.line = 1
}

Token :: struct {
	ttype:  TokenType,
	lexeme: string,
	line:   uint,
}

TokenType :: enum {
	LeftParen,
	RightParen,
	LeftBrace,
	RightBrace,
	LeftBracket,
	RightBracket,
	Comma,
	Dot,
	Minus,
	Plus,
	Semicolon,
	Slash,
	Star,
	Bang,
	BangEqual,
	Equal,
	EqualEqual,
	Greater,
	GreaterEqual,
	Less,
	LessEqual,
	Identifier,
	String,
	Number,
	And,
	Class,
	Else,
	False,
	For,
	Fun,
	If,
	Nil,
	Or,
	Print,
	Return,
	Super,
	This,
	True,
	Var,
	While,
	Error,
	Eof,
}

is_at_end :: proc() -> bool {
	return scanner.current >= len(scanner.source)
}

@(private = "file")
advance :: proc() -> rune {
	ch := scanner.source[scanner.current]
	scanner.current += 1
	return rune(ch)
}

@(private = "file")
peek :: proc() -> rune {
	if is_at_end() {return 0}
	return rune(scanner.source[scanner.current])
}

peek_next :: proc() -> rune {
	if scanner.current + 1 >= len(scanner.source) {return 0}
	return rune(scanner.source[scanner.current + 1])
}

@(private = "file")
match :: proc(expected: rune) -> bool {
	if is_at_end() {return false}
	if rune(scanner.source[scanner.current]) != expected {return false}
	scanner.current += 1
	return true
}

make_token :: proc(ttype: TokenType) -> Token {
	return Token {
		ttype = ttype,
		lexeme = string(scanner.source[scanner.start:scanner.current]),
		line = scanner.line,
	}
}

error_token :: proc(message: string) -> Token {
	return Token{ttype = .Error, lexeme = message, line = scanner.line}
}

skip_whitespace :: proc() {
	for !is_at_end() {
		ch := peek()
		switch ch {
		case ' ', '\r', '\t':
			advance()
		case '\n':
			advance()
			scanner.line += 1
		case '/':
			if peek_next() == '/' do for peek() != '\n' && !is_at_end() do advance()
			else do return
		case:
			return
		}
	}
}

scan_token :: proc() -> Token {
	skip_whitespace()
	scanner.start = scanner.current

	if is_at_end() do return make_token(.Eof)

	ch := advance()

	if unicode.is_letter(ch) do return identifier()
	if unicode.is_digit(ch) do return number()

	switch ch {
	case '(':
		return make_token(.LeftParen)
	case ')':
		return make_token(.RightParen)
	case '{':
		return make_token(.LeftBrace)
	case '}':
		return make_token(.RightBrace)
	case ',':
		return make_token(.Comma)
	case '.':
		return make_token(.Dot)
	case '-':
		return make_token(.Minus)
	case '+':
		return make_token(.Plus)
	case ';':
		return make_token(.Semicolon)
	case '*':
		return make_token(.Star)
	case '/':
		return make_token(.Slash)
	case '[':
		return make_token(.LeftBracket)
	case ']':
		return make_token(.RightBracket)
	case '!':
		if match('=') {return make_token(.BangEqual)} else {return make_token(.Bang)}
	case '=':
		if match('=') {return make_token(.EqualEqual)} else {return make_token(.Equal)}
	case '<':
		if match('=') {return make_token(.LessEqual)} else {return make_token(.Less)}
	case '>':
		if match('=') {return make_token(.GreaterEqual)} else {return make_token(.Greater)}
	case '"':
		return string_scan()
	}

	builder: strings.Builder
	strings.builder_init_len(&builder, 24)
	strings.write_string(&builder, "Unexpected character `")
	strings.write_rune(&builder, ch)
	strings.write_rune(&builder, '`')
	return error_token(strings.to_string(builder))
}

identifier :: proc() -> Token {
	for unicode.is_letter(peek()) || unicode.is_digit(peek()) || peek() == '_' do advance()
	return make_token(identifier_type())
}

identifier_type :: proc() -> TokenType {
	txt := string(scanner.source[scanner.start:scanner.current])
	switch txt {
	case "and":
		return .And
	case "class":
		return .Class
	case "else":
		return .Else
	case "false":
		return .False
	case "for":
		return .For
	case "fun":
		return .Fun
	case "if":
		return .If
	case "nil":
		return .Nil
	case "or":
		return .Or
	case "print":
		return .Print
	case "return":
		return .Return
	case "super":
		return .Super
	case "this":
		return .This
	case "true":
		return .True
	case "var":
		return .Var
	case "while":
		return .While
	}
	return .Identifier
}

@(private = "file")
number :: proc() -> Token {
	for unicode.is_digit(peek()) do advance()

	if peek() == '.' && unicode.is_digit(peek_next()) {
		advance()
		for unicode.is_digit(peek()) do advance()
	}

	return make_token(.Number)
}

string_scan :: proc() -> Token {
	for peek() != '"' && !is_at_end() {
		if peek() == '\n' do scanner.line += 1
		advance()
	}

	if is_at_end() do return error_token("Unterminated string.")

	advance()
	return make_token(.String)
}
