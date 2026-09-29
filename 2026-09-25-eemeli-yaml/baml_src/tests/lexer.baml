// Port of tests/lexer.ts

testset "lexer" {
  test "unexpected unindent in quoted string with CRLF" {
    let src_ = "- \"\r\nx\"";
    expect_toEqual(lex(src_), [DOCUMENT(), "-", " ", "\"", "\r\n", SCALAR(), "x\""])
  }

  test "plain scalar + CRLF + comment" {
    let src_ = "foo\r\n# bar";
    expect_toEqual(lex(src_), [DOCUMENT(), SCALAR(), "foo", "\r\n", "# bar"])
  }

  test "Scalar starting with : after flow-ish key in preceding node in flow collection" {
    let src_ = "[[], :@]";
    expect_toEqual(lex(src_), [DOCUMENT(), "[", "[", "]", ",", " ", SCALAR(), ":@", "]"])
  }

  test "unindented comment in flow collection" {
    let src_ = "- {\n#c\n  }";
    expect_toEqual(lex(src_), [DOCUMENT(), "-", " ", "{", "\n", "#c", "\n", "  ", "}"])
  }

  test "indented map + ... + unindented flow collection" {
    let src_ = " :\n...\n{\n}";
    expect_toEqual(lex(src_), [DOCUMENT(), " ", ":", "\n", "...", "\n", DOCUMENT(), "{", "\n", "}"])
  }

  test "multiple empty --- separated documents" {
    let src_ = "---\n---\n---\n---";
    expect_toEqual(lex(src_), [DOCUMENT(), "---", "\n", "---", "\n", "---", "\n", "---"])
  }

  test "multiple empty ... separated documents" {
    let src_ = "...\n...\n...\n...";
    expect_toEqual(lex(src_), [DOCUMENT(), "...", "\n", DOCUMENT(), "...", "\n", DOCUMENT(), "...", "\n", DOCUMENT(), "..."])
  }

  test "trailing comments on ..." {
    let src_ = "... # c\n# d\n... \n";
    expect_toEqual(lex(src_), [DOCUMENT(), "...", " ", "# c", "\n", "# d", "\n", DOCUMENT(), "...", " ", "\n"])
  }
}
