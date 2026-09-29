// Port of tests/line-counter.ts

testset "line-counter" {
  test "Parse error, no newlines" {
    let lineCounter = new_line_counter();
    let doc = parseDocument("foo: bar: baz", Options { lineCounter: lineCounter });
    expect_toMatchObject(doc.errors, [{ "pos": [5, 6] }]);
    expect_toMatchObject(lineCounter.lineStarts, [0]);
    expect_toMatchObject(lineCounter.linePos(5), { "line": 1, "col": 6 })
  }

  test "Parse error with newlines" {
    let lineCounter = new_line_counter();
    let doc = parseDocument("foo:\n  bar: - baz\n", Options { lineCounter: lineCounter });
    expect_toMatchObject(doc.errors, [{ "pos": [12, 13] }, { "pos": [14, 17] }]);
    expect_toMatchObject(lineCounter.lineStarts, [0, 5, 18]);
    expect_toMatchObject(lineCounter.linePos(14), { "line": 2, "col": 10 });
    expect_toMatchObject(lineCounter.linePos(17), { "line": 2, "col": 13 })
  }

  test "block scalar" {
    let lineCounter = new_line_counter();
    parseDocument("foo: |\n a\n b\n c\nbar:\n baz\n", Options { lineCounter: lineCounter });
    expect_toMatchObject(lineCounter.lineStarts, [0, 7, 10, 13, 16, 21, 26]);
    for (let c in [[0, 1, 1], [10, 3, 1], [11, 3, 2], [12, 3, 3], [13, 4, 1], [14, 4, 2], [15, 4, 3], [16, 5, 1], [17, 5, 2], [18, 5, 3]]) {
      expect_toMatchObject(lineCounter.linePos(c[0]), { "line": c[1], "col": c[2] });
    }
  }

  test "flow scalar" {
    let lineCounter = new_line_counter();
    let doc = parseDocument("?\n \"a\n b\"\n: '\n c\n \n\n d'\n", Options { lineCounter: lineCounter });
    expect_toMatchObject(doc.toJS(null), { "a b": " c\n\nd" });
    expect_toMatchObject(lineCounter.lineStarts, [0, 2, 6, 10, 14, 17, 19, 20, 24])
  }
}
