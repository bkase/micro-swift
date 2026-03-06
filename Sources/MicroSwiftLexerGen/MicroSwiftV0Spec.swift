/// The checked-in Micro-Swift v0 lexer specification.
public let microSwiftV0 = LexerSpec(name: "MicroSwift.v0") {
  skip("ws", oneOrMore(.byteClass(.asciiWhitespace)))
  skip("lineComment", literal("//") <> zeroOrMore(not(.newline)))

  let ident = identifier(
    "ident",
    .byteClass(.asciiIdentStart) <> zeroOrMore(.byteClass(.asciiIdentContinue))
  )

  keywords(for: ident) {
    keyword("func", as: "kwFunc")
    keyword("let", as: "kwLet")
    keyword("return", as: "kwReturn")
    keyword("if", as: "kwIf")
    keyword("else", as: "kwElse")
    keyword("true", as: "kwTrue")
    keyword("false", as: "kwFalse")
  }

  token("int", oneOrMore(.byteClass(.asciiDigit)))

  token("arrow", literal("->"))
  token("eqEq", literal("=="))
  token("eq", literal("="))
  token("plus", literal("+"))
  token("minus", literal("-"))
  token("star", literal("*"))
  token("slash", literal("/"))
  token("lParen", literal("("))
  token("rParen", literal(")"))
  token("lBrace", literal("{"))
  token("rBrace", literal("}"))
  token("colon", literal(":"))
  token("comma", literal(","))

}
