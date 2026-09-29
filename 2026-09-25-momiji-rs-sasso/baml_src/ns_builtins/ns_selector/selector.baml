// Ported from sasso `src/builtins/selector.rs` (namespace `root.builtins.selector`).
//
// The `sass:selector` built-in functions, global spellings.
//
// `selector-nest`, `selector-append`, `selector-extend`, `selector-replace`,
// `selector-unify`, `is-superselector`, `simple-selectors`, and
// `selector-parse`. Each accepts and returns *selector values*: a selector
// list is a comma-separated Sass list of complex selectors, and each complex
// selector is a space-separated Sass list whose items are compound-selector
// strings interleaved with combinator strings (`>`/`+`/`~`), all unquoted
// (dart-sass `ComplexSelector.asSassList`).
//
// The heavy lifting (parsing, superselector tests, compound/complex
// unification, parent weaving, and the extend engine) lives in
// [`crate::selector`]; this module only marshals Sass values to/from selector
// strings, resolves `&` parent references for `nest`/`append`, validates
// arguments, and serializes results.

// `Compound` is referenced via the fully-qualified `crate::selector::Compound`
// path in `compound_target`'s signature.

/// The names the selector family owns by name (the single source of truth,
/// mirroring the `try_call` match arms below).
function NAMES() -> string[] {
    [
        "selector-nest",
        "selector-append",
        "selector-extend",
        "selector-replace",
        "selector-unify",
        "is-superselector",
        "simple-selectors",
        "selector-parse",
    ]
}

function try_call(
    name: string,
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> (root.std.Ok<root.value.Value> | root.std.Err<root.error.Error>)? {
    // PORT: `Some(match name { … })` — the arm's `Result` is captured as an
    // `Ok`/`Err` value; an unknown name returns `None` before any call.
    let r: root.value.Value = {
        match (name) {
            "selector-nest" => fn_nest(pos_args, named, pos),
            "selector-append" => fn_append(pos_args, named, pos),
            "selector-extend" => fn_extend(pos_args, named, pos),
            "selector-replace" => fn_replace(pos_args, named, pos),
            "selector-unify" => fn_unify(pos_args, named, pos),
            "is-superselector" => fn_is_superselector(pos_args, named, pos),
            "simple-selectors" => fn_simple_selectors(pos_args, named, pos),
            "selector-parse" => fn_parse(pos_args, named, pos),
            _ => {
                return null;
            },
        }
    } catch (e) {
        let err: root.error.Error => {
            return root.std.Err { error: err };
        }
    };
    root.std.Ok { value: r }
}

// ---- arity validation -------------------------------------------------
/// Reject more positional arguments than `max` (dart-sass "Only N argument(s)
/// allowed, but M were passed."). Used by the fixed-arity selector functions;
/// `selector-nest` and `selector-append` are variadic and skip this.
function check_arity(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    max: int,
    pos: root.scanner.Pos,
) -> void {
    root.builtins.check_arity(max, pos_args, named, pos)
}

// ---- value <-> selector-string marshalling ----------------------------
/// Convert a Sass value into its selector-string form (dart-sass
/// `_selectorString`). The structure is restricted to at most two list levels:
/// a string; a space list of strings; or a comma list whose items are each a
/// string or a space list of strings. A slash list, a deeper nesting, or any
/// non-string/list value is rejected — matching dart-sass exactly (a comma
/// inside a space list, or a list inside a space list, is *not* valid).
function value_to_selector_string(
    v: root.value.Value,
    pname: string,
    pos: root.scanner.Pos,
) -> string {
    let rendered = value_to_selector_string__render(v);
    if (rendered == null) {
        throw root.error.Error.at("$" + pname + ": " + v.to_css(true) + " is not a valid selector: it must be a string,\na list of strings, or a list of lists of strings.", pos);
    }
    rendered
}

/// A space list of strings → ` `-joined; a lone string → its text. Returns
/// `None` for anything else (a comma/slash list, or a nested list).
function value_to_selector_string__space_or_string(v: root.value.Value) -> string? {
    match (v) {
        root.value.Value_Str { _0: let s } => s.text,
        root.value.Value_List { _0: let l }
            if l.sep == root.value.ListSep.Space && l.items.length() != 0 => {
            let parts: string[] = [];
            for (let item in l.items) {
                match (item) {
                    root.value.Value_Str { _0: let s } => parts.push(s.text),
                    _ => {
                        return null;
                    },
                }
            }
            root.std.join(parts, " ")
        },
        _ => null,
    }
}

function value_to_selector_string__render(v: root.value.Value) -> string? {
    match (v) {
        root.value.Value_Str { _0: let s } => s.text,
        root.value.Value_List { _0: let l } if l.items.length() == 0 => null,
        root.value.Value_List { _0: let l } => match (l.sep) {
            root.value.ListSep.Comma => {
                let parts: string[] = [];
                for (let item in l.items) {
                    let part = value_to_selector_string__space_or_string(item);
                    if (part == null) {
                        return null;
                    }
                    parts.push(part);
                }
                root.std.join(parts, ", ")
            },
            // An undecided list here is single-element, so treat it like a
            // space-separated one.
            root.value.ListSep.Space | root.value.ListSep.Undecided => {
                value_to_selector_string__space_or_string(v)
            },
            // A slash-separated list is not a valid selector.
            root.value.ListSep.Slash => null,
        },
        _ => null,
    }
}

/// Read the selector argument at `i` as a parsed selector list, erroring like
/// dart-sass on a non-selector value, empty selector, or parse failure.
function selector_list_arg(
    params: string[],
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    i: int,
    pos: root.scanner.Pos,
) -> root.selector.Complex[] {
    let v = root.builtins.require(params, pos_args, named, i, pos);
    let pname = params.at(i) ?? "selector";
    let text = value_to_selector_string(v, pname, pos);
    parse_selector_text(text, pname, pos)
}

/// Parse a selector string into a list of complex selectors, erroring with
/// dart-sass's `${pname}: expected selector.` on empty/unparseable input.
function parse_selector_text(
    text: string,
    pname: string,
    pos: root.scanner.Pos,
) -> root.selector.Complex[] {
    if (root.std.trim(text) == "") {
        throw root.error.Error.at("$" + pname + ": expected selector.", pos);
    }
    // Normalize like the main pipeline first: dart splits adjacent compounds
    // (`[c]d` parses as the descendant `[c] d`).
    let normalized = root.eval.normalize_selector(text);
    let parsed = root.selector.parse.parse_list(normalized);
    if (parsed == null) {
        throw root.error.Error.at("$" + pname + ": expected selector.", pos);
    }
    parsed
}

// ---- serialization back to a selector value ---------------------------
/// Serialize a list of complex selectors into a selector *value*: a comma list
/// of space lists (each a complex selector's compound/combinator parts), all
/// unquoted strings. A single complex selector still produces the comma list
/// wrapper (length 1), matching dart-sass.
function selectors_to_value(complexes: root.selector.Complex[]) -> root.value.Value {
    let items: root.value.Value[] = complexes.map((c: root.selector.Complex) -> root.value.Value {
        complex_to_value(c)
    });
    root.value.Value_List {
        _0: root.value.List {
            items: items,
            sep: root.value.ListSep.Comma,
            bracketed: false,
            keywords: null,
        },
    }
}

/// Serialize one complex selector as a space list of its parts (compounds and
/// combinators) as unquoted strings.
function complex_to_value(c: root.selector.Complex) -> root.value.Value {
    let parts = root.selector.complex_to_list_parts(c);
    let items: root.value.Value[] = parts.map((text: string) -> root.value.Value {
        root.value.Value_Str { _0: root.value.SassStr { text: text, quoted: false } }
    });
    // A single-component complex selector is still a (one-element) space list.
    root.value.Value_List {
        _0: root.value.List {
            items: items,
            sep: root.value.ListSep.Space,
            bracketed: false,
            keywords: null,
        },
    }
}

// ---- `&` parent resolution (for nest / append) ------------------------
/// Resolve the child selector string `child` against the parent selector list
/// `parents`, returning the resolved selector list (dart-sass
/// `SelectorList.resolveParentSelectors` over each parent). A child complex that
/// contains a top-level `&` substitutes the parent in place (parent-major
/// order); one without `&` is nested as a descendant of each parent.
function resolve_parents_str(
    child: string,
    parents: string[],
    fname: string,
    pos: root.scanner.Pos,
) -> string[] {
    let parent_str = root.std.join(parents, ", ");
    let parent_strs: string[] = root.std.clone_vec(parents);
    let child_complexes = split_top_commas(child);
    // dart-sass parses each nested selector with parent references allowed, so a
    // `&` that is not at the start of a compound selector is rejected up front.
    for (let cc in child_complexes) {
        validate_parent_placement(cc);
    }
    // Per-child expansions: a top-level `&` expands as a cartesian product
    // over the parent complexes (each occurrence picks independently, the
    // last varying fastest); a `&` inside a selector pseudo receives the
    // WHOLE parent list (`:is(&)` -> `:is(c, d)`); a child without `&` nests
    // under every parent. The groups are then flattened column-major
    // (dart-sass `flattenVertically`).
    let groups: string[][] = [];
    for (let cc in child_complexes) {
        if (has_parent_ref(cc)) {
            groups.push(expand_parent_refs(cc, parent_strs, parent_str));
        } else {
            groups.push(
                parent_strs.map((p: string) -> string {
                    `${p} ${root.std.trim(cc)}`
                }),
            );
        }
    }
    let out: string[] = [];
    for (let resolved in flatten_vertically(groups)) {
        // Validate by parsing — except when the result still carries a
        // literal `&` (a parent that was itself `&`), which stays raw.
        if (has_parent_ref(resolved)) {
            out.push(resolved);
            continue;
        }
        let parsed = root.selector.parse.parse_list(resolved);
        if (parsed == null) {
            throw root.error.Error.at(`Invalid selector produced by ${fname}(): ${resolved}`, pos);
        }
        root.std.extend(
            out,
            parsed.map((c: root.selector.Complex) -> string {
                c.render()
            }),
        );
    }
    if (out.length() == 0) {
        // No `&` and no parents shouldn't happen (parents is non-empty), but
        // guard against an empty result.
        return parse_selector_text(parent_str, "selectors", pos).map((c: root.selector.Complex) -> string {
            c.render()
        });
    }
    out
}

/// Serialize complex-selector strings into a selector value: a comma list of
/// space lists (each string split on top-level whitespace), all unquoted.
/// Handles strings a parsed [`Complex`] can't represent (a literal `&`).
function selector_strings_to_value(complexes: string[]) -> root.value.Value {
    let items: root.value.Value[] = complexes.map((c: string) -> root.value.Value {
        let parts = split_top_ws(c);
        root.value.Value_List {
            _0: root.value.List {
                items: parts.map((text: string) -> root.value.Value {
                    root.value.Value_Str { _0: root.value.SassStr { text: text, quoted: false } }
                }),
                sep: root.value.ListSep.Space,
                bracketed: false,
                keywords: null,
            },
        }
    });
    root.value.Value_List {
        _0: root.value.List {
            items: items,
            sep: root.value.ListSep.Comma,
            bracketed: false,
            keywords: null,
        },
    }
}

/// Split a complex-selector string on top-level whitespace (outside quotes,
/// parens, and brackets).
function split_top_ws(s: string) -> string[] {
    let out: string[] = [];
    let cur = root.std.StrBuf.new();
    let depth = 0;
    // PORT: `s.chars().peekable()` → an index cursor over the chars.
    let chars = s.chars();
    let i = 0;
    while (i < chars.length()) {
        let c = chars[i];
        i += 1;
        match (c) {
            "\\" => {
                cur.push(c);
                if (i < chars.length()) {
                    let n = chars[i];
                    i += 1;
                    cur.push(n);
                }
            },
            "\"" | "'" => {
                cur.push(c);
                let q = c;
                while (i < chars.length()) {
                    let n = chars[i];
                    i += 1;
                    cur.push(n);
                    if (n == q) {
                        break;
                    }
                }
            },
            "(" | "[" => {
                depth += 1;
                cur.push(c);
            },
            ")" | "]" => {
                depth -= 1;
                cur.push(c);
            },
            let c if root.std.is_whitespace(c) && depth == 0 => {
                if (!cur.is_empty()) {
                    out.push(cur.take());
                }
            },
            _ => cur.push(c),
        }
    }
    if (!cur.is_empty()) {
        out.push(cur.take());
    }
    out
}

/// dart-sass `flattenVertically`: flatten a list of groups column-major —
/// the first element of every group, then the second, … (`[[a,b],[c,d]]` →
/// `[a,c,b,d]`).
function flatten_vertically(groups: string[][]) -> string[] {
    if (groups.length() == 1) {
        return groups.at(0) ?? [];
    }
    // PORT: `VecDeque<String>` → a copied array consumed with `shift()`.
    let queues: string[][] = groups.map((g: string[]) -> string[] {
        root.std.clone_vec(g)
    });
    let out: string[] = [];
    while (queues.length() != 0) {
        root.std.retain(queues, (q: string[]) -> bool {
            let v = q.shift();
            if (v != null) {
                out.push(v);
            }
            q.length() != 0
        });
    }
    out
}

/// Validate that every top-level `&` in a child complex selector appears at the
/// start of a compound selector (start of the part, or right after a combinator
/// or whitespace), matching dart-sass's parser. A `&` elsewhere (e.g. `d&`,
/// `[d]&`) errors with `"&" may only used at the beginning of a compound
/// selector.`. Quoted strings and the contents of `[…]`/`(…)` groups are
/// skipped.
function validate_parent_placement(s: string) -> void {
    let chars = s.chars();
    let i = 0;
    let at_compound_start = true;
    let depth = 0;
    while (i < chars.length()) {
        let c = chars[i];
        match (c) {
            "\\" => {
                i += 2;
                at_compound_start = false;
                continue;
            },
            "\"" | "'" => {
                let q = c;
                i += 1;
                while (i < chars.length()) {
                    if (chars[i] == "\\") {
                        i += 2;
                        continue;
                    }
                    if (chars[i] == q) {
                        i += 1;
                        break;
                    }
                    i += 1;
                }
                at_compound_start = false;
                continue;
            },
            "[" | "(" => {
                depth += 1;
                at_compound_start = false;
            },
            "]" | ")" => {
                depth -= 1;
                at_compound_start = false;
            },
            _ if depth > 0 => {},
            " " | "\t" | "\n" | "\r" | ">" | "+" | "~" => {
                at_compound_start = true;
            },
            "&" => {
                if (!at_compound_start) {
                    throw root.error.Error.unpositioned("\"&\" may only used at the beginning of a compound selector.");
                }
                at_compound_start = false;
            },
            _ => {
                at_compound_start = false;
            },
        }
        i += 1;
    }
}

/// Whether a complex-selector string has a top-level `&` (outside brackets,
/// parens, and quotes), i.e. a parent reference this resolver substitutes.
/// Whether `s` contains a `&` parent reference. dart-sass substitutes a `&`
/// wherever it appears in selector position, including inside a selector-list
/// pseudo (`:is(&)`, `:not(&)`), so any paren depth counts; a `&` inside a
/// quoted string, an escape, or an attribute value (`[x=&]`) is literal and
/// does not.
function has_parent_ref(s: string) -> bool {
    let bracket = 0;
    // PORT: `s.chars().peekable()` → an index cursor over the chars.
    let chars = s.chars();
    let i = 0;
    while (i < chars.length()) {
        let c = chars[i];
        i += 1;
        match (c) {
            "\\" => {
                // `chars.next()`: skip the escaped char (if any).
                i += 1;
            },
            "\"" | "'" => {
                let q = c;
                while (i < chars.length()) {
                    let n = chars[i];
                    i += 1;
                    if (n == "\\") {
                        continue;
                    }
                    if (n == q) {
                        break;
                    }
                }
            },
            "[" => {
                bracket += 1;
            },
            "]" => {
                bracket -= 1;
            },
            "&" if bracket == 0 => {
                return true;
            },
            _ => {},
        }
    }
    false
}

/// Replace every unescaped, unquoted top-level `&` in `s` with `parent`. The
/// text directly following a `&` joins onto the parent's last compound by string
/// adjacency (e.g. `&.y` with parent `.a .b` becomes `.a .b.y`).
function expand_parent_refs(s: string, parents: string[], parent_list: string) -> string[] {
    let variants: string[] = [""];
    // PORT: `s.chars().peekable()` → an index cursor over the chars.
    let chars = s.chars();
    let i = 0;
    let paren = 0;
    // PORT: `v.push_str(text)` on each `&mut String` → reassign each slot.
    let push_all = (variants: string[], text: string) -> void {
        let j = 0;
        while (j < variants.length()) {
            variants[j] = variants[j] + text;
            j += 1;
        }
    };
    while (i < chars.length()) {
        let c = chars[i];
        i += 1;
        match (c) {
            "\\" => {
                let t: string = c;
                if (i < chars.length()) {
                    let n = chars[i];
                    i += 1;
                    t = t + n;
                }
                push_all(variants, t);
            },
            "\"" | "'" => {
                let t: string = c;
                let q = c;
                while (i < chars.length()) {
                    let n = chars[i];
                    i += 1;
                    t = t + n;
                    if (n == q) {
                        break;
                    }
                }
                push_all(variants, t);
            },
            "(" => {
                paren += 1;
                push_all(variants, "(");
            },
            ")" => {
                paren -= 1;
                push_all(variants, ")");
            },
            // Inside a selector pseudo the parent reference receives the
            // whole parent LIST (`:is(&)` -> `:is(c, d)`).
            "&" if paren > 0 => push_all(variants, parent_list),
            // A top-level `&` expands as a cartesian product: each occurrence
            // picks a parent complex independently, the last varying fastest.
            "&" => {
                variants
                    = variants.flat_map((v: string) -> string[] {
                        parents.map((p: string) -> string {
                            `${v}${p}`
                        })
                    });
            },
            _ => push_all(variants, c),
        }
    }
    variants
}

/// Split a selector-list string on top-level commas (depth-aware), trimming.
function split_top_commas(s: string) -> string[] {
    let out: string[] = [];
    let cur = root.std.StrBuf.new();
    let paren = 0;
    let bracket = 0;
    // PORT: `s.chars().peekable()` → an index cursor over the chars.
    let chars = s.chars();
    let i = 0;
    while (i < chars.length()) {
        let c = chars[i];
        i += 1;
        match (c) {
            "\\" => {
                cur.push(c);
                if (i < chars.length()) {
                    let n = chars[i];
                    i += 1;
                    cur.push(n);
                }
            },
            "\"" | "'" => {
                cur.push(c);
                let q = c;
                while (i < chars.length()) {
                    let n = chars[i];
                    i += 1;
                    cur.push(n);
                    if (n == q) {
                        break;
                    }
                }
            },
            "(" => {
                paren += 1;
                cur.push(c);
            },
            ")" => {
                paren -= 1;
                cur.push(c);
            },
            "[" => {
                bracket += 1;
                cur.push(c);
            },
            "]" => {
                bracket -= 1;
                cur.push(c);
            },
            "," if paren == 0 && bracket == 0 => out.push(cur.take()),
            _ => cur.push(c),
        }
    }
    out.push(cur.take());
    out.filter((p: string) -> bool {
        root.std.trim(p) != ""
    })
}

// ---- nest -------------------------------------------------------------
/// `selector-nest($selectors...)`: nest each selector within the previous,
/// resolving `&` against the accumulated result (dart-sass `nest`).
function fn_nest(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> root.value.Value {
    let all: root.value.Value[] = root.std.clone_vec(pos_args);
    for (let t in named) {
        all.push(t._1);
    }
    if (all.length() == 0) {
        throw root.error.Error.at("$selectors: At least one selector must be passed.", pos);
    }
    // The first selector is the base; it MAY contain `&`, which stays
    // literal (dart-sass parses it with parent references allowed):
    // `nest("&")` is `&`, `nest("&", ".x")` is `& .x`.
    let first = value_to_selector_string(all[0], "selectors", pos);
    let acc: string[] = if (has_parent_ref(first)) {
        let parts = split_top_commas(first);
        for (let cc in parts) {
            validate_parent_placement(cc);
            // A top-level `&` may not carry a suffix (`&c`) — dart-sass
            // rejects it when parsing the first argument.
            let chars = cc.chars();
            let i = 0;
            for (let ch in chars) {
                if (ch == "&") {
                    let n = chars.at(i + 1);
                    if (n != null) {
                        if (n.is_alphanumeric() || n == "-" || n == "_" || n == "\\") {
                            throw root.error.Error.at("A top-level selector may not contain a parent selector with a suffix.", pos);
                        }
                    }
                }
                i += 1;
            }
        }
        parts.map((p: string) -> string {
            root.std.trim(p)
        })
    } else {
        parse_arg_selector(all[0], pos).map((c: root.selector.Complex) -> string {
            c.render()
        })
    };
    for (let v in all.slice(1, all.length())) {
        let child = value_to_selector_string(v, "selectors", pos);
        acc = resolve_parents_str(child, acc, "selector-nest", pos);
    }
    selector_strings_to_value(acc)
}

/// Parse a single selector value argument into a complex-selector list.
function parse_arg_selector(v: root.value.Value, pos: root.scanner.Pos) -> root.selector.Complex[] {
    let text = value_to_selector_string(v, "selectors", pos);
    parse_selector_text(text, "selectors", pos)
}

// ---- append -----------------------------------------------------------
/// `selector-append($selectors...)`: append each selector to the previous with
/// no descendant combinator — the leading compound of each subsequent complex
/// merges onto the trailing compound of the accumulator (dart-sass `append`).
function fn_append(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> root.value.Value {
    let all: root.value.Value[] = root.std.clone_vec(pos_args);
    for (let t in named) {
        all.push(t._1);
    }
    if (all.length() == 0) {
        throw root.error.Error.at("$selectors: At least one selector must be passed.", pos);
    }
    let acc = parse_arg_selector(all[0], pos);
    for (let v in all.slice(1, all.length())) {
        let suffix = parse_arg_selector(v, pos);
        acc = append_lists(acc, suffix, pos);
    }
    selectors_to_value(acc)
}

/// Append `suffix` to `prefix`: for each prefix complex × suffix complex, the
/// suffix's leading compound (which must carry no combinator) is concatenated
/// onto the prefix's trailing compound; the rest of the suffix follows
/// (dart-sass `append`/`_prependParent`).
function append_lists(
    prefix: root.selector.Complex[],
    suffix: root.selector.Complex[],
    pos: root.scanner.Pos,
) -> root.selector.Complex[] {
    let out: root.selector.Complex[] = [];
    for (let p in prefix) {
        // A parent with a trailing combinator (`.c ~`) can't be appended onto.
        if (p.trailing.length() != 0) {
            throw root.error.Error.at(`Selector "${p.render()}" can't be used as a parent in a compound selector.`, pos);
        }
        let p_one = p.render();
        for (let s in suffix) {
            // The first component of the suffix must have no combinator, and its
            // leading simple may not be a universal selector or a namespaced type
            // selector (those can't suffix another compound), matching dart-sass
            // `_prependParent`.
            let s_str = s.render();
            // A combinator-only suffix (`>`) has no compound to append.
            if (s.components.length() == 0) {
                throw root.error.Error.at(`Can't append ${s_str} to ${p_one}.`, pos);
            }
            let first = s.components.at(0);
            if (first != null) {
                let leading = first.compound.simples.at(0);
                let is_universal = match (leading) {
                    root.selector.Simple_Universal {} => true,
                    _ => false,
                };
                let is_ns_type = match (leading) {
                    root.selector.Simple_Type { _0: let t } => t.includes("|"),
                    _ => false,
                };
                let leading_blocks_append = is_universal || is_ns_type;
                if (first.combinator() != null || leading_blocks_append) {
                    throw root.error.Error.at(`Can't append ${s_str} to ${p_one}.`, pos);
                }
            }
            // Concatenate the prefix and the suffix's leading compound by string
            // adjacency, so `.a` + `.b.c` → `.a.b.c` and `ul` + `li` → `ulli`.
            let combined = `${p_one}${s_str}`;
            let parsed = root.selector.parse.parse_list(combined);
            if (parsed == null) {
                throw root.error.Error.at(`Can't append ${s_str} to ${p_one}.`, pos);
            }
            root.std.extend(out, parsed);
        }
    }
    out
}

// ---- extend / replace -------------------------------------------------
/// `selector-extend($selector, $extendee, $extender)`: extend `$selector` so
/// that wherever `$extendee` matches, `$extender` is added too (keeping the
/// original). Mirrors `@extend` (normal mode).
function fn_extend(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> root.value.Value {
    extend_or_replace(pos_args, named, pos, false, "selector-extend")
}

/// `selector-replace($selector, $original, $replacement)`: like `selector-extend`
/// but the matched selector is replaced (the original is dropped).
function fn_replace(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> root.value.Value {
    extend_or_replace(pos_args, named, pos, true, "selector-replace")
}

function extend_or_replace(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
    replace: bool,
    fname: string,
) -> root.value.Value {
    let params: string[] = if (replace) {
        ["selector", "original", "replacement"]
    } else {
        ["selector", "extendee", "extender"]
    };
    check_arity(pos_args, named, 3, pos);
    let selector = selector_list_arg(params, pos_args, named, 0, pos);
    let target_list = selector_list_arg(params, pos_args, named, 1, pos);
    let extender = selector_list_arg(params, pos_args, named, 2, pos);

    // The extendee/original is a list of compound selectors: each complex
    // selector in it must be a single compound (dart-sass rejects a complex
    // selector here). Every compound becomes a separate extension target.
    let targets = compound_targets(target_list, pos);

    let complexes = root.selector.extend_compound_target(selector, targets, extender, replace);
    if (complexes.length() == 0) {
        throw root.error.Error.at(`${fname}() produced an empty selector.`, pos);
    }
    selectors_to_value(complexes)
}

/// Extract the compound targets of an extendee/original selector list. The list
/// may contain several complex selectors, but each must itself be a single
/// compound (dart-sass rejects a complex selector with a combinator or multiple
/// components, erroring `Can't extend complex selector <rendered>.`).
function compound_targets(
    list: root.selector.Complex[],
    pos: root.scanner.Pos,
) -> root.selector.Compound[] {
    let out: root.selector.Compound[] = [];
    for (let complex in list) {
        if (complex.components.length() == 1 && complex.components[0].combinator() == null) {
            // PORT: `.clone()` → alias; neither side is mutated afterwards.
            out.push(complex.components[0].compound);
        } else {
            throw root.error.Error.at(`Can't extend complex selector ${complex.render()}.`, pos);
        }
    }
    out
}

// ---- unify ------------------------------------------------------------
/// `selector-unify($selector1, $selector2)`: the selectors matching both inputs,
/// or `null` when no combination unifies (dart-sass `unify`).
function fn_unify(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> root.value.Value {
    let params = ["selector1", "selector2"];
    check_arity(pos_args, named, 2, pos);
    let s1 = selector_list_arg(params, pos_args, named, 0, pos);
    let s2 = selector_list_arg(params, pos_args, named, 1, pos);
    let unified = root.selector.unify_lists(s1, s2);
    if (unified != null) {
        selectors_to_value(unified)
    } else {
        root.value.Value_Null {  }
    }
}

// ---- is-superselector -------------------------------------------------
/// `is-superselector($super, $sub)`: whether `$super` matches every element
/// `$sub` matches (dart-sass `is-superselector`).
function fn_is_superselector(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> root.value.Value {
    let params = ["super", "sub"];
    check_arity(pos_args, named, 2, pos);
    let sup = selector_list_arg(params, pos_args, named, 0, pos);
    let sub = selector_list_arg(params, pos_args, named, 1, pos);
    root.value.Value_Bool { _0: root.selector.list_is_superselector(sup, sub) }
}

// ---- simple-selectors -------------------------------------------------
/// `simple-selectors($selector)`: the simple selectors of a single compound
/// selector, as a comma list of unquoted strings (dart-sass `simple-selectors`).
function fn_simple_selectors(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> root.value.Value {
    let params = ["selector"];
    check_arity(pos_args, named, 1, pos);
    let v = root.builtins.require(params, pos_args, named, 0, pos);
    let text = value_to_selector_string(v, "selector", pos);
    if (root.std.trim(text) == "") {
        throw root.error.Error.at("$selector: expected selector.", pos);
    }
    let simples = root.selector.parse_compound_simples(text);
    if (simples == null) {
        throw root.error.Error.at("$selector: expected selector.", pos);
    }
    let items: root.value.Value[] = simples.map((text: string) -> root.value.Value {
        root.value.Value_Str { _0: root.value.SassStr { text: text, quoted: false } }
    });
    root.value.Value_List {
        _0: root.value.List {
            items: items,
            sep: root.value.ListSep.Comma,
            bracketed: false,
            keywords: null,
        },
    }
}

// ---- parse ------------------------------------------------------------
/// `selector-parse($selector)`: parse a selector string/value into a selector
/// value (dart-sass `parse`).
function fn_parse(
    pos_args: root.value.Value[],
    named: root.std.Tuple2<string, root.value.Value>[],
    pos: root.scanner.Pos,
) -> root.value.Value {
    let params = ["selector"];
    check_arity(pos_args, named, 1, pos);
    let list = selector_list_arg(params, pos_args, named, 0, pos);
    selectors_to_value(list)
}
