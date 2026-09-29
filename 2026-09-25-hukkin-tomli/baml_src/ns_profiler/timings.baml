// Port addition (no counterpart in the original): micro-timings of the hot
// helpers, used to find where the BAML port spends its time.
// Run: `baml run -e 'root.profiler.timings()'` from the project root.

function time_it(label: string, n: int, f: () -> void) -> string {
    let start = baml.time.Instant.now();
    for (let i = 0; i < n; i += 1) {
        f();
    }
    label + ": " + (start.elapsed().to_microseconds() / n).to_string() + "us"
}

function timings() -> string[] {
    let data = baml.fs.read("benchmark/data.toml");
    [
        time_it("loads(data.toml)", 3, () -> void {
            root.tomli.loads(data);
        }),
        time_it("baml.toml parse", 3, () -> void {
            let _ = baml.toml.Table.parse(data);
        }),
        time_it("KEY_INITIAL_CHARS()", 100, () -> void {
            let _ = root.tomli.KEY_INITIAL_CHARS();
        }),
        time_it("ASCII_CTRL()", 100, () -> void {
            let _ = root.tomli.ASCII_CTRL();
        }),
        time_it("TOML_WS()", 100, () -> void {
            let _ = root.tomli.TOML_WS();
        }),
        time_it("regex.new(RE_DATETIME)", 100, () -> void {
            let _ = baml.regex.new(root.tomli.RE_DATETIME());
        }),
        time_it("re_match_at(RE_NUMBER)", 100, () -> void {
            let _ = root.tomli.re_match_at(root.tomli.RE_NUMBER(), "a = 123\n", 4);
        }),
        time_it("src.at(i) 4KB", 1000, () -> void {
            let _ = data.at(2000);
        }),
        time_it("src.slice(i, len) 4KB", 1000, () -> void {
            let _ = data.slice(2000, data.length());
        }),
    ]
}

function doc_timings() -> string[] {
    let strs = "";
    let nums = "";
    let dts = "";
    let bools = "";
    for (let i = 0; i < 100; i += 1) {
        strs = strs + "k" + i.to_string() + " = \"value\"\n";
        nums = nums + "k" + i.to_string() + " = 12345\n";
        dts = dts + "k" + i.to_string() + " = 1979-05-27\n";
        bools = bools + "k" + i.to_string() + " = true\n";
    }
    [
        time_it("100 string values", 5, () -> void {
            root.tomli.loads(strs);
        }),
        time_it("100 bool values", 5, () -> void {
            root.tomli.loads(bools);
        }),
        time_it("100 int values", 5, () -> void {
            root.tomli.loads(nums);
        }),
        time_it("100 date values", 5, () -> void {
            root.tomli.loads(dts);
        }),
    ]
}

function scaling() -> string[] {
    let out: string[] = [];
    for (let n in [50, 100, 200, 400]) {
        let bools = "";
        for (let i = 0; i < n; i += 1) {
            bools = bools + "k" + i.to_string() + " = true\n";
        }
        out.push(
            time_it(n.to_string() + " bool lines", 3, () -> void {
                root.tomli.loads(bools);
            }),
        );
    }
    let line = "k = true\n";
    out.push(
        time_it("key_value_rule-ish: skip_chars", 1000, () -> void {
            let _ = root.tomli.skip_chars(line, 1, root.tomli.TOML_WS());
        }),
    );
    out.push(
        time_it("KEY_INITIAL_CHARS().contains", 1000, () -> void {
            let _ = root.tomli.KEY_INITIAL_CHARS().contains("k");
        }),
    );
    out.push(
        time_it("parse_key", 1000, () -> void {
            let _ = root.tomli.parse_key(line, 0);
        }),
    );
    out.push(
        time_it("Output.new", 1000, () -> void {
            let _ = root.tomli.Output.new();
        }),
    );
    out.push(
        time_it("make_safe_parse_float", 1000, () -> void {
            let _ = root.tomli.make_safe_parse_float(null);
        }),
    );
    out.push(
        time_it("loads(one line)", 100, () -> void {
            let _ = root.tomli.loads(line);
        }),
    );
    out.push(
        time_it("TOMLDecodeError.new", 100, () -> void {
            let _ = root.tomli.TOMLDecodeError.new("x", line, 3);
        }),
    );
    out
}

function drill() -> string[] {
    let line = "k = true\n";
    let pf = root.tomli.make_safe_parse_float(null);
    let out: string[] = [];
    out.push(
        time_it("parse_value(true)", 1000, () -> void {
            let _ = root.tomli.parse_value(line, 4, pf, 0);
        }),
    );
    out.push(
        time_it("parse_key_value_pair", 1000, () -> void {
            let _ = root.tomli.parse_key_value_pair(line, 0, pf, 0);
        }),
    );
    out.push(
        time_it("key_value_rule", 100, () -> void {
            let o = root.tomli.Output.new();
            let _ = root.tomli.key_value_rule(line, 0, o, [], pf);
        }),
    );
    out.push(
        time_it("skip_comment", 1000, () -> void {
            let _ = root.tomli.skip_comment(line, 8);
        }),
    );
    out.push(
        time_it("replace_all", 1000, () -> void {
            let _ = line.replace_all("\r\n", "\n");
        }),
    );
    out.push(
        time_it("MAX_INLINE_NESTING", 1000, () -> void {
            let _ = root.tomli.MAX_INLINE_NESTING();
        }),
    );
    out
}

function drill2() -> string[] {
    let out: string[] = [];
    let v: root.tomli.Value = true;
    let m: map<string, root.tomli.Value> = {};
    let o = root.tomli.Output.new();
    out.push(
        time_it("is_dict_or_list(true)", 100, () -> void {
            let _ = root.tomli.is_dict_or_list(v);
        }),
    );
    out.push(
        time_it("is_dict_or_list(map)", 100, () -> void {
            let _ = root.tomli.is_dict_or_list(m);
        }),
    );
    out.push(
        time_it("flags.is_([])", 100, () -> void {
            let _ = o.flags.is_([], root.tomli.Flag.FROZEN);
        }),
    );
    out.push(
        time_it("get_or_create_nest([])", 100, () -> void {
            let _ = o.data.get_or_create_nest([]);
        }),
    );
    out.push(
        time_it("v is bool", 100, () -> void {
            let _ = v is bool;
        }),
    );
    out.push(
        time_it("v is string[]", 100, () -> void {
            let _ = v is string[];
        }),
    );
    out
}

function drill3() -> string[] {
    let line = "k = \"value\"\n";
    let pf = root.tomli.make_safe_parse_float(null);
    let out: string[] = [];
    out.push(
        time_it("parse_value(str)", 200, () -> void {
            let _ = root.tomli.parse_value(line, 4, pf, 0);
        }),
    );
    out.push(
        time_it("parse_one_line_basic_str", 200, () -> void {
            let _ = root.tomli.parse_one_line_basic_str(line, 4);
        }),
    );
    out.push(
        time_it("ILLEGAL_BASIC_STR_CHARS", 200, () -> void {
            let _ = root.tomli.ILLEGAL_BASIC_STR_CHARS();
        }),
    );
    out.push(
        time_it("_widen", 200, () -> void {
            let _ = root.tomli._widen(root.tomli.Tuple2 { first: 1, second: "s" });
        }),
    );
    out.push(
        time_it("key_value_rule(str)", 200, () -> void {
            let o = root.tomli.Output.new();
            let _ = root.tomli.key_value_rule(line, 0, o, [], pf);
        }),
    );
    out
}

function drill4() -> string[] {
    let a = root.tomli.ASCII_CTRL();
    let t = root.tomli.CharSet.from_string("\t");
    let s = a._chars;
    let out: string[] = [];
    out.push(
        time_it("a.minus(t)", 200, () -> void {
            let _ = a.minus(t);
        }),
    );
    out.push(
        time_it("s.chars()", 200, () -> void {
            let _ = s.chars();
        }),
    );
    out.push(
        time_it("filter includes", 200, () -> void {
            let _ = s.chars().filter((c) -> {
                !"\t".includes(c)
            });
        }),
    );
    out.push(
        time_it("join", 200, () -> void {
            let _ = s.chars().join("");
        }),
    );
    out.push(
        time_it("includes ctrl char", 200, () -> void {
            let _ = s.includes("a");
        }),
    );
    out
}
