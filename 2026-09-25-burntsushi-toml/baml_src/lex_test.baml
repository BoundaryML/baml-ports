// Port of lex_test.go.

class PositionStringCase {
    in_: Position,
    want: string,
}

testset "TestPositionString" {
    let tests = [
        PositionStringCase { in_: Position { line: 0, col: 0, start: 0, len: 0 }, want: "at line 0; start 0; length 0" },
        PositionStringCase { in_: Position { line: 1, col: 1, len: 1, start: 1 }, want: "at line 1; start 1; length 1" },
    ];

    let i = 0;
    for (let tt in tests) {
        // Go uses t.Run("", ...), which Go numbers #00, #01, ...
        test `#0${i}` {
            let have = tt.in_.to_string();
            assert.equal(have, tt.want)
        }
        i += 1;
    }
}

test "TestItemTypeString" {
    for (let it in [
        ItemType.Error, ItemType.EOF, ItemType.Text,
        ItemType.String, ItemType.StringEsc, ItemType.RawString, ItemType.MultilineString,
        ItemType.RawMultilineString, ItemType.Bool, ItemType.Integer, ItemType.Float, ItemType.Datetime,
        ItemType.Array, ItemType.ArrayEnd, ItemType.TableStart, ItemType.TableEnd, ItemType.ArrayTableStart,
        ItemType.ArrayTableEnd, ItemType.KeyStart, ItemType.KeyEnd, ItemType.CommentStart,
        ItemType.InlineTableStart, ItemType.InlineTableEnd,
    ]) {
        let have = item_type_string(it);
        if (have == "") {
            throw "empty String for itemType";
        }
    }
}

test "TestItemString" {
    let it = Item { typ: ItemType.String, val: "xxx", pos: Position { line: 42, col: 3, start: 0, len: 0 }, err: null };
    let have = it.to_string();
    let want = "(String, xxx)";
    assert.equal(have, want)
}

test "TestStateFnString" {
    {
        let fn_ = StateFn.LexString;
        assert.equal(state_fn_string(fn_), "lexString()");
    }
    {
        let fn_ = StateFn.Nil;
        assert.equal(state_fn_string(fn_), "<nil>");
    }
}
