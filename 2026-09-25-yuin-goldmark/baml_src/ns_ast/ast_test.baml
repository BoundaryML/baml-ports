// Port of goldmark ast/ast_test.go.

class WalkCase {
    name: string,
    node: Node,
    want: NodeKind[],
    action: map<string, WalkStatus>,
}

function walk_test_doc() -> Node {
    n(new_document(), [n(new_heading(1, HeadingKind.HeadingKindATX), [""]), new_link(root.text.empty_single_line_value())])
}

function walk_failures() -> string[] {
    let tests = [
        WalkCase {
            name: "visits all in depth first order",
            node: walk_test_doc(),
            want: [kind_document(), kind_heading(), kind_text(), kind_link()],
            action: {},
        },
        WalkCase {
            name: "stops after heading",
            node: walk_test_doc(),
            want: [kind_document(), kind_heading()],
            action: { "Heading": WalkStatus.WalkStop },
        },
        WalkCase {
            name: "skip children",
            node: walk_test_doc(),
            want: [kind_document(), kind_heading(), kind_link()],
            action: { "Heading": WalkStatus.WalkSkipChildren },
        },
    ];
    let failures: string[] = [];
    for (let tt in tests) {
        let kinds: NodeKind[] = [];
        let collect_kinds = (nd: Node, entering: bool) -> WalkStatus {
            if (entering) {
                kinds.push(nd.kind());
            }
            let status = tt.action.get(nd.kind());
            if (status != null) {
                return status;
            }
            WalkStatus.WalkContinue
        };
        walk(tt.node, collect_kinds);
        if (kinds != tt.want) {
            failures.push(tt.name + ": got " + kinds.join(","));
        }
    }
    failures
}

test "TestWalk" {
    assert.equal(walk_failures(), []);
}
