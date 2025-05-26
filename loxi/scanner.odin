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

peek :: proc() -> rune {
	if is_at_end() {return 0}
	return rune(scanner.source[scanner.current])
}

peek_next :: proc() -> rune {
	if scanner.current + 1 >= len(scanner.source) {return 0}
	return rune(scanner.source[scanner.current + 1])
}

match :: proc(expected: rune) -> bool {
	if is_at_end() {return false}
	if rune(scanner.source[scanner.current]) != expected {return false}
	scanner.current += 1
	return true
}

make_token :: proc(ttype: TokenType) -> Token {
	return Token{ttype = ttype, lexeme = string(scanner.source[scanner.start:scanner.current]), line = scanner.line}
}

error_token :: proc(message: string) -> Token {
	return Token{ttype = .Error, lexeme = message, line = scanner.line}
}

skip_whitespace :: proc() {
	for !is_at_end() {
		ch := peek()
		switch ch {
		case ' ', '\r', '\t':
			_ = advance()
		case '\n':
			_ = advance()
			scanner.line += 1
		case '/':
			if peek_next() == '/' {
				for peek() != '\n' && !is_at_end() {
					_ = advance()
				}
			} else {return}
		case:
			return
		}
	}
}

scan_token :: proc() -> Token {
	skip_whitespace()
	scanner.start = scanner.current

	if is_at_end() {return make_token(.Eof)}

	ch := advance()

	if unicode.is_letter(ch) {return identifier()}
	if unicode.is_digit(ch) {return number()}

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
	case '!':
		if match('=') {return make_token(.BangEqual)} else {return make_token(.Bang)}
	case '=':
		if match('=') {return make_token(.EqualEqual)} else {return make_token(.Equal)}
	case '<':
		if match('=') {return make_token(.LessEqual)} else {return make_token(.Less)}
	case '>':
		if match('=') {return make_token(.GreaterEqual)} else {return make_token(.Greater)}
	case '"':
		return string_literal()
	}
	return error_token("Unexpected character.")
}

identifier :: proc() -> Token {
	for unicode.is_letter(peek()) || unicode.is_digit(peek()) {
		_ = advance()
	}
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
	for unicode.is_digit(peek()) {_ = advance()}

	if peek() == '.' && unicode.is_digit(peek_next()) {
		_ = advance()
		for unicode.is_digit(peek()) {_ = advance()}
	}

	return make_token(.Number)
}

string_literal :: proc() -> Token {
	for peek() != '"' && !is_at_end() {
		if peek() == '\n' {scanner.line += 1}
		_ = advance()
	}

	if is_at_end() {return error_token("Unterminated string.")}

	_ = advance()
	return make_token(.String)
}
