// Ported from sasso `src/selector/mod.rs` (namespace `root.selector`).
//
// A structured CSS selector model plus the `@extend` engine.
//
// Selectors are parsed from their already-resolved string form (after `&`
// and interpolation have been substituted by the evaluator) into a small
// tree — [`ComplexSelector`] → [`ComplexComponent`] → [`CompoundSelector`]
// → [`SimpleSelector`] — that mirrors dart-sass's model closely enough to
// port its `@extend` algorithm (extension, unification, transitive chains,
// and placeholder-rule dropping).

/// A value paired with its precomputed FxHash, so a map keyed by `Hashed<T>`
/// hashes the (already-walked) inner `T` exactly ONCE — at construction — and
/// every subsequent map probe just re-mixes the cached `u64`. `Eq` still
/// compares the inner `value` structurally, so the map partitions IDENTICALLY
/// to one keyed by the bare `T` (byte-exact: these maps are only probed for
/// membership/lookup, never iterated for output order). Used for the `@extend`
/// engine's per-batch `Complex`-keyed maps, whose derived `Hash` otherwise
/// re-walks the whole components→compounds→simples→`String` tree on every probe.
class Hashed<T> {
    hash: bigint,
    value: T,
    function new(value: T) -> Hashed<T> {
        let h = root.fxhash.FxHasher.default();
        // PORT: BAML has no `Hash` trait; `value.hash(&mut h)` hashes the value's
        // structural `to_string()` rendering instead (equal values render equally,
        // so the hash still agrees with the structural `==`).
        h.write(value.to_string().to_utf8());
        Hashed { hash: h.finish(), value: value }
    }

    // PORT: `impl Hash` dropped (derive-like / not needed in BAML).

    implements baml.ops.Equals {
        function eq(self, other: Hashed<T>) -> bool {
            // The cached hash is a cheap discriminator before the structural compare.
            self.hash == other.hash && self.value == other.value
        }
    }

    // PORT: `impl Eq` dropped (derive-like / not needed in BAML).
}

/// A combinator joining two compound selectors.
enum Combinator {
    Child, // >
    NextSibling, // +
    FollowingSibling, // ~
}

interface CombinatorMethods {
    function as_str(self) -> string throws unknown;
}

implements CombinatorMethods for Combinator {
    function as_str(self) -> string {
        match (self) {
            Combinator.Child => ">",
            Combinator.NextSibling => "+",
            Combinator.FollowingSibling => "~",
        }
    }

}

/// One simple selector: the atoms of a compound selector.
interface Simple {
    function render(self) -> string throws never {
        match (self) {
            Simple_Universal { ns: null } => "*",
            Simple_Universal { ns: let n: string } => `${n}|*`,
            let s: Simple_Type => s._0,
            let s: Simple_Class => `.${s._0}`,
            let s: Simple_Id => `#${s._0}`,
            let s: Simple_Placeholder => `%${s._0}`,
            let s: Simple_Attribute => s._0,
            let s: Simple_Pseudo => s._0,
            _ => root.std.unreachable(),
        }
    }

    function is_placeholder(self) -> bool throws never {
        self is Simple_Placeholder
    }
}

/// `*` or `ns|*`. Stores the optional namespace prefix verbatim.
class Simple_Universal {
    ns: string?,
    implements Simple {}
}

/// A type/element selector, e.g. `div`, `svg|rect`. Stored verbatim.
class Simple_Type {
    _0: string,
    implements Simple {}
}

/// `.foo`
class Simple_Class {
    _0: string,
    implements Simple {}
}

/// `#foo`
class Simple_Id {
    _0: string,
    implements Simple {}
}

/// `%foo`
class Simple_Placeholder {
    _0: string,
    implements Simple {}
}

/// `[attr=val i]` etc. — the whole bracketed text including `[` `]`.
class Simple_Attribute {
    _0: string,
    implements Simple {}
}

/// A pseudo class/element. Stored verbatim text including leading colon(s),
/// e.g. `:hover`, `::before`, `:not(.x)`.
class Simple_Pseudo {
    _0: string,
    implements Simple {}
}

/// A resolved selector as dart-sass writes it in COMPRESSED style.
///
/// Two kinds of whitespace go, and no others:
///
/// * the space on either side of a COMBINATOR — `.a > .b` is `.a>.b`, and a
///   combinator that opens a relative selector loses its trailing space too
///   (`:has(+ .b)` is `:has(+.b)`);
/// * the space after the comma of a SELECTOR LIST — the list a `:not()`,
///   `:is()`, `:where()`, `:has()` … carries, or the `of` tail of an
///   `:nth-child()`.
///
/// Every other space is structure (`.a .b` IS the descendant combinator) and
/// every other comma is opaque: `:lang(en, fr)` keeps its space, because its
/// argument is an identifier list and not a selector list. Attribute values and
/// quoted strings are copied through untouched.
///
/// The top-level list's own commas never reach here — emit joins the complexes
/// with `,` itself.
function compress_selector(sel: string) -> string {
    // Nothing to do unless the selector has a combinator or a pseudo argument.
    if (
        !root.std.any_char(sel, (b: string) -> bool {
            b == ">" || b == "+" || b == "~" || b == "("
        })
    ) {
        return sel;
    }
    let chars = sel.chars();
    let out = root.std.StrBuf.with_capacity(sel.length());
    compress_into(out, chars);
    out.as_str()
}

/// Append `chars` — one complex selector, or one component of a selector list
/// argument — to `out` in compressed form.
function compress_into(out: root.std.StrBuf, chars: string[]) -> void {
    let i = 0;
    while (i < chars.length()) {
        match (chars[i]) {
            "\\" => {
                let end = escape_end(chars, i);
                out.push_str(root.std.join(chars.slice(i, end), ""));
                i = end;
            },
            "\"" | "'" => {
                let end = skip_quoted(chars, i);
                out.push_str(root.std.join(chars.slice(i, root.std.imin(end, chars.length())), ""));
                i = end;
            },
            "[" => {
                // An attribute selector: its insides are not selector structure.
                let end = skip_attribute(chars, i);
                out.push_str(root.std.join(chars.slice(i, root.std.imin(end, chars.length())), ""));
                i = end;
            },
            " " | "\t" | "\n" | "\r" => {
                let j = i;
                while (j < chars.length() && chars[j].is_whitespace()) {
                    j += 1;
                }
                // A run of whitespace IS the descendant combinator — unless
                // what follows is a combinator of its own, which eats it.
                let next = chars.at(j);
                if (!(next == ">" || next == "+" || next == "~") && j < chars.length()) {
                    out.push(" ");
                }
                i = j;
            },
            ">" | "+" | "~" => {
                out.push(chars[i]);
                i += 1;
                while (i < chars.length() && chars[i].is_whitespace()) {
                    i += 1;
                }
            },
            ":" => {
                let name_start = i
                    + 1
                    + (
                        if (chars.at(i + 1) == ":") {
                            1
                        } else {
                            0
                        }
                    );
                let j = name_start;
                while (
                    j < chars.length()
                        && (
                            chars[j].is_ascii_alphanumeric()
                                || chars[j] == "-"
                                || chars[j] == "_"
                                || root.std.ord(chars[j]) >= 0x80
                        )
                ) {
                    j += 1;
                }
                if (chars.at(j) != "(") {
                    out.push_str(root.std.join(chars.slice(i, j), ""));
                    i = j;
                    continue;
                }
                let close = matching_paren(chars, j);
                let name = root.std.join(chars.slice(name_start, j), "");
                out.push_str(root.std.join(chars.slice(i, j + 1), ""));
                compress_pseudo_arg(out, name, chars.slice(j + 1, root.std.imin(close, chars.length())));
                if (close < chars.length()) {
                    out.push(")");
                    i = close + 1;
                } else {
                    i = chars.length();
                }
            },
            let c => {
                out.push(c);
                i += 1;
            },
        }
    }
}

/// Append one pseudo's argument, compressed according to what that pseudo
/// takes: a selector list, an An+B (with an optional `of` list), or an opaque
/// run copied verbatim.
function compress_pseudo_arg(out: root.std.StrBuf, name: string, inner: string[]) -> void {
    let unv = unvendor(name);
    if (unv == "nth-child" || unv == "nth-last-child") {
        // The An+B itself is already normalised; only the `of` tail is a
        // selector list.
        let arg = root.std.join(inner, "");
        match (arg.index_of(" of ")) {
            let at: int => {
                out.push_str(arg.slice(0, at + 4));
                compress_selector_list(out, arg.slice(at + 4, arg.length()));
            },
            _ => out.push_str(arg),
        }
        return;
    }
    let is_selector_pseudo = (
        match (unv) {
            "not"
                | "is"
                | "where"
                | "has"
                | "matches"
                | "any"
                | "host"
                | "host-context"
                | "current"
                | "slotted" =>
            {
                true
            },
            _ => false,
        }
    )
        || unv.ends_with("-any");
    if (is_selector_pseudo) {
        let arg = root.std.join(inner, "");
        compress_selector_list(out, arg);
    } else {
        out.push_str(root.std.join(inner, ""));
    }
}

/// The index just past the CSS escape starting at `start` (which holds a `\`):
/// up to six hex digits and the single whitespace character that terminates
/// them, or the one character that follows a non-hex escape. The terminator is
/// part of the TOKEN — `.\31  .b` is the class `1` and then a descendant
/// combinator, and losing either space changes which.
function escape_end(chars: string[], start: int) -> int {
    let i = start + 1;
    if (!root.std.is_ascii_hexdigit(chars.at(i))) {
        // `\,`, `\ `, `\+` … — exactly one character, whatever it is.
        return root.std.imin(i + 1, chars.length());
    }
    let hex_start = i;
    while (i < chars.length() && i - hex_start < 6 && chars[i].is_ascii_hex()) {
        i += 1;
    }
    // One whitespace character closes the run (and CRLF counts as one).
    match (chars.at(i)) {
        "\r" if chars.at(i + 1) == "\n" => i + 2,
        let c: string if c.is_whitespace() => i + 1,
        _ => i,
    }
}

/// Append a selector-list argument: each component compressed, joined by a bare
/// comma.
function compress_selector_list(out: root.std.StrBuf, arg: string) -> void {
    let i = 0;
    for (let part in root.selector.parse.split_top(arg, ",")) {
        if (i > 0) {
            out.push(",");
        }
        let cs = root.std.trim_start(part).chars();
        compress_into(out, cs);
        i += 1;
    }
}

/// Validate the arguments of every grammar-typed pseudo in a resolved selector
/// string the way dart-sass does, returning the exact dart error message on a
/// malformed one. Two pseudo families carry a strict grammar. The An+B pseudos
/// `:nth-child` / `:nth-last-child` (see [`validate_nth`]) — including a vendor
/// prefix (`unvendor(name)` must equal the bare name) — take an An+B argument.
/// The selector-argument pseudos `:not` / `:is` / `:where` / `:has` / `:matches`
/// / `:any` / `:-*-any` / `:host` / `:host-context` / `:current` take a non-empty
/// selector list (an empty leading or trailing component is dart's
/// `expected selector.`), recursively validated. Every OTHER pseudo (`:lang`,
/// `:dir`, custom `:--foo`, unknown `:foo`) takes an opaque argument and is left
/// untouched. The input is already interpolation-resolved, so this matches dart
/// validating the resolved text.
function validate_pseudo_args(sel: string) -> void {
    // PORT: `Result<(), &'static str>` → the message is thrown as a
    // `root.std.StrError` (catch `let e: root.std.StrError`).
    let chars = sel.chars();
    validate_pseudo_args_inner(chars);
}

function validate_pseudo_args_inner(chars: string[]) -> void {
    let i = 0;
    while (i < chars.length()) {
        match (chars[i]) {
            "\\" => {
                i += 2;
                continue;
            },
            "\"" | "'" => {
                i = skip_quoted(chars, i);
                continue;
            },
            "[" => {
                // Skip a whole attribute selector; commas/parens inside it are
                // not selector structure.
                i = skip_attribute(chars, i);
                continue;
            },
            ":" => {
                // A pseudo: read the name, then (if present) its `(...)` arg.
                let name_start = i
                    + 1
                    + (
                        if (chars.at(i + 1) == ":") {
                            1
                        } else {
                            0
                        }
                    );
                let j = name_start;
                while (
                    j < chars.length()
                        && (
                            chars[j].is_ascii_alphanumeric()
                                || chars[j] == "-"
                                || chars[j] == "_"
                                || root.std.ord(chars[j]) >= 0x80
                        )
                ) {
                    j += 1;
                }
                if (j < chars.length() && chars[j] == "(") {
                    let close = matching_paren(chars, j);
                    let name = root.std.join(chars.slice(name_start, j), "");
                    let inner = chars.slice(j + 1, root.std.imin(close, chars.length()));
                    validate_one_pseudo_arg(name, inner);
                    i
                        = if (close < chars.length()) {
                            close + 1
                        } else {
                            chars.length()
                        };
                    continue;
                }
                i = j;
                continue;
            },
            _ => {
                i += 1;
            },
        }
    }
}

/// Validate one pseudo's `(...)` argument (`inner`, without the parens) given
/// its `name` (without the leading colon). Dispatches on the unvendored
/// lowercase name; opaque pseudos return `Ok` untouched.
function validate_one_pseudo_arg(name: string, inner: string[]) -> void {
    let unv = unvendor(name);
    // An+B pseudos.
    if (unv == "nth-child" || unv == "nth-last-child") {
        let arg = root.std.join(inner, "");
        validate_nth(arg);
        // Recurse into the `of <selector>` tail's selector list (validated
        // non-empty by `validate_nth`; here its nested pseudos are checked).
        let of_sel = nth_of_selector(inner);
        if (of_sel != null) {
            validate_selector_list_arg(of_sel);
        }
        return;
    }
    // Selector-argument pseudos.
    let is_selector_pseudo = (
        match (unv) {
            "not" | "is" | "where" | "has" | "matches" | "any" | "host" | "host-context" | "current" => {
                true
            },
            _ => false,
        }
    )
        || unv.ends_with("-any");
    if (is_selector_pseudo) {
        let arg = root.std.join(inner, "");
        validate_selector_list_arg(arg);
        return;
    }
    // Any other pseudo carries an opaque argument.
}

/// Validate a selector-list argument (the inside of a `:not(...)` etc., or an
/// `of` tail): split on top-level commas; the FIRST and LAST components must be
/// non-empty (dart reads complexes around comma runs and errors on an empty
/// leading/trailing one — `:not(, .a)`, `:not(.a, )`, `:not()` all
/// `expected selector.`; an empty MIDDLE part `:not(.a,, .b)` is tolerated).
/// Each non-empty component is recursively scanned for nested pseudo grammar.
function validate_selector_list_arg(arg: string) -> void {
    let parts = root.selector.parse.split_top(arg, ",");
    // An all-empty argument (`()`, `( )`) has no first complex.
    if (
        parts.every((p: string) -> bool {
            root.std.trim(p) == ""
        })
    ) {
        root.std.err_str("expected selector.");
    }
    let first = parts.at(0);
    let last = root.std.last(parts);
    if (
        (
            if (first != null) {
                root.std.trim(first) == ""
            } else {
                false
            }
        )
            || (
                if (last != null) {
                    root.std.trim(last) == ""
                } else {
                    false
                }
            )
    ) {
        root.std.err_str("expected selector.");
    }
    for (let part in parts) {
        if (root.std.trim(part) == "") {
            continue;
        }
        let cs = part.chars();
        validate_pseudo_args_inner(cs);
    }
}

/// Index of the `)` matching the `(` at `open`, honouring strings/escapes and
/// nested parens. Returns `chars.len()` when unmatched.
function matching_paren(chars: string[], open: int) -> int {
    let depth = 0;
    let i = open;
    while (i < chars.length()) {
        match (chars[i]) {
            "\\" => {
                i += 2;
            },
            "\"" | "'" => {
                i = skip_quoted(chars, i);
            },
            "(" => {
                depth += 1;
                i += 1;
            },
            ")" => {
                depth -= 1;
                if (depth == 0) {
                    return i;
                }
                i += 1;
            },
            _ => {
                i += 1;
            },
        }
    }
    chars.length()
}

/// Index just past a quoted string starting at `start`, honouring `\` escapes;
/// `chars.len()` for an unterminated string.
function skip_quoted(chars: string[], start: int) -> int {
    let q = chars[start];
    let i = start + 1;
    while (i < chars.length()) {
        match (chars[i]) {
            "\\" => {
                i += 2;
            },
            let c if c == q => {
                return i + 1;
            },
            _ => {
                i += 1;
            },
        }
    }
    chars.length()
}

/// Index just past a `[...]` attribute selector starting at `start`, honouring
/// strings/escapes; `chars.len()` for an unterminated one.
function skip_attribute(chars: string[], start: int) -> int {
    let i = start + 1;
    while (i < chars.length()) {
        match (chars[i]) {
            "\\" => {
                i += 2;
            },
            "\"" | "'" => {
                i = skip_quoted(chars, i);
            },
            "]" => {
                return i + 1;
            },
            _ => {
                i += 1;
            },
        }
    }
    chars.length()
}

/// Normalize a `:nth-child(…)` / `:nth-last-child(…)` pseudo's An+B argument
/// (`2n + 1` → `2n+1`, `2N + 1` → `2n+1`, `3n - 2` → `3n-2`), preserving an
/// `of <selector>` tail. Only the lowercase `nth-child`/`nth-last-child`
/// pseudos are normalized (dart-sass keeps any other pseudo — including an
/// uppercased name or `:nth-of-type` — verbatim). Returns `None` when the text
/// is not such a pseudo, leaving it unchanged.
function normalize_nth(text: string) -> string? {
    let open = text.index_of("(");
    if (open == null) {
        return null;
    }
    if (!text.ends_with(")")) {
        return null;
    }
    let name = text.slice(0, open);
    if (name != ":nth-child" && name != ":nth-last-child") {
        return null;
    }
    let arg = text.slice(open + 1, text.length() - 1);
    // Split off an `of <selector>` tail at a whitespace-bounded `of` keyword.
    let lower = root.std.ascii_lower(arg);
    let found = find_of_keyword(lower);
    let anb = if (found != null) {
        arg.slice(0, found)
    } else {
        arg
    };
    let of_sel: string? = if (found != null) {
        root.std.trim(arg.slice(found + 2, arg.length()))
    } else {
        null
    };
    // The An+B canonical form has no internal whitespace and a lowercase `n`.
    let anb_norm = root.std.join(
        anb.chars().filter((c: string) -> bool {
            !c.is_whitespace()
        }),
        "",
    );
    if (anb_norm == "") {
        return null;
    }
    let anb_norm = root.std.ascii_lower(anb_norm);
    match (of_sel) {
        let sel: string => `${name}(${anb_norm} of ${sel})`,
        _ => `${name}(${anb_norm})`,
    }
}

/// Validate an `:nth-child` / `:nth-last-child` An+B argument the way dart-sass's
/// `_aNPlusB` (plus the surrounding `of <selector>` handling) does, returning the
/// exact dart error message on a malformed argument. `arg` is the raw text BETWEEN
/// the parentheses (interpolation already resolved). Only the `:nth-child` and
/// `:nth-last-child` pseudos are validated; dart leaves `:nth-of-type` and
/// `:nth-last-of-type` permissive, so their callers never reach here.
///
/// Grammar (dart `_aNPlusB`, scanner-based, derived empirically):
///   leading whitespace is skipped, then one of:
///     - `even` / `odd` (case-insensitive, a whole-identifier match), OR
///     - an optional `+`/`-` sign, optional run of digits, then either:
///         * `n`/`N` (only after the optional sign+digits, with NO whitespace
///           skipped before it UNLESS digits were consumed), followed by an
///           optional ` [+-] <digits>` tail; OR
///         * nothing more (a pure integer — requires at least one digit).
///   After the An+B, an optional ` of <selector>` tail (whitespace-introduced)
///   is allowed; any other trailing content is rejected.
function validate_nth(arg: string) -> void {
    let chars = arg.chars();
    let i = 0;
    // PORT: the `skip_ws(&mut i)` closure advances the captured `i` directly
    // (BAML closures assign captured locals), so it takes no argument.
    let skip_ws = () -> void {
        while (i < chars.length() && chars[i].is_whitespace()) {
            i += 1;
        }
    };
    skip_ws();
    // `even` / `odd` — a whole keyword, case-insensitive.
    let first = chars.at(i);
    match (
        if (first != null) {
            root.std.ascii_lower(first)
        } else {
            null
        }
    ) {
        "e" => {
            return finish_nth(chars, scan_keyword(chars, root.std.Cell.new(i), "even"));
        },
        "o" => {
            return finish_nth(chars, scan_keyword(chars, root.std.Cell.new(i), "odd"));
        },
        _ => {},
    }
    // Optional sign.
    if (chars.at(i) == "+" || chars.at(i) == "-") {
        i += 1;
    }
    // Optional run of digits.
    let digits_start = i;
    while (root.std.is_ascii_digit(chars.at(i))) {
        i += 1;
    }
    let saw_digit = i > digits_start;
    // Position right after the An+B body so far (before any speculative ws skip),
    // so `finish_nth` can tell whether whitespace separated trailing content.
    let body_end = i;
    // dart skips whitespace before `n` ONLY when digits were consumed (`5 n`
    // is `5n`, but `+ n` errors). With no digits, `n` must follow immediately.
    if (saw_digit) {
        skip_ws();
    }
    if (chars.at(i) == "n" || chars.at(i) == "N") {
        i += 1;
        body_end = i;
        // Optional ` [+-] <digits>` tail.
        skip_ws();
        if (chars.at(i) == "+" || chars.at(i) == "-") {
            i += 1;
            skip_ws();
            if (!root.std.is_ascii_digit(chars.at(i))) {
                root.std.err_str("Expected a number.");
            }
            while (root.std.is_ascii_digit(chars.at(i))) {
                i += 1;
            }
            body_end = i;
        }
        return finish_nth(chars, body_end);
    }
    // No `n`: a pure integer needs at least one digit; otherwise dart expects `n`.
    if (!saw_digit) {
        root.std.err_str("Expected \"n\".");
    }
    finish_nth(chars, body_end);
}

/// After the An+B is consumed at `i`, validate the remaining text: either
/// nothing (modulo trailing whitespace before the close — dart's caller is at
/// `)`), or a whitespace-introduced ` of <selector>` tail whose selector list
/// is non-empty. Trailing junk with no `of` is dart's `Expected "of".`; junk
/// glued with no whitespace before it is the caller's `expected ")".`.
function finish_nth(chars: string[], i: int) -> void {
    // dart only treats trailing content as an `of` clause when whitespace
    // separates it from the An+B; glued junk (`n1`, `2n+1of`) is left for the
    // caller, which then reports `expected ")".`.
    let had_ws = i < chars.length() && chars[i].is_whitespace();
    while (i < chars.length() && chars[i].is_whitespace()) {
        i += 1;
    }
    if (i >= chars.length()) {
        return;
    }
    if (!had_ws) {
        root.std.err_str("expected \")\".");
    }
    // Must be `of` (a complete, case-insensitive identifier) before the
    // selector. dart's `scanIdentifier("of")` distinguishes a mid-scan mismatch
    // (`Expected "of".` WITH a period — wrong char where `o`/`f` was expected)
    // from a fully-matched `of` glued to an extra identifier char (`ofx`,
    // `of-x`, `of9` → `Expected "of"` WITHOUT one). `of.a`/`of#x`/`of:hover` are
    // a complete `of` with the selector glued on (the next char isn't an ident
    // char), so they're accepted.
    if (
        !(
            (chars.at(i) == "o" || chars.at(i) == "O")
                && (chars.at(i + 1) == "f" || chars.at(i + 1) == "F")
        )
    ) {
        root.std.err_str("Expected \"of\".");
    }
    let of_complete = match (chars.at(i + 2)) {
        null => true,
        let c: string => {
            !(c.is_ascii_alphanumeric() || c == "-" || c == "_" || root.std.ord(c) >= 0x80)
        },
    };
    if (!of_complete) {
        root.std.err_str("Expected \"of\"");
    }
    i += 2;
    while (i < chars.length() && chars[i].is_whitespace()) {
        i += 1;
    }
    let rest = root.std.join(chars.slice(i, chars.length()), "");
    if (root.std.trim(rest) == "") {
        root.std.err_str("expected selector.");
    }
    // The `of` selector list is validated by the caller's recursive selector
    // validation; non-empty is the only check made here.
}

/// Extract the `of <selector>` tail's selector text from an already-validated
/// `:nth-child` argument (the part after a whitespace-introduced, complete-
/// identifier `of` keyword), or `None` when there is no `of` clause.
function nth_of_selector(inner: string[]) -> string? {
    let i = 0;
    // Find a whitespace-bounded `of` that is a complete identifier.
    while (i + 1 < inner.length()) {
        let before_ws = i > 0 && inner[i - 1].is_whitespace();
        let of_complete = match (inner.at(i + 2)) {
            null => true,
            let c: string => {
                !(c.is_ascii_alphanumeric() || c == "-" || c == "_" || root.std.ord(c) >= 0x80)
            },
        };
        if (
            before_ws
                && (inner[i] == "o" || inner[i] == "O")
                && (inner[i + 1] == "f" || inner[i + 1] == "F")
                && of_complete
        ) {
            let j = i + 2;
            while (j < inner.length() && inner[j].is_whitespace()) {
                j += 1;
            }
            return root.std.join(inner.slice(j, inner.length()), "");
        }
        i += 1;
    }
    null
}

/// Scan a whole keyword (`even`/`odd`) case-insensitively starting at `*i`,
/// returning the index past it. dart's `scanIdentifier` distinguishes two
/// failures with DIFFERENT messages: a char that doesn't match the keyword
/// mid-scan (or a too-short input) is `Expected "<kw>".` WITH a period; a full
/// keyword followed by an extra identifier-continuation char (`oddx`, `even1`)
/// is `Expected "<kw>"` WITHOUT one.
function scan_keyword(chars: string[], i: root.std.Cell<int>, kw: string) -> int {
    let msgs = match (kw) {
        "even" => root.std.Tuple2 { _0: "Expected \"even\".", _1: "Expected \"even\"" },
        _ => root.std.Tuple2 { _0: "Expected \"odd\".", _1: "Expected \"odd\"" },
    };
    let mismatch = msgs._0;
    let trailing = msgs._1;
    for (let k in kw.chars()) {
        match (chars.at(i.value)) {
            let c: string if root.std.ascii_lower(c) == k => {
                i.value += 1;
            },
            _ => {
                root.std.err_str(mismatch);
            },
        }
    }
    // No identifier character may immediately follow the keyword (`oddx`,
    // `even1` are dart errors), but a sign/digit-less boundary is fine.
    let next = chars.at(i.value);
    if (root.std.is_ascii_alphanumeric(next) || next == "-" || next == "_") {
        root.std.err_str(trailing);
    }
    i.value
}

/// If `text` is a `:nth-child`/`:nth-last-child` with an `of <selector>` tail,
/// return `(name, anb, selector)` — the pseudo name (with colon), the canonical
/// An+B, and the `of` selector list. The selectors compare by `(name, anb)` so
/// a nested same-An+B nth pseudo can be merged and a different one dropped.
function nth_of_parts(text: string) -> root.std.Tuple3<string, string, string>? {
    let open = text.index_of("(");
    if (open == null) {
        return null;
    }
    if (!text.ends_with(")")) {
        return null;
    }
    let name = text.slice(0, open);
    if (name != ":nth-child" && name != ":nth-last-child") {
        return null;
    }
    let arg = text.slice(open + 1, text.length() - 1);
    let pos = find_of_keyword(root.std.ascii_lower(arg));
    if (pos == null) {
        return null;
    }
    root.std.Tuple3 {
        _0: name,
        _1: root.std.trim(arg.slice(0, pos)),
        _2: root.std.trim(arg.slice(pos + 2, arg.length())),
    }
}

/// The byte index of a whitespace-bounded `of` keyword in an already-lowercased
/// `:nth-child` argument (the boundary between the An+B and the `of <selector>`
/// tail), or `None` if there is no `of` clause.
function find_of_keyword(lower: string) -> int? {
    // PORT: a CHARACTER index (the callers slice the same-length `arg` with it);
    // ASCII whitespace never occurs inside a multi-byte character, so testing
    // chars instead of bytes gives the same boundaries.
    let bytes = lower.chars();
    let i = 0;
    while let rel: int = lower.slice(i, lower.length()).index_of("of") {
        let pos = i + rel;
        let before_ws = pos == 0 || root.std.is_ascii_whitespace(bytes[pos - 1]);
        let after = pos + 2;
        let after_ws = after < bytes.length() && root.std.is_ascii_whitespace(bytes[after]);
        if (before_ws && after_ws) {
            return pos;
        }
        i = pos + 2;
    }
    null
}

/// A compound selector: a non-empty run of simple selectors with no
/// combinator between them, e.g. `.foo.bar:hover`.
class Compound {
    simples: Simple[],
    function render(self) -> string {
        root.std.join(
            self.simples.map((s: Simple) -> string {
                s.render()
            }),
            "",
        )
    }

    function has_placeholder(self) -> bool {
        self.simples.some((s: Simple) -> bool {
            s.is_placeholder()
        })
    }
}

/// One component of a complex selector: a compound preceded by the (usually
/// empty or single) run of combinators that joins it to the previous component.
/// A run of more than one combinator (`c > > d`) or a leading run (`~ ~ c`) is a
/// "bogus" but parseable selector dart-sass preserves.
class ComplexComponent {
    combinators: Combinator[],
    compound: Compound,
    /// The leading combinator when there is exactly one (the common case);
    /// `None` for a descendant join or a multi-combinator run.
    function combinator(self) -> Combinator? {
        match (self.combinators) {
            [let c] => c,
            _ => null,
        }
    }
}

/// A complex selector: a sequence of compound selectors joined by descendant
/// (whitespace) or explicit combinators, e.g. `.a > .b .c`. `trailing` holds a
/// "bogus" trailing combinator run (`c >`, `c + >`) — or, when `components` is
/// empty, a combinator-only selector (`>`) — that dart-sass preserves.
class Complex {
    components: ComplexComponent[],
    trailing: Combinator[],
    function render(self) -> string {
        let out = "";
        let i = 0;
        for (let comp in self.components) {
            if (i > 0) {
                out = out + " ";
            }
            for (let c in comp.combinators) {
                out = out + c.as_str();
                out = out + " ";
            }
            out = out + comp.compound.render();
            i += 1;
        }
        let j = 0;
        for (let c in self.trailing) {
            if (j > 0 || self.components.length() != 0) {
                out = out + " ";
            }
            out = out + c.as_str();
            j += 1;
        }
        out
    }

    function has_placeholder(self) -> bool {
        self.components.some((c: ComplexComponent) -> bool {
            c.compound.has_placeholder()
        })
    }
}

/// Whether a complex selector still contains a placeholder simple (`%foo`).
/// Lets the extend pass test a `Parsed` rule's placeholder fast-path condition
/// on the typed model, with no render.
function complex_has_placeholder(c: Complex) -> bool {
    c.has_placeholder()
}

function assert_render_injective(unused_c: Complex) -> void {
    // PORT: the `#[cfg(not(debug_assertions))]` (release) build's no-op; the
    // debug-only thread-local injectivity guard is not ported.
}

function assert_simple_render_injective(unused_s: Simple) -> void {
    // PORT: the `#[cfg(not(debug_assertions))]` (release) build's no-op; the
    // debug-only thread-local injectivity guard is not ported.
}

// mod parse → namespace `root.selector.parse`

// ---- the extend engine -------------------------------------------------
/// One registered extension: `extender` selectors should be added wherever
/// `target` (a single simple selector) is matched. `target` is `None` when the
/// extend target couldn't be parsed as a single simple selector (it then never
/// matches, but still records "not found" for the !optional check).
class Extension {
    target: Simple?,
    /// The extending selector list (the rule body containing `@extend`).
    extenders: Complex[],
    /// Source line-break flags parallel to `extenders`: an extend product
    /// that IS an extender complex inherits its flag (dart's
    /// ComplexSelector.lineBreak travels with the selector object).
    extender_breaks: bool[],
    optional: bool,
    /// Whether this extension's target was ever found in the stylesheet.
    /// Shared so scoped clones report back to the original.
    matched: root.std.Cell<bool>,
    /// The module keys this extension's origin can see (its own key plus its
    /// transitive upstreams). A chained extension (an extender that is itself
    /// extended) only links when the outer extension can see the inner one's
    /// origin (dart-sass per-module stores).
    origin: string,
    /// Global registration index (position in the evaluator's `@extend`
    /// sequence). A rule's `extend_base` splits this sequence: extensions
    /// registered before the rule apply one-shot (dart `addSelector`),
    /// later ones incrementally.
    reg_idx: int,
    /// A transitively-derived entry (dart creates these while merging a
    /// downstream store into `origin`'s): it applies only STRICTLY upstream
    /// of `origin`, and sorts after `origin`'s own raw extenders.
    derived: bool,
    /// For a derived entry, the origin of the TRIGGERING extension (the
    /// downstream store whose absorption created it) — within a home store,
    /// derived entries follow the absorption order of their trigger.
    via_origin: string?,
    // Module-origin set, built in eval (`closure_cache`); kept on std `HashSet`
    // so the FxHash migration stays scoped to this file's selector maps.
    origin_closure: map<string, bool>,
}

/// Whether any compound in any complex selector of `list` contains `target`.
function list_contains_simple(list: Complex[], target: Simple) -> bool {
    // PORT: `simples.contains(target)` → `some(== target)`: BAML's
    // `Array.includes` compares class instances by identity, not structurally.
    list.some((c: Complex) -> bool {
        c.components.some((comp: ComplexComponent) -> bool {
            comp.compound.simples.some((s: Simple) -> bool {
                s == target
            })
        })
    })
}

/// How an `@extend` target string classifies.
interface TargetClass {}

/// A valid single-simple-selector target.
class TargetClass_Simple {
    _0: Simple,
    implements TargetClass {}
}

/// `@extend a b` — complex selectors may not be extended.
class TargetClass_Complex {
    implements TargetClass {}
}

/// `@extend a.b` / `a:hover` — compound (multi-simple) selectors may no
/// longer be extended.
class TargetClass_Compound {
    implements TargetClass {}
}

/// Unparseable.
class TargetClass_Invalid {
    implements TargetClass {}
}

/// Classify an `@extend` target string (already interpolation-resolved).
function classify_target(s: string) -> TargetClass {
    let s = root.std.trim(s);
    if (s == "") {
        return TargetClass_Invalid {  };
    }
    let complex = root.selector.parse.parse_complex(s);
    if (complex == null) {
        return TargetClass_Invalid {  };
    }
    if (complex.components.length() != 1 || complex.components[0].combinator() != null) {
        return TargetClass_Complex {  };
    }
    let simples = complex.components[0].compound.simples;
    if (simples.length() != 1) {
        return TargetClass_Compound {  };
    }
    TargetClass_Simple { _0: simples[0] }
}

/// The result of running the extend engine on a selector list.
class ExtendResult {
    /// The rewritten selector list, typed. The caller (`OutNode::Rule`) carries
    /// these `Complex` values through to emit, which renders them via
    /// `Complex::render()` — byte-identical to rendering them here (Phase 1d:
    /// no string round trip between the engine and the serializer).
    selectors: Complex[],
    /// Source line-break flags parallel to `selectors`: an original keeps its
    /// input flag, a product that IS an extender complex takes the extender's
    /// flag, and woven products fall back to `false`.
    breaks: bool[],
    /// True if every component still contains a placeholder (rule should drop).
    all_placeholders: bool,
}

/// The scope-fixed derivation shared by every rule in one module `scope` with
/// one fixed `extensions` list. Building this is the expensive part — it folds
/// the whole `ExtensionStore` transitive closure (dart's `_extensions` /
/// `_extensionsByExtender` / `_sourceSpecificity`) — and the result depends ONLY
/// on `(extensions, scope)`, NOT on the per-rule selector list. dart builds its
/// store ONCE and then incrementally extends each rule's selector against it; we
/// reproduce that by computing this plan ONCE per scope (in `rewrite_nodes`) and
/// reusing it across every rule, instead of re-deriving the closure per rule
/// (the old O(rules × extensions) blow-up).
class ExtendPlan {
    /// dart `newExtensionsByTarget` per registration — the per-`@extend` batches
    /// applied by the registration-order fold.
    batches: Extension[][],
    /// The full flat extension registry incl. the transitive closure (dart
    /// `_extensions`), driving the one-shot / pseudo-self-ref worklist.
    registry: Extension[],
    /// Registry length after each input `@extend` was processed: entry `i`
    /// bounds the store visible to a rule created after registration `i`
    /// (dart `addSelector` extends a new rule by the store SO FAR).
    batch_registry_marks: int[],
    /// Each input batch's global registration index (ascending — the
    /// visible-subset filter preserves the evaluator's order).
    batch_reg_idx: int[],
    /// Each input batch's origin module key.
    batch_origin: string[],
    /// Per-origin rank in this scope's downstream store-merge flatten
    /// (dart `addExtensions` order): smaller = earlier in the merged map.
    origin_rank: map<string, int>,
    /// Legacy fold order for @import-mixed compiles: no foreign one-shot,
    /// pre-rule split ignores origins (the pre-store-merge model).
    legacy_order: bool,
    /// Store-wide source specificities (dart `_sourceSpecificity`) for `trim`.
    source_spec: map<string, int>,
    /// The visible extension count (`extensions.len()`), against which the
    /// per-rule `extend_base` is compared to choose the one-shot path. Stored so
    /// the comparison stays exactly the old `extend_base >= extensions.len()`.
    n_extensions: int,
    /// dart `single-module` flag: every extension's origin is this scope.
    single_module: bool,
    /// A self-referential pseudo chain is present (issue_2055) — routes to the
    /// single-pass batch fold rather than the registration fixpoint.
    pseudo_self_ref: bool,
    /// How many units of the shared work budget `expand_extensions` consumes
    /// while deriving the closure. The old per-rule path reset the budget then
    /// ran `expand_extensions`, so each rule's fold saw `BUDGET − this`; with
    /// the plan computed once, we replay this deduction per rule to keep the
    /// budget state — and therefore the output — byte-identical.
    expand_budget_cost: int,
    /// True when no extensions are visible in this scope (the caller's fast
    /// path: a rule with no `@extend` and no placeholder is untouched).
    function is_empty(self) -> bool {
        self.n_extensions == 0
    }
}

/// Build the scope-fixed [`ExtendPlan`] for one module `scope` and its fixed
/// `extensions` list. Call ONCE per scope; reuse across every rule.
function build_extend_plan(
    extensions: Extension[],
    scope: string,
    origin_rank: map<string, int>,
    legacy_order: bool,
) -> ExtendPlan {
    let source_spec = source_specificity_map(extensions);
    // Run the closure derivation under a fresh budget and record exactly how
    // much it consumed, so the per-rule path can replay the same deduction.
    reset_extend_budget();
    let budget_before = EXTEND_WORK().get();
    let expanded = expand_extensions(extensions);
    let raw_batches = expanded._0;
    let registry = expanded._1;
    let raw_marks = expanded._2;
    // dart applies a DOWNSTREAM module's whole store in ONE extendList
    // (`addExtensions` accumulates every store's extensions and makes a
    // single `_extendExistingSelectors` call), so same-target extenders from
    // one foreign module land in registration order (bulma's
    // `.fixed-grid`/`.grid` from grid.scss). Merge consecutive same-origin
    // FOREIGN batches into one multi-extension batch; own-scope batches stay
    // per-`@extend` (dart's incremental addExtension). A merged batch keeps
    // its FIRST member's registration index and its LAST member's registry
    // mark, so the pre-rule split and registry segments stay consistent.
    let batches: Extension[][] = [];
    let batch_registry_marks: int[] = [];
    let batch_reg_idx: int[] = [];
    let batch_origin: string[] = [];
    let last_origin: string? = null;
    let i = 0;
    for (let batch in raw_batches) {
        let origin = extensions[i].origin;
        if (origin != scope && last_origin == origin) {
            let last = root.std.expect(root.std.last(batches), "non-empty on merge");
            root.std.extend(last, batch);
            root.std.assert_true(batch_registry_marks.length() > 0, "mark");
            batch_registry_marks[batch_registry_marks.length() - 1] = raw_marks[i];
        } else {
            batches.push(batch);
            batch_registry_marks.push(raw_marks[i]);
            batch_reg_idx.push(extensions[i].reg_idx);
            batch_origin.push(extensions[i].origin);
            last_origin = origin;
        }
        i += 1;
    }
    let budget_after = EXTEND_WORK().get();
    let expand_budget_cost = root.std.saturating_sub_u(budget_before, budget_after);
    let single_module = extensions.every((e: Extension) -> bool {
        e.origin == scope
    });
    // key: `Simple::render()` (injective over simples).
    let targets: map<string, bool> = {};
    for (let e in extensions) {
        let t = e.target;
        if (t != null) {
            let _ = root.std.set_insert(targets, t.render());
        }
    }
    let pseudo_self_ref = single_module
        && registry.some((e: Extension) -> bool {
            e.extenders.some((c: Complex) -> bool {
                pseudo_arg_has_target(c, targets, false)
            })
        });
    ExtendPlan {
        batches: batches,
        registry: registry,
        batch_registry_marks: batch_registry_marks,
        batch_reg_idx: batch_reg_idx,
        batch_origin: batch_origin,
        origin_rank: origin_rank,
        legacy_order: legacy_order,
        source_spec: source_spec,
        n_extensions: extensions.length(),
        single_module: single_module,
        pseudo_self_ref: pseudo_self_ref,
        expand_budget_cost: expand_budget_cost,
    }
}

/// Apply `extensions` to the parsed selector list `original`, returning the
/// extended selector list (original selectors first, then generated ones, in
/// dart-sass order). Placeholder-only complex selectors are dropped from the
/// output.
function extend_selectors(
    original: Complex[],
    original_breaks: bool[],
    plan: ExtendPlan,
    scope: string,
    extend_base: int,
) -> ExtendResult {
    // Reset the shared work budget for this rule, then replay the deduction the
    // closure derivation would have taken if it ran here (it now ran ONCE in
    // `build_extend_plan`). This keeps the budget state — and therefore the
    // fold's truncation behaviour and output — byte-identical to the old
    // per-rule path that called `expand_extensions` after `reset_extend_budget`.
    reset_extend_budget();
    EXTEND_WORK().set(root.std.saturating_sub_u(EXTEND_WORK().get(), plan.expand_budget_cost));
    let batches = plan.batches;
    let registry = plan.registry;
    let source_spec = plan.source_spec;
    // The set of "original" rendered selectors — the unextended input. Original
    // selectors are never trimmed (dart-sass keeps them so the rule still
    // matches what it always matched). Start from the scope-wide store originals
    // (dart `_originals` — every extender written in this module, protected from
    // a broader generated one trimming it) and add the rule's own selectors.
    // dart's `_originals` is an IDENTITY set: original status travels with
    // the INSTANCE, not the value. The pipeline threads a per-entry flag
    // instead (seeded true for the rule's own selectors; the first product of
    // each original round-trip inherits it), so a product VALUE-equal to an
    // original is still coverage-trimmed in the original's favor.
    for (let complex in original) {
        assert_render_injective(complex);
    }

    // dart `addSelector` ONE-SHOT vs `_extendExistingSelectors` INCREMENTAL.
    // When a rule's selector was established AFTER every applicable `@extend`
    // (`extend_base >= extensions.len()`), dart extends it by the whole store at
    // ONCE — `_extendComplex`'s `paths` unification order (LAST choice slowest)
    // and the `:not`/`:is` merge applied simultaneously. When it was established
    // before/among its `@extend`s, dart re-extends it incrementally in
    // registration order (the opposite cartesian order, and each `:not` inserted
    // right after the target so later extends sort first). The one-shot path
    // runs the worklist over the full `registry` (transitive closure incl.
    // dart#1297 derived extensions) with the `paths`-order cartesian; the
    // incremental path is the registration-order FOLD (per-origin gating intact).
    // Gated to single-module: there the closure-size sort is stable so the index
    // equals registration order; multi-module keeps the fold. `extend_base`
    // is the GLOBAL registration counter, so "after every applicable
    // @extend" must compare against the visible extensions' own global
    // indices — not their count (a late-loaded module's rule has a large
    // base while its scope sees only a couple of extensions; bulma's
    // `.input`/`.textarea` register AFTER their placeholder rule and must
    // fold incrementally).
    // PORT: `usize::MAX` (the "no base" sentinel) is `root.std.INT_MAX()`.
    let single_module = plan.single_module;
    let order: CartesianOrder = if (
        single_module
            && extend_base != root.std.INT_MAX()
            && plan.batch_reg_idx.every((r: int) -> bool {
                r < extend_base
            })
    ) {
        CartesianOrder.OneShot
    } else {
        CartesianOrder.Fold
    };
    // A SELF-REFERENTIAL pseudo chain (issue_2055) — precomputed in the plan.
    let pseudo_self_ref = plan.pseudo_self_ref;
    let result: root.std.Tuple2<Complex, bool>[] = if (pseudo_self_ref && order == CartesianOrder.Fold) {
        // A self-referential pseudo chain (`:not(.thing[disabled])` extending
        // `.thing`, issue_2055). dart applies each `@extend`'s
        // `newExtensionsByTarget` (its single extension PLUS the
        // `additionalExtensions` derived by `_extendExistingExtensions`) to the
        // selector list EXACTLY ONCE, in registration order — the nesting depth
        // comes from `_extendPseudo` recursing into `_extendList`, NOT from
        // re-applying the whole store. Re-applying the registry as a worklist
        // over-generates (the full set cross-products every `.thing` against
        // every derived extender), and re-folding the batches to a fixpoint
        // blows up combinatorially. So: fold the batches once each, faithful to
        // dart's single registration-order pass.
        let current: root.std.Tuple4<Complex, bool, bool, string>[] = baml.Array.generate(original.length(), (i: int) -> root.std.Tuple4<Complex, bool, bool, string> {
            root.std.Tuple4 {
                _0: original[i],
                _1: original_breaks.at(i) ?? false,
                _2: true,
                _3: scope,
            }
        });
        // OPT 1 (single registration-order pass): skip a batch none of whose
        // targets the running list can match — a no-op, budget-neutral batch.
        // key: `Simple::render()`.
        let current_simples: map<string, bool> = {};
        for (let entry in current) {
            collect_match_simples(entry._0, current_simples);
        }
        for (let batch in batches) {
            let any = false;
            for (let e in batch) {
                let t = e.target;
                if (t != null) {
                    if (current_simples.has(t.render())) {
                        any = true;
                        break;
                    }
                }
            }
            if (!any) {
                continue;
            }
            current = extend_list_batch(current, batch, scope, source_spec);
            for (let entry in current) {
                collect_match_simples(entry._0, current_simples);
            }
        }
        current.map((entry: root.std.Tuple4<Complex, bool, bool, string>) -> root.std.Tuple2<Complex, bool> {
            root.std.Tuple2 { _0: entry._0, _1: entry._1 }
        })
    } else if (order == CartesianOrder.OneShot) {
        let all_orig: bool[] = baml.Array.filled(original.length(), true);
        let extended = extend_to_fixpoint_breaks(original, original_breaks, all_orig, scope, registry, order);
        let result = extended._0;
        let changed = extended._1;
        if (changed) {
            trim_breaks(result, source_spec).map((entry: root.std.Tuple3<Complex, bool, bool>) -> root.std.Tuple2<Complex, bool> {
                root.std.Tuple2 { _0: entry._0, _1: entry._1 }
            })
        } else {
            baml.Array.generate(original.length(), (i: int) -> root.std.Tuple2<Complex, bool> {
                root.std.Tuple2 { _0: original[i], _1: original_breaks.at(i) ?? false }
            })
        }
    } else {
        // Faithful dart registration-order: apply the batch sequence (one
        // `@extend` worth of new extensions per batch) to a FIXPOINT. One pass
        // establishes dart's order; later passes pick up transitive products a
        // single pass can't reach (extend cycles `.foo→.bar→.baz→.foo`). Each
        // selector carries the module origin that owns it, and a batch only
        // extends a selector it can SEE (per-module gating blocks cross-sibling
        // diamond leaks). New products append after the established order and
        // `trim` drops any a kept selector covers, so order is preserved and
        // spurious blow-ups are pruned; the shared work budget bounds growth.
        // dart `addSelector`: extensions registered BEFORE this rule was
        // created apply as ONE `extendList` over the store-so-far (their
        // products in extension-registration order — govuk's
        // `.govuk-body-l, .govuk-body-lead` aliases); only LATER
        // registrations re-extend the rule incrementally. Gated to a single
        // module, where `extend_base` indexes the registration sequence.
        // The batch list is ordered downstream-first (not registration
        // order), so the pre-rule set is NOT a prefix: collect the batches
        // whose registration index precedes the rule, in registration order,
        // and splice their registry segments for the one-shot store.
        // Foreign (downstream-module) stores never fold incrementally: dart
        // merges every downstream store transitively and applies the result
        // in ONE `extendList` per upstream module at combine time. Entry
        // order mirrors the merged map: each origin at its rank in the
        // scope's store-merge flatten (plan.origin_rank), raw extenders
        // before that origin's DERIVED entries, registration order within.
        // A derived entry created AT this scope is excluded (it exists for
        // strictly-upstream merges; the chain resolves here through the
        // already-extended selector list instead).
        let foreign: int[] = if (plan.legacy_order) {
            []
        } else {
            root.std.range(0, batches.length()).filter((i: int) -> bool {
                let o = plan.batch_origin.at(i);
                if (o != null) {
                    o != scope
                } else {
                    false
                }
            })
        };
        let pre_batches: int[] = if (extend_base != root.std.INT_MAX() && extend_base > 0) {
            let v: int[] = root.std.range(0, batches.length()).filter((i: int) -> bool {
                (plan.legacy_order || plan.batch_origin.at(i) == scope)
                    && (plan.batch_reg_idx.at(i) ?? root.std.INT_MAX()) < extend_base
            });
            let _ = v.sort_by_key((i: int) -> int {
                plan.batch_reg_idx[i]
            });
            v
        } else {
            []
        };
        // key: the batch index's `to_string()`.
        let pre_set: map<string, bool> = {};
        for (let i in pre_batches) {
            let _ = root.std.set_insert(pre_set, i.to_string());
        }
        for (let i in foreign) {
            let _ = root.std.set_insert(pre_set, i.to_string());
        }
        let seed: root.std.Tuple3<Complex, bool, bool>[] = if (pre_batches.length() != 0) {
            // The one-shot store is the concatenation of these batches' registry
            // slices. `pre_batches` is sorted by registry position, so those
            // slices are usually adjacent, and then the concatenation *is* a
            // subslice of `registry` -- borrow it rather than cloning every
            // `Extension` in it. Cloning unconditionally is a copy of the whole
            // registry prefix per extending rule, which is where an
            // `@extend`-heavy sheet's allocation went.
            // PORT: a `start..end` range is a `Tuple2 { _0: start, _1: end }`.
            let batch_range = (i: int) -> root.std.Tuple2<int, int> {
                let start = if (i == 0) {
                    0
                } else {
                    plan.batch_registry_marks[i - 1]
                };
                root.std.Tuple2 { _0: start, _1: plan.batch_registry_marks[i] }
            };
            let lo = 0;
            let hi = 0;
            let contiguous = true;
            let k = 0;
            for (let i in pre_batches) {
                let range = batch_range(i);
                if (k == 0) {
                    lo = range._0;
                } else if (range._0 != hi) {
                    // A gap, or out of order: the union is not itself a slice.
                    contiguous = false;
                    break;
                }
                hi = range._1;
                k += 1;
            }
            // PORT: `Cow<[Extension]>` → the slice copy (the `Extension`s are
            // shared, as the borrowed/cloned-with-shared-cells Rust entries are).
            let one_shot_store: Extension[] = if (contiguous) {
                registry.slice(lo, hi)
            } else {
                pre_batches.flat_map((i: int) -> Extension[] {
                    let range = batch_range(i);
                    registry.slice(range._0, range._1)
                })
            };
            let all_orig: bool[] = baml.Array.filled(original.length(), true);
            let extended = extend_to_fixpoint_breaks(original, original_breaks, all_orig, scope, one_shot_store, CartesianOrder.OneShot);
            let res = extended._0;
            let changed = extended._1;
            if (changed) {
                trim_breaks(res, source_spec)
            } else {
                baml.Array.generate(original.length(), (i: int) -> root.std.Tuple3<Complex, bool, bool> {
                    root.std.Tuple3 {
                        _0: original[i],
                        _1: original_breaks.at(i) ?? false,
                        _2: true,
                    }
                })
            }
        } else {
            baml.Array.generate(original.length(), (i: int) -> root.std.Tuple3<Complex, bool, bool> {
                root.std.Tuple3 { _0: original[i], _1: original_breaks.at(i) ?? false, _2: true }
            })
        };
        let current: root.std.Tuple4<Complex, bool, bool, string>[] = seed.map((entry: root.std.Tuple3<Complex, bool, bool>) -> root.std.Tuple4<Complex, bool, bool, string> {
            root.std.Tuple4 { _0: entry._0, _1: entry._1, _2: entry._2, _3: scope }
        });
        // OPT 1: the set `S` of simples the running list can match against —
        // exactly those `s` for which some complex `complex_may_match_targets`
        // `{s}`. A batch ALL of whose targets are absent from `S` changes
        // nothing AND consumes zero budget (the `can_match` gate fires before
        // `consume_extend_work`), so it can be skipped entirely — byte-exact.
        // Maintained INCREMENTALLY: only an applied batch mutates `current`, so
        // its products' simples are unioned in; skipped batches leave `S` alone.
        // key: `Simple::render()`.
        let current_simples: map<string, bool> = {};
        for (let entry in current) {
            collect_match_simples(entry._0, current_simples);
        }
        // dart's incremental path is ONE `_extendList` per registration —
        // never a fixpoint. Chains across registrations are precomputed as
        // DERIVED extensions (including the live-list self-derivation above),
        // so re-running the batches would only conjure products dart never
        // emits (tabler: `body[data-bs-theme=dark] [data-bs-theme=light]`
        // chained through its sibling extender of the SAME rule).
        {
            for (let bi in baml.iter.Range.new(0, batches.length())) {
                let batch = batches[bi];
                if (pre_set.has(bi.to_string())) {
                    continue;
                }
                // Skip a batch none of whose targets the running list can match.
                let any = false;
                for (let e in batch) {
                    let t = e.target;
                    if (t != null) {
                        if (current_simples.has(t.render())) {
                            any = true;
                            break;
                        }
                    }
                }
                if (!any) {
                    continue;
                }
                let next = extend_list_batch(current, batch, scope, source_spec);
                // Union the (possibly new) products' simples into `S`. Only an
                // applied batch reaches here; recomputing from scratch per batch
                // would defeat the win, so fold incrementally.
                for (let entry in next) {
                    collect_match_simples(entry._0, current_simples);
                }
                current = next;
            }
        };
        // Satisfaction snapshot (dart's `originalSelectors`): a foreign
        // extension counts as matched only against selectors present BEFORE
        // this merge — a product added by a SIBLING store in the same merge
        // must not satisfy it (use/error/extend scope/diamond).
        let pre_foreign_snapshot: Complex[] = if (foreign.length() == 0) {
            []
        } else {
            current.map((entry: root.std.Tuple4<Complex, bool, bool, string>) -> Complex {
                entry._0
            })
        };
        if (foreign.length() != 0) {
            let foreign_entries: Extension[] = registry.filter((e: Extension) -> bool {
                e.origin != scope
            });
            let _ = foreign_entries.sort_by((a: Extension, b: Extension) -> baml.ops.Ordering {
                let rank = (e: Extension) -> int {
                    plan.origin_rank.get(e.origin) ?? root.std.INT_MAX()
                };
                // Within a home store, derived entries follow the absorption
                // order of their TRIGGERING store (the via origin's rank),
                // not registration order.
                let via_rank = (e: Extension) -> int {
                    let o = e.via_origin;
                    (
                        if (o != null) {
                            plan.origin_rank.get(o)
                        } else {
                            null
                        }
                    )
                        ?? root.std.INT_MAX()
                };
                // PORT: `Ordering::then` chain → fall through while `Equal`
                // (`bool` orders `false < true`).
                let ord = rank(a).cmp(rank(b));
                if (ord == baml.ops.Ordering.Equal) {
                    let da: int = if (a.derived) {
                        1
                    } else {
                        0
                    };
                    let db: int = if (b.derived) {
                        1
                    } else {
                        0
                    };
                    ord = da.cmp(db);
                }
                if (ord == baml.ops.Ordering.Equal) {
                    ord = via_rank(a).cmp(via_rank(b));
                }
                if (ord == baml.ops.Ordering.Equal) {
                    ord = a.reg_idx.cmp(b.reg_idx);
                }
                ord
            });
            let foreign_store: Extension[] = foreign_entries;
            let complexes: Complex[] = current.map((entry: root.std.Tuple4<Complex, bool, bool, string>) -> Complex {
                entry._0
            });
            let breaks: bool[] = current.map((entry: root.std.Tuple4<Complex, bool, bool, string>) -> bool {
                entry._1
            });
            let origs: bool[] = current.map((entry: root.std.Tuple4<Complex, bool, bool, string>) -> bool {
                entry._2
            });
            let extended = extend_to_fixpoint_breaks(complexes, breaks, origs, scope, foreign_store, CartesianOrder.OneShot);
            let res = extended._0;
            let changed = extended._1;
            if (changed) {
                current
                    = trim_breaks(res, source_spec).map((
                        entry: root.std.Tuple3<Complex, bool, bool>,
                    ) -> root.std.Tuple4<Complex, bool, bool, string> {
                        root.std.Tuple4 { _0: entry._0, _1: entry._1, _2: entry._2, _3: scope }
                    });
            }
        }
        // Mandatory-extend accounting for batches the fold never runs (the
        // pre-rule one-shot and the foreign one-shot use registry segments,
        // so a target-only MARKER — or an extension merged into an earlier
        // identical registration — never reaches collect_extenders): flip
        // its matched cell whenever the target appears in this rule's list
        // (dart tracks "found" via _selectors[target], independent of
        // application).
        let accounting: root.std.Tuple2<int, Complex[]>[] = pre_batches
            .map((i: int) -> root.std.Tuple2<int, Complex[]> {
                root.std.Tuple2 { _0: i, _1: original }
            })
            .concat(
                foreign.map((i: int) -> root.std.Tuple2<int, Complex[]> {
                    root.std.Tuple2 { _0: i, _1: pre_foreign_snapshot }
                }),
            );
        for (let pair in accounting) {
            let i = pair._0;
            let snapshot = pair._1;
            for (let e in batches[i]) {
                if (e.matched.get()) {
                    continue;
                }
                let t = e.target;
                if (t != null) {
                    if (list_contains_simple(snapshot, t)) {
                        e.matched.set(true);
                    }
                }
            }
        }
        current.map((entry: root.std.Tuple4<Complex, bool, bool, string>) -> root.std.Tuple2<Complex, bool> {
            root.std.Tuple2 { _0: entry._0, _1: entry._1 }
        })
    };

    // Simplify placeholders inside `:is()/:where()/:not()`-style pseudo
    // arguments, dropping selectors whose pseudo can never match.
    let simplified: root.std.Tuple2<Complex, bool>[] = [];
    for (let entry in result) {
        let c = simplify_pseudo_placeholders(entry._0);
        if (c != null) {
            simplified.push(root.std.Tuple2 { _0: c, _1: entry._1 });
        }
    }

    // Drop complex selectors that still contain a (top-level) placeholder.
    // Each product's line-break flag traveled through the pipeline (dart's
    // `complex.lineBreak || path.any((c) => c.lineBreak)`).
    let all_placeholders = simplified.every((entry: root.std.Tuple2<Complex, bool>) -> bool {
        entry._0.has_placeholder()
    });
    let selectors: Complex[] = [];
    let breaks: bool[] = [];
    for (let entry in simplified) {
        if (!entry._0.has_placeholder()) {
            selectors.push(entry._0);
            breaks.push(entry._1);
        }
    }
    ExtendResult { selectors: selectors, breaks: breaks, all_placeholders: all_placeholders }
}

/// Simplify placeholder selectors inside pseudo-class arguments
/// (`:is()`/`:where()`/`:matches()`/`:not()` etc.): remove placeholder complex
/// selectors from the argument list. For "matches-any" pseudos an empty
/// argument means the whole compound matches nothing (return `None` to drop the
/// selector); for `:not()` an empty argument means the pseudo excludes nothing
/// and is removed (a now-empty compound becomes `*`). Returns the rewritten
/// complex selector, or `None` if it can never match.
function simplify_pseudo_placeholders(complex: Complex) -> Complex? {
    let components: ComplexComponent[] = [];
    for (let comp in complex.components) {
        let simples: Simple[] = [];
        for (let s in comp.compound.simples) {
            match (s) {
                Simple_Pseudo { _0: let text } if text.includes("%") => {
                    match (simplify_one_pseudo(text)) {
                        PseudoResult_Keep { _0: let new } => {
                            simples.push(Simple_Pseudo { _0: new });
                        },
                        PseudoResult_Remove {} => {
                            /* `:not()` with empty arg */
                        },
                        PseudoResult_NeverMatches {} => {
                            return null;
                        },
                        _ => root.std.unreachable(),
                    }
                },
                let other => {
                    simples.push(other);
                },
            }
        }
        // A compound emptied by removing a `:not()` becomes the universal `*`.
        if (simples.length() == 0) {
            simples.push(Simple_Universal { ns: null });
        }
        components.push(
            ComplexComponent {
                combinators: root.std.clone_vec(comp.combinators),
                compound: Compound { simples: simples },
            },
        );
    }
    Complex { components: components, trailing: [] }
}

interface PseudoResult {}

/// Keep the pseudo, rewritten to this text.
class PseudoResult_Keep {
    _0: string,
    implements PseudoResult {}
}

/// Remove the pseudo entirely (e.g. `:not()` with no remaining args).
class PseudoResult_Remove {
    implements PseudoResult {}
}

/// The pseudo can never match — drop the whole selector.
class PseudoResult_NeverMatches {
    implements PseudoResult {}
}

/// Simplify a single pseudo selector text whose argument contains a
/// `%placeholder`. Only `:is/:where/:matches/:any/:-*-any/:not` take a selector
/// argument we process; others are kept verbatim.
function simplify_one_pseudo(text: string) -> PseudoResult {
    // Split into `:name(` ... `)`.
    let open = text.index_of("(");
    if (open == null) {
        return PseudoResult_Keep { _0: text };
    }
    if (!text.ends_with(")")) {
        return PseudoResult_Keep { _0: text };
    }
    let head = text.slice(0, open); // e.g. `:not`
    let arg = text.slice(open + 1, text.length() - 1);
    let name = root.std.ascii_lower(root.std.trim_start_matches(head, ":"));
    // `:has()` joins the matches-any set: dart's serializer drops invisible
    // (placeholder) complexes from EVERY pseudo's argument list, and a
    // fully-invisible argument makes the pseudo — and its compound — never
    // match (issue_1797 `div:has(%not)` extends to `div:has(.not)`).
    let is_matchish = (
        match (unvendor(name)) {
            "is" | "where" | "matches" | "any" | "has" => true,
            _ => false,
        }
    )
        || name.ends_with("-any");
    let is_not = unvendor(name) == "not";
    if (!is_matchish && !is_not) {
        return PseudoResult_Keep { _0: text };
    }
    // Parse the argument selector list and drop placeholder-bearing complexes.
    let list = root.selector.parse.parse_list(arg);
    if (list == null) {
        return PseudoResult_Keep { _0: text };
    }
    let kept = list.filter((c: Complex) -> bool {
        !c.has_placeholder()
    });
    if (kept.length() == 0) {
        let r: PseudoResult = if (is_not) {
            PseudoResult_Remove {  }
        } else {
            PseudoResult_NeverMatches {  }
        };
        return r;
    }
    let inner = root.std.join(
        kept.map((c: Complex) -> string {
            c.render()
        }),
        ", ",
    );
    PseudoResult_Keep { _0: `${head}(${inner})` }
}

/// `_trim`'s "originals are never trimmed" membership WITHOUT cloning the
/// Remove complex selectors that are subselectors of another in the list,
/// preserving original selectors. Mirrors dart-sass `ExtensionStore._trim`:
/// iterate last-to-first, dropping a selector when an already-kept (or
/// later-in-input) selector is its superselector. Originals are always kept.
/// [`trim_breaks`] over bare complexes tagged with per-entry ORIGINAL flags.
function trim(
    selectors: root.std.Tuple2<Complex, bool>[],
    source_spec: map<string, int>, /* key: Simple */
) -> Complex[] {
    trim_breaks(
        selectors.map((t: root.std.Tuple2<Complex, bool>) -> root.std.Tuple3<Complex, bool, bool> {
            root.std.Tuple3 { _0: t._0, _1: false, _2: t._1 }
        }),
        source_spec,
    )
        .map((t: root.std.Tuple3<Complex, bool, bool>) -> Complex {
            t._0
        })
}

/// Like [`trim`], preserving each selector's line-break flag. Entries carry
/// (complex, line-break, is-original-INSTANCE): dart's `_originals` is a
/// `Set.identity()`, so an extension product that is VALUE-equal to one of
/// the rule's original selectors is NOT an original — it falls through to
/// the superselector coverage check, is covered by the original instance,
/// and drops, leaving the original at its own position with its own
/// line-break flag (tabler `.btn-sm,\n.btn-group-sm > .btn`).
function trim_breaks(
    selectors: root.std.Tuple3<Complex, bool, bool>[],
    source_spec: map<string, int>, /* key: Simple */
) -> root.std.Tuple3<Complex, bool, bool>[] {
    // Quadratic; dart-sass bails above 100 to avoid pathological cost.
    if (selectors.length() > 100) {
        return selectors;
    }
    // dart `_sourceSpecificityFor`: a compound's source specificity is the
    // max recorded for any of its simples (0 when none was an extender).
    // key: `Simple::render()`.
    let source_spec_for = (c: Complex) -> int {
        c.components
            .map((comp: ComplexComponent) -> int {
                comp.compound.simples
                    .map((s: Simple) -> int {
                        source_spec.get(s.render()) ?? 0
                    })
                    .reduce(
                        (a: int, b: int) -> int {
                            root.std.imax(a, b)
                        },
                        0,
                    )
            })
            .reduce(
                (a: int, b: int) -> int {
                    root.std.imax(a, b)
                },
                0,
            )
    };
    let result: root.std.Tuple3<Complex, bool, bool>[] = [];
    let num_originals = 0;
    let n = selectors.length();
    // PORT: `'outer: for i in (0..n).rev()` → a descending `while`; the
    // `continue 'outer` from the inner scan sets `rotated`.
    let i = n;
    while (i > 0) {
        i -= 1;
        let c1 = selectors[i]._0;
        let f1 = selectors[i]._1;
        let o1 = selectors[i]._2;
        if (o1) {
            // A duplicate original rotates to the front (dart `rotateSlice`),
            // preserving the EARLIEST source position's precedence.
            let rotated = false;
            let j = 0;
            while (j < num_originals) {
                if (result[j]._0 == c1) {
                    let c = root.std.unwrap(result.remove_at(j));
                    result.insert(c, 0);
                    rotated = true;
                    break;
                }
                j += 1;
            }
            if (rotated) {
                continue;
            }
            num_originals += 1;
            result.insert(root.std.Tuple3 { _0: c1, _1: f1, _2: true }, 0);
            continue;
        }
        // Drop c1 only when a superselector ALSO has at least the max source
        // specificity of c1's extenders (dart `_trim`): `.test-case` (1000)
        // may not trim `.test-case:active` whose source weighs 2000.
        let max_spec = source_spec_for(c1);
        let covers = (c2: Complex) -> bool {
            complex_specificity(c2) >= max_spec && complex_is_superselector(c2, c1)
        };
        if (
            result.some((t: root.std.Tuple3<Complex, bool, bool>) -> bool {
                covers(t._0)
            })
                || selectors.slice(0, i).some((t: root.std.Tuple3<Complex, bool, bool>) -> bool {
                    covers(t._0)
                })
        ) {
            continue;
        }
        result.insert(root.std.Tuple3 { _0: c1, _1: f1, _2: false }, 0);
    }
    result
}

// ---- superselector checks ---------------------------------------------
/// Whether `c1` is a superselector of `c2` (matches every element `c2` does).
/// dart-sass `ComplexSelector.isSuperselector`: selectors with leading
/// combinators are neither super- nor subselectors; trailing runs are handled
/// inside [`complex_is_superselector_trailing`].
function complex_is_superselector(c1: Complex, c2: Complex) -> bool {
    let d1 = to_dart(c1);
    let d2 = to_dart(c2);
    d1.leading.length() == 0
        && d2.leading.length() == 0
        && complex_is_superselector_trailing(d1.comps, d2.comps)
}

/// dart-sass `complexIsSuperselector` over trailing-combinator component lists.
function complex_is_superselector_trailing(complex1: TComp[], complex2: TComp[]) -> bool {
    // Selectors with trailing operators are neither super- nor subselectors.
    let last1 = root.std.last(complex1);
    if (
        if (last1 != null) {
            last1.combinators.length() != 0
        } else {
            true
        }
    ) {
        return false;
    }
    let last2 = root.std.last(complex2);
    if (
        if (last2 != null) {
            last2.combinators.length() != 0
        } else {
            true
        }
    ) {
        return false;
    }

    let i1 = 0;
    let i2 = 0;
    let previous_combinator: Combinator? = null;
    while (true) {
        let remaining1 = complex1.length() - i1;
        let remaining2 = complex2.length() - i2;
        if (remaining1 == 0 || remaining2 == 0) {
            return false;
        }
        if (remaining1 > remaining2) {
            return false;
        }
        let component1 = complex1[i1];
        if (component1.combinators.length() > 1) {
            return false;
        }
        if (remaining1 == 1) {
            let parents = complex2.slice(i2, complex2.length() - 1);
            if (
                parents.some((p: TComp) -> bool {
                    p.combinators.length() > 1
                })
            ) {
                return false;
            }
            let last2 = root.std.last(complex2);
            if (last2 == null) {
                return false;
            }
            return compound_is_superselector(component1.compound, last2.compound, parents);
        }

        // Find the first index `end` in complex2 whose compound is a subselector
        // of component1's compound.
        let end = i2;
        while (true) {
            let component2 = complex2[end];
            if (component2.combinators.length() > 1) {
                return false;
            }
            if (compound_is_superselector(component1.compound, component2.compound, [])) {
                break;
            }
            end += 1;
            if (end == complex2.length() - 1) {
                return false;
            }
        }

        // Intervening components (between i2 and end) must be compatible with the
        // previous combinator.
        if (!compatible_with_previous_combinator(previous_combinator, complex2.slice(i2, end))) {
            return false;
        }

        let component2 = complex2[end];
        let combinator1 = component1.combinators.at(0);
        let combinator2 = component2.combinators.at(0);
        if (!is_supercombinator(combinator1, combinator2)) {
            return false;
        }

        i1 += 1;
        i2 = end + 1;
        previous_combinator = combinator1;

        if (complex1.length() - i1 == 1) {
            match (combinator1) {
                Combinator.FollowingSibling => {
                    // `.foo ~ .bar` only supersedes selectors whose intervening
                    // combinators are all subcombinators of `~`.
                    let upto = complex2.length() - 1;
                    if (
                        !complex2.slice(i2, upto).every((c: TComp) -> bool {
                            is_supercombinator(combinator1, c.combinators.at(0))
                        })
                    ) {
                        return false;
                    }
                },
                let c: Combinator if complex2.length() - i2 > 1 => {
                    return false;
                },
                _ => {},
            }
        }
    }
}

function compatible_with_previous_combinator(previous: Combinator?, parents: TComp[]) -> bool {
    if (parents.length() == 0) {
        return true;
    }
    if (previous == null) {
        return true;
    }
    let prev = previous;
    // The child and next-sibling combinators require the *immediate* following
    // component be a superselector.
    if (prev != Combinator.FollowingSibling) {
        return false;
    }
    // The following-sibling combinator allows intermediate components, but only
    // if they're all siblings.
    parents.every((c: TComp) -> bool {
        let first = c.combinators.at(0);
        first == Combinator.FollowingSibling || first == Combinator.NextSibling
    })
}

/// Whether `combinator1` is a supercombinator of `combinator2`.
function is_supercombinator(c1: Combinator?, c2: Combinator?) -> bool {
    c1 == c2
        || (c1 == null && c2 == Combinator.Child)
        || (c1 == Combinator.FollowingSibling && c2 == Combinator.NextSibling)
}

/// Parse a selector pseudo `:name(<selectors>)` of the `:is`/`:matches`/`:any`/
/// `:where`/`:-*-any`/`:has`/`:host`/`:host-context` family into its normalized
/// name and argument selector list. `None` for any other (or non-selector) pseudo.
/// Canonicalize the selector argument of a `:not`/`:is`/`:where`/`:matches`/
/// `:any`/`:has` pseudo by re-parsing and re-rendering it (recursively
/// normalizing nested attributes and pseudos). `None` leaves it verbatim.
function normalize_pseudo_arg(text: string) -> string? {
    let open = text.index_of("(");
    if (open == null) {
        return null;
    }
    if (!text.ends_with(")")) {
        return null;
    }
    let head = text.slice(0, open);
    let name_l = root.std.ascii_lower(root.std.trim_start_matches(head, ":"));
    let known = (
        match (unvendor(name_l)) {
            "not" | "is" | "where" | "matches" | "any" | "has" => true,
            _ => false,
        }
    )
        || name_l.ends_with("-any");
    if (!known) {
        return null;
    }
    let raw = text.slice(open + 1, text.length() - 1);
    let list = root.selector.parse.parse_list(raw);
    if (list == null) {
        return null;
    }
    // Keep the source's per-arg line structure: an arg that began on its own
    // line (dart: the arg complex's lineBreak) re-joins with ",\n" — the
    // serializer honors line breaks inside pseudo args too (quasar's
    // `:is(:-webkit-autofill,\n[type=color], …)`).
    let part_breaks: bool[] = [];
    {
        let paren = 0;
        let bracket = 0;
        let leading = true;
        let brk = false;
        for (let ch in raw.chars()) {
            match (ch) {
                "(" => {
                    paren += 1;
                },
                ")" => {
                    paren -= 1;
                },
                "[" => {
                    bracket += 1;
                },
                "]" => {
                    bracket -= 1;
                },
                "," if paren == 0 && bracket == 0 => {
                    part_breaks.push(brk);
                    leading = true;
                    brk = false;
                    continue;
                },
                _ => {},
            }
            if (leading) {
                if (ch == "\n") {
                    brk = true;
                } else if (!ch.is_whitespace()) {
                    leading = false;
                }
            }
        }
        part_breaks.push(brk);
    };
    let inner = root.std.StrBuf.new();
    let i = 0;
    for (let c in list) {
        if (i > 0) {
            inner.push(",");
            inner.push(
                if (part_breaks.at(i) ?? false) {
                    "\n"
                } else {
                    " "
                },
            );
        }
        inner.push_str(c.render());
        i += 1;
    }
    `${head}(${inner.as_str()})`
}

function parse_selector_pseudo(text: string) -> root.std.Tuple2<string, Complex[]>? {
    let open = text.index_of("(");
    if (open == null) {
        return null;
    }
    if (!text.ends_with(")")) {
        return null;
    }
    let name = root.std.ascii_lower(root.std.trim_start_matches(text.slice(0, open), ":"));
    let known = (
        match (unvendor(name)) {
            "is" | "where" | "matches" | "any" | "has" | "host" | "host-context" => true,
            _ => false,
        }
    )
        || name.ends_with("-any");
    if (!known) {
        return null;
    }
    let list = root.selector.parse.parse_list(text.slice(open + 1, text.length() - 1));
    if (list == null) {
        return null;
    }
    root.std.Tuple2 { _0: name, _1: list }
}

/// dart-sass `_selectorPseudoIsSuperselector`. A selector pseudo on the super
/// side matches if `compound2` carries a same-name selector pseudo whose
/// argument our list supersedes, OR (for the `:is`/`:matches`/`:any`/`:where`/
/// `:-*-any` family) one of our argument complexes is a superselector of
/// `parents` followed by `compound2`. The relational `:has`/`:host`/
/// `:host-context` use only the same-name rule.
function selector_pseudo_is_super(
    name: string,
    branches: Complex[],
    b: Compound,
    parents: TComp[],
) -> bool {
    for (let s in b.simples) {
        if let t: Simple_Pseudo = s {
            let parsed = parse_selector_pseudo(t._0);
            if (parsed != null) {
                let n2 = parsed._0;
                let b_branches = parsed._1;
                // Our list must supersede EVERY branch of `b`'s same-name pseudo:
                // `:is(c)` is NOT a superselector of `:is(c, d)` (it can't match
                // the `d` branch), but `:is(c, d)` IS of `:is(c)`.
                if (
                    n2 == name
                        && b_branches.length() != 0
                        && b_branches.every((s2: Complex) -> bool {
                            list_is_superselector(branches, [s2])
                        })
                ) {
                    return true;
                }
            }
        }
    }
    let matchish = (
        match (unvendor(name)) {
            "is" | "where" | "matches" | "any" => true,
            _ => false,
        }
    )
        || name.ends_with("-any");
    if (!matchish) {
        return false;
    }
    branches.some((branch: Complex) -> bool {
        // dart-sass: a branch with leading combinators is never a superselector.
        let bd = to_dart(branch);
        if (bd.leading.length() != 0) {
            return false;
        }
        let target: TComp[] = root.std.clone_vec(parents);
        target.push(TComp { compound: b, combinators: [] });
        complex_is_superselector_trailing(bd.comps, target)
    })
}

/// Parse a `:not(...)` (or vendor-prefixed `:-pfx-not(...)`) selector pseudo
/// into its (full) name and argument list.
function parse_not_pseudo(text: string) -> root.std.Tuple2<string, Complex[]>? {
    let open = text.index_of("(");
    if (open == null) {
        return null;
    }
    if (!text.ends_with(")")) {
        return null;
    }
    let name = root.std.ascii_lower(root.std.trim_start_matches(text.slice(0, open), ":"));
    if (unvendor(name) != "not") {
        return null;
    }
    let list = root.selector.parse.parse_list(text.slice(open + 1, text.length() - 1));
    if (list == null) {
        return null;
    }
    root.std.Tuple2 { _0: name, _1: list }
}

/// dart-sass `:not(S1)` superselector rule (contravariant): `:not(S1)` is a
/// superselector of compound `b` iff every complex in `S1` is *excluded* by
/// some simple of `b` — a type/id with a different name (so `b` can never match
/// that complex), or a same-(full-)name `:not(S2)` whose `S2` supersedes the
/// complex.
function not_pseudo_is_super(name: string, branches: Complex[], b: Compound) -> bool {
    branches.every((complex1: Complex) -> bool {
        b.simples.some((simple2: Simple) -> bool {
            not_excludes(complex1, simple2, name)
        })
    })
}

function not_excludes(complex1: Complex, simple2: Simple, not_name: string) -> bool {
    let last = root.std.last(complex1.components);
    let last_simples = () -> Simple[] {
        let l = last;
        if (l != null) {
            l.compound.simples
        } else {
            []
        }
    };
    match (simple2) {
        Simple_Type { _0: let t2 } => {
            let n2 = type_local_name(t2);
            last_simples().some((s: Simple) -> bool {
                match (s) {
                    Simple_Type { _0: let t1 } if type_local_name(t1) != n2 => true,
                    _ => false,
                }
            })
        },
        Simple_Id { _0: let id2 } => {
            last_simples().some((s: Simple) -> bool {
                match (s) {
                    Simple_Id { _0: let id1 } if id1 != id2 => true,
                    _ => false,
                }
            })
        },
        Simple_Pseudo { _0: let t2 } => {
            let parsed = parse_not_pseudo(t2);
            if (parsed != null) {
                parsed._0 == not_name && list_is_superselector(parsed._1, [complex1])
            } else {
                false
            }
        },
        _ => false,
    }
}

/// The local (namespace-stripped) name of a type selector string.
function type_local_name(t: string) -> string {
    // `t.rsplit('|').next().unwrap_or(t)`: the text after the last `|`.
    root.std.last(t.split("|")) ?? t
}

/// Whether compound `a` is a superselector of compound `b` (dart-sass
/// `compoundIsSuperselector`). A pseudo-element effectively changes the target
/// of a compound rather than narrowing it, so if either compound has a
/// pseudo-element they must both have the *same* one (with matching simples on
/// each side of it). `parents` are the components of `b`'s complex that precede
/// its final compound, used by the `:is`-family selector-pseudo rule.
function compound_is_superselector(a: Compound, b: Compound, parents: TComp[]) -> bool {
    // PORT: `match (find_pseudo_element(a), find_pseudo_element(b))` → if/else chain.
    let pa = find_pseudo_element(a);
    let pb = find_pseudo_element(b);
    if (pa != null && pb != null) {
        let pe1 = pa._0;
        let i1 = pa._1;
        let pe2 = pb._0;
        let i2 = pb._1;
        pseudo_element_is_superselector(pe1, pe2)
            && compound_components_is_superselector(a.simples.slice(0, i1), b.simples.slice(0, i2))
            && compound_components_is_superselector(
                a.simples.slice(i1 + 1, a.simples.length()),
                b.simples.slice(i2 + 1, b.simples.length()),
            )
    } else if (pa != null || pb != null) {
        // Exactly one side has a pseudo-element: never a superselector.
        false
    } else {
        a.simples.every((s1: Simple) -> bool {
            // A selector pseudo (`:is(...)` etc.) follows the dart-sass pseudo
            // rule; every other simple must match some simple of `b`.
            if let p1: Simple_Pseudo = s1 {
                let text = p1._0;
                let sel = parse_selector_pseudo(text);
                if (sel != null) {
                    return selector_pseudo_is_super(sel._0, sel._1, b, parents);
                }
                // `:not(S1)` uses its own contravariant superselector rule.
                let not_sel = parse_not_pseudo(text);
                if (not_sel != null) {
                    return not_pseudo_is_super(not_sel._0, not_sel._1, b);
                }
                // `:nth-child(An+B of S1)`/`:nth-last-child(...)` (possibly
                // vendor-prefixed) match a same-named pseudo in `b` with the
                // same An+B whose `of` list is a subselector (dart-sass
                // `_selectorPseudoIsSuperselector`).
                let nth = nth_selector_parts(text);
                if (nth != null) {
                    return nth_pseudo_is_super(nth._0, nth._1, nth._2, b);
                }
            }
            b.simples.some((s2: Simple) -> bool {
                simple_is_superselector(s1, s2)
            })
        })
    }
}

/// Whether pseudo-element `pe1` is a superselector of pseudo-element `pe2`
/// (dart-sass `PseudoSelector.isSuperselector`): they are equal, or both are a
/// same-named `::slotted(...)` whose selector arguments compare as lists.
function pseudo_element_is_superselector(pe1: Simple, pe2: Simple) -> bool {
    if (pe1 == pe2) {
        return true;
    }
    let t1 = match (pe1) {
        Simple_Pseudo { _0: let t } => t,
        _ => null,
    };
    let t2 = match (pe2) {
        Simple_Pseudo { _0: let t } => t,
        _ => null,
    };
    if (t1 == null || t2 == null) {
        return false;
    }
    let p1 = parse_pseudo_parts(t1);
    let p2 = parse_pseudo_parts(t2);
    if (p1 == null || p2 == null) {
        return false;
    }
    if (unvendor(p1.name) != "slotted" || p1.head != p2.head) {
        return false;
    }
    // PORT: `match (parse_list(..), parse_list(..))` → if.
    let l1 = root.selector.parse.parse_list(p1.arg);
    let l2 = root.selector.parse.parse_list(p2.arg);
    if (l1 != null && l2 != null) {
        list_is_superselector(l1, l2)
    } else {
        false
    }
}

/// Parse a (possibly vendor-prefixed) `:nth-child`/`:nth-last-child` pseudo
/// with an `of <selector>` clause into `(head, anb, of_selector)`, where `head`
/// is the verbatim name including the colon.
function nth_selector_parts(text: string) -> root.std.Tuple3<string, string, string>? {
    let open = text.index_of("(");
    if (open == null) {
        return null;
    }
    if (!text.ends_with(")") || text.starts_with("::")) {
        return null;
    }
    let head = text.slice(0, open);
    let name = root.std.ascii_lower(root.std.trim_start_matches(head, ":"));
    let un = unvendor(name);
    if (!(un == "nth-child" || un == "nth-last-child")) {
        return null;
    }
    let arg = text.slice(open + 1, text.length() - 1);
    let pos = find_of_keyword(root.std.ascii_lower(arg));
    if (pos == null) {
        return null;
    }
    root.std.Tuple3<string, string, string> {
        _0: head,
        _1: root.std.trim(arg.slice(0, pos)),
        _2: root.std.trim(arg.slice(pos + 2, arg.length())),
    }
}

/// The selector branches of a subselector-pseudo *class* (dart-sass
/// `SimpleSelector._subselectorPseudos`): the argument list of
/// `:is`/`:matches`/`:any`/`:where`, or the `of` list of
/// `:nth-child`/`:nth-last-child`. Vendor prefixes are allowed.
function subselector_pseudo_branches(text: string) -> Complex[]? {
    let nth = nth_selector_parts(text);
    if (nth != null) {
        return root.selector.parse.parse_list(nth._2);
    }
    let parts = parse_pseudo_parts(text);
    if (parts == null) {
        return null;
    }
    if (parts.head.starts_with("::")) {
        return null;
    }
    let un = unvendor(parts.name);
    if (!(un == "is" || un == "matches" || un == "any" || un == "where")) {
        return null;
    }
    root.selector.parse.parse_list(parts.arg)
}

/// dart-sass `_selectorPseudoIsSuperselector` for `nth-child`/`nth-last-child`:
/// some simple of `b` is a same-named pseudo with an identical An+B argument
/// whose `of` selector list is a subselector of `pseudo1`'s.
function nth_pseudo_is_super(head1: string, anb1: string, of1: string, b: Compound) -> bool {
    let list1_opt = root.selector.parse.parse_list(of1);
    if (list1_opt == null) {
        return false;
    }
    // PORT: re-bind the narrowed value; a closure does not see the narrowing.
    let list1: Complex[] = list1_opt;
    b.simples.some((s2: Simple) -> bool {
        let t2 = match (s2) {
            Simple_Pseudo { _0: let t } => t,
            _ => null,
        };
        if (t2 == null) {
            return false;
        }
        let parts2 = nth_selector_parts(t2);
        if (parts2 == null) {
            return false;
        }
        let head2 = parts2._0;
        let anb2 = parts2._1;
        let of2 = parts2._2;
        if (!(head2 == head1 && anb2 == anb1)) {
            return false;
        }
        let list2 = root.selector.parse.parse_list(of2);
        if (list2 != null) {
            list_is_superselector(list1, list2)
        } else {
            false
        }
    })
}

/// Like [`compound_is_superselector`] over raw simple-selector slices, treating
/// an empty `b` as the universal selector (dart-sass
/// `_compoundComponentsIsSuperselector`).
function compound_components_is_superselector(a: Simple[], b: Simple[]) -> bool {
    if (a.length() == 0) {
        return true;
    }
    let universal: Simple[] = [Simple_Universal { ns: null }];
    let b = if (b.length() == 0) {
        universal
    } else {
        b
    };
    compound_is_superselector(Compound { simples: root.std.clone_vec(a) }, Compound { simples: root.std.clone_vec(b) }, [])
}

/// If `compound` contains a pseudo-element, return it and its index.
function find_pseudo_element(compound: Compound) -> root.std.Tuple2<Simple, int>? {
    // PORT: `.iter().enumerate().find(..).map(..)` → index loop.
    let i = 0;
    for (let s in compound.simples) {
        if (is_pseudo_element(s)) {
            return root.std.Tuple2<Simple, int> { _0: s, _1: i };
        }
        i += 1;
    }
    null
}

/// Whether simple `a` is a superselector of simple `b`.
function simple_is_superselector(a: Simple, b: Simple) -> bool {
    if (a == b) {
        return true;
    }
    // dart-sass `SimpleSelector.isSuperselector`: any simple is a superselector
    // of a subselector-pseudo (`:is`/`:matches`/`:any`/`:where` or
    // `:nth-child(... of S)`/`:nth-last-child(... of S)`) when every branch's
    // final compound contains a subselector of it.
    if let pb: Simple_Pseudo = b {
        let branches = subselector_pseudo_branches(pb._0);
        if (branches != null) {
            return branches.every((complex: Complex) -> bool {
                let last = root.std.last(to_dart(complex).comps);
                if (last != null) {
                    last.compound.simples.some((s: Simple) -> bool {
                        simple_is_superselector(a, s)
                    })
                } else {
                    false
                }
            });
        }
    }
    match (a) {
        // `*` (no namespace) matches everything.
        Simple_Universal { ns: null } => true,
        // `*|*` matches everything.
        Simple_Universal { ns: let n } if n == "*" => true,
        // `ns|*` matches `ns|type` and `ns|*` (same namespace).
        Simple_Universal { ns: let n } => match (b) {
            Simple_Type { _0: let t } => type_namespace(t) == n,
            Simple_Universal { ns: let m } if m != null => n == m,
            _ => false,
        },
        // A type selector `t` supersedes a matching type selector, honoring
        // a `*` namespace wildcard.
        Simple_Type { _0: let t } => match (b) {
            Simple_Type { _0: let u } => {
                let s1 = split_type(t);
                let n1 = s1._0;
                let name1 = s1._1;
                let s2 = split_type(u);
                let n2 = s2._0;
                let name2 = s2._1;
                name1 == name2 && (n1 == "*" || n1 == n2)
            },
            _ => false,
        },
        _ => false,
    }
}

/// Split a (possibly namespaced) type name into `(namespace, local)`.
function split_type(t: string) -> root.std.Tuple2<string?, string> {
    let sp = root.std.split_once(t, "|");
    if (sp != null) {
        root.std.Tuple2<string?, string> { _0: sp._0, _1: sp._1 }
    } else {
        root.std.Tuple2<string?, string> { _0: null, _1: t }
    }
}

/// The namespace component of a type selector string, if any.
function type_namespace(t: string) -> string? {
    let sp = root.std.split_once(t, "|");
    if (sp != null) {
        sp._0
    } else {
        null
    }
}

/// Extend a single complex selector: compute, for each component, the list of
/// possible replacements (each a sequence of components), then take the
/// Cartesian product and weave them into complete complex selectors. The first
/// option of every component is the original, so the unextended selector comes
/// out first. (dart-sass `Extender._extendComplex`.)
function extend_complex(complex: Complex, extensions: Extension[]) -> Complex[] {
    let empty: map<string, bool> = {};
    extend_complex_breaks(complex, false, true, null, extensions, empty, CartesianOrder.Fold).map((
        t: root.std.Tuple3<Complex, bool, bool>,
    ) -> Complex {
        t._0
    })
}

/// Which cartesian-product ITERATION ORDER the `@extend` engine uses when
/// crossing per-component / per-simple option lists. dart-sass has two:
/// `OneShot` is the literal `paths(...)` order (the LAST component/simple
/// varies SLOWEST) used by the single-shot transitive-closure path; `Fold`
/// is the registration-order incremental fold (the FIRST component/simple
/// varies slowest). This only selects which nested loop is outer — it never
/// changes WHICH products are generated, only their byte order, which dart
/// pins exactly. See the call sites at `extend_complex_breaks` /
/// `extend_component` for the two loop forms.
enum CartesianOrder {
    OneShot,
    Fold,
}

/// Like [`extend_complex`], but every product carries its line-break flag:
/// the input's flag OR any contributing extender's (dart's
/// `complex.lineBreak || path.any((c) => c.lineBreak)`).
function extend_complex_breaks(
    complex: Complex,
    in_break: bool,
    in_orig: bool,
    orig_scope: string?,
    extensions: Extension[],
    ext_breaks: map<string, bool>/* key: Complex */,
    order: CartesianOrder,
) -> root.std.Tuple3<Complex, bool, bool>[] {
    let d = to_dart(complex);
    // dart-sass: a complex selector with more than one leading combinator is
    // never extended (the caller keeps the original).
    if (d.leading.length() > 1) {
        return [root.std.Tuple3<Complex, bool, bool> { _0: complex, _1: in_break, _2: in_orig }];
    }

    // For each component, the complex selectors it can expand to (the original
    // first, followed by any extension replacements, transitively resolved).
    let per_component: root.std.Tuple2<DComplex, bool>[][] = [];
    let any_extended = false;
    let i = 0;
    for (let comp in d.comps) {
        let extended = extend_component(comp, extensions, ext_breaks, order);
        if (extended == null) {
            // dart-sass folds unextended leading components into a prefix
            // complex carrying the selector's leading run; keeping the run on
            // the first component's sole option is equivalent.
            let leading: Combinator[] = if (i == 0) {
                root.std.clone_vec(d.leading)
            } else {
                []
            };
            per_component.push(
                [
                    root.std.Tuple2<DComplex, bool> {
                        _0: DComplex { leading: leading, comps: [comp] },
                        _1: false,
                    },
                ],
            );
        } else {
            any_extended = true;
            if (i == 0 && d.leading.length() != 0) {
                // dart-sass: a first-component extension must have no
                // leading combinators (or the same ones); the complex's own
                // leading run is then re-attached.
                per_component.push(
                    extended
                        .filter((t: root.std.Tuple2<DComplex, bool>) -> bool {
                            t._0.leading.length() == 0 || t._0.leading == d.leading
                        })
                        .map((t: root.std.Tuple2<DComplex, bool>) -> root.std.Tuple2<DComplex, bool> {
                            root.std.Tuple2<DComplex, bool> {
                                _0: DComplex {
                                    leading: root.std.clone_vec(d.leading),
                                    comps: t._0.comps,
                                },
                                _1: t._1,
                            }
                        }),
                );
            } else {
                per_component.push(extended);
            }
        }
        i += 1;
    }
    if (!any_extended) {
        return [root.std.Tuple3<Complex, bool, bool> { _0: complex, _1: in_break, _2: in_orig }];
    }

    // Take the Cartesian product across components and `weave` each path into
    // one or more complete complex selectors (dart-sass `paths` + `weave`). The
    // iteration order sets which component varies fastest: dart's one-shot
    // `_extendComplex` uses literal `paths` (the LAST component varies SLOWEST,
    // its option the outer loop), while the incremental registration-order fold
    // varies the FIRST component slowest (its product interleaved per step). See
    // nested-compound-unification: rule-after-extends -> one_shot paths order.
    let combos: root.std.Tuple2<DComplex[], bool>[] = [root.std.Tuple2<DComplex[], bool> { _0: [], _1: false }];
    for (let opts in per_component) {
        let next: root.std.Tuple2<DComplex[], bool>[] = [];
        // The COMPONENT axis always uses dart's literal `paths` order (the
        // newest component's option is the outer loop, so the FIRST component
        // varies fastest): dart runs ONE `_extendComplex` per selector even on
        // the incremental fold path, and `paths` is the only order it has.
        // `CartesianOrder` still swaps the per-SIMPLE loops inside
        // `extend_component` (forem `.crayons-btn + .crayons-btn` both-ends
        // extension vs the `:not` insertion order).
        for (let o in opts) {
            let opt = o._0;
            let oflag = o._1;
            for (let cc in combos) {
                let combo = cc._0;
                let cflag = cc._1;
                let c = root.std.clone_vec(combo);
                c.push(opt);
                next.push(root.std.Tuple2<DComplex[], bool> { _0: c, _1: cflag || oflag });
            }
        }
        combos = next;
        if (combos.length() > 100_000) {
            break;
        }
    }

    // dart's fast path (`options case [var extenders]` over a bare single
    // compound) returns the EXTENDER's own `ComplexSelector` object, and an
    // extender is a rule selector already living in the identity `_originals`
    // — so a full-compound replacement product carries original status. Any
    // weave/unification builds NEW objects and does not.
    let input_is_bare = d.leading.length() == 0
        && d.comps.length() == 1
        && d.comps[0].combinators.length() == 0
        && d.comps[0].compound.simples.length() == 1;
    // Identity-original status is PER STORE: `addExtensions` (the cross-
    // module merge) never adds a downstream store's originals, so a foreign
    // extender's bare product is NOT protected in this scope and a broader
    // sibling product replaces it (midstream_extend_within_pseudoselector),
    // while the same shape within one module keeps both (dart#1297).
    // PORT: `FxHashSet<&Complex>` → set keyed by `Complex::render()` (render is
    // injective over `Complex`, see `assert_render_injective`).
    let bare_extenders: map<string, bool> = {};
    if (input_is_bare && orig_scope != null) {
        let scope = orig_scope;
        for (let e in extensions) {
            if (!e.derived && e.origin == scope) {
                for (let x in e.extenders) {
                    let _ = bare_extenders.set(x.render(), true);
                }
            }
        }
    }
    let out: root.std.Tuple3<Complex, bool, bool>[] = [];
    let seen: map<string, bool> = {};
    for (let pp in combos) {
        let path = pp._0;
        let pflag = pp._1;
        for (let woven in weave(path)) {
            let c = from_dart(woven);
            let r = c.render();
            if (root.std.set_insert(seen, r)) {
                // dart marks the FIRST product of an original complex as an
                // original itself (`_originals.add(outputComplex)`) — it is
                // the reconstructed original, value-equal by construction.
                let orig = (in_orig && out.length() == 0) || (input_is_bare && bare_extenders.has(r));
                out.push(
                    root.std.Tuple3<Complex, bool, bool> { _0: c, _1: in_break || pflag, _2: orig },
                );
            }
        }
    }
    out
}

/// A complex selector in dart-sass's internal model: a leading combinator run
/// (e.g. `> .c`; more than one is invalid-but-preserved CSS) plus components
/// each carrying its *trailing* combinator run. The public [`Complex`] stores
/// the joining run on the *following* component instead; [`to_dart`]/
/// [`from_dart`] convert losslessly at the boundary. The weave/unify/extend
/// pipeline operates entirely on this model so combinator runs survive intact.
class DComplex {
    leading: Combinator[],
    comps: TComp[],
    /// derive(Default)
    function default() -> DComplex {
        DComplex { leading: [], comps: [] }
    }

    /// dart-sass `Selector.isUseless` (combinator part): a leading run or any
    /// component run of more than one combinator can never match anything.
    function is_useless(self) -> bool {
        self.leading.length() > 1
            || self.comps.some((c: TComp) -> bool {
                c.combinators.length() > 1
            })
    }

    /// dart-sass `ComplexSelector.withAdditionalCombinators`: append
    /// `combinators` to the final component's trailing run (or to the leading
    /// run when there are no components).
    function with_additional_combinators(self, combinators: Combinator[]) -> DComplex {
        if (combinators.length() == 0) {
            return self;
        }
        // PORT: Rust takes `mut self` by value; BAML classes alias, so mutate a
        // shallow copy and replace (rather than extend in place) the last component.
        let me = DComplex {
            leading: root.std.clone_vec(self.leading),
            comps: root.std.clone_vec(self.comps),
        };
        let last = root.std.last(me.comps);
        if (last != null) {
            me.comps[me.comps.length() - 1]
                = TComp {
                    compound: last.compound,
                    combinators: last.combinators.concat(combinators),
                };
        } else {
            root.std.extend(me.leading, combinators);
        }
        me
    }

    /// dart-sass `ComplexSelector.concatenate`: append `child`'s components,
    /// folding its leading run onto our final component's trailing run.
    function concatenate(self, child: DComplex) -> DComplex {
        if (child.leading.length() == 0) {
            let comps = root.std.clone_vec(self.comps);
            root.std.extend(comps, child.comps);
            DComplex { leading: root.std.clone_vec(self.leading), comps: comps }
        } else if (self.comps.length() != 0) {
            let comps = root.std.clone_vec(self.comps);
            // PORT: `last_mut().combinators.extend(..)` on a deep clone → replace the
            // (shared) last component with an extended copy.
            let last = root.std.expect(root.std.last(comps), "non-empty");
            comps[comps.length() - 1]
                = TComp {
                    compound: last.compound,
                    combinators: last.combinators.concat(child.leading),
                };
            root.std.extend(comps, child.comps);
            DComplex { leading: root.std.clone_vec(self.leading), comps: comps }
        } else {
            let leading = root.std.clone_vec(self.leading);
            root.std.extend(leading, child.leading);
            DComplex { leading: leading, comps: root.std.clone_vec(child.comps) }
        }
    }
}

/// Convert the public leading-combinator model into the dart model. The first
/// component's run becomes the complex's leading run; each later component's
/// run moves onto the previous component's trailing position; `trailing` lands
/// on the last component. A combinator-only selector (`>`) becomes a leading
/// run with no components. Lossless.
function to_dart(c: Complex) -> DComplex {
    let first = c.components.at(0);
    if (first == null) {
        return DComplex { leading: root.std.clone_vec(c.trailing), comps: [] };
    }
    let n = c.components.length();
    let comps: TComp[] = [];
    let i = 0;
    while (i < n) {
        comps.push(
            TComp {
                compound: c.components[i].compound,
                combinators: if (i + 1 < n) {
                    root.std.clone_vec(c.components[i + 1].combinators)
                } else {
                    root.std.clone_vec(c.trailing)
                },
            },
        );
        i += 1;
    }
    DComplex { leading: root.std.clone_vec(first.combinators), comps: comps }
}

/// Convert back from the dart model into the public model (inverse of
/// [`to_dart`]; lossless).
function from_dart(d: DComplex) -> Complex {
    if (d.comps.length() == 0) {
        return Complex { components: [], trailing: root.std.clone_vec(d.leading) };
    }
    let components: ComplexComponent[] = [];
    let i = 0;
    for (let t in d.comps) {
        components.push(
            ComplexComponent {
                combinators: if (i == 0) {
                    root.std.clone_vec(d.leading)
                } else {
                    root.std.clone_vec(d.comps[i - 1].combinators)
                },
                compound: t.compound,
            },
        );
        i += 1;
    }
    Complex {
        components: components,
        trailing: root.std.clone_vec(root.std.expect(root.std.last(d.comps), "non-empty").combinators),
    }
}

/// dart-sass `weave`: expand "parenthesized selectors". Single-component path
/// elements are concatenated onto every prefix; multi-component ones have
/// their parent components interwoven with each prefix via [`weave_parents`].
function weave(complexes: DComplex[]) -> DComplex[] {
    if (complexes.length() <= 1) {
        return root.std.clone_vec(complexes);
    }
    let prefixes: DComplex[] = [complexes[0]];
    for (let complex in complexes.slice(1, complexes.length())) {
        if (complex.comps.length() == 1) {
            let k = 0;
            while (k < prefixes.length()) {
                prefixes[k] = prefixes[k].concatenate(complex);
                k += 1;
            }
            continue;
        }
        let last = root.std.last(complex.comps);
        if (last == null) {
            continue;
        }
        let next: DComplex[] = [];
        for (let prefix in prefixes) {
            let parents: DComplex[] = weave_parents(prefix, complex) ?? [];
            for (let parent_prefix in parents) {
                let woven = parent_prefix;
                woven.comps.push(last);
                next.push(woven);
            }
        }
        prefixes = next;
        if (prefixes.length() > 100_000) {
            break;
        }
    }
    prefixes
}

/// dart-sass `_mergeLeadingCombinators`: a leading run compatible with both, or
/// `None` if they can't be unified (either run longer than one, or two
/// different single combinators).
function merge_leading_combinators(a: Combinator[], b: Combinator[]) -> Combinator[]? {
    if (a.length() > 1 || b.length() > 1) {
        return null;
    }
    if (a.length() == 0) {
        return root.std.clone_vec(b);
    }
    if (b.length() == 0 || a == b) {
        return root.std.clone_vec(a);
    }
    null
}

/// A complex-selector component in the *trailing-combinator* representation
/// dart-sass uses for weaving: a compound followed by zero or more combinators
/// that join it to the *next* component. (The current public model attaches a
/// single combinator to the *following* compound; we convert at the boundary.)
class TComp {
    compound: Compound,
    combinators: Combinator[],
}

/// Interweave `prefix`'s components with `base`'s components *other than the
/// last*, returning all order-preserving interleavings (with unification of
/// equal/superselector groups and leading/trailing combinator merging). A
/// faithful port of dart-sass `_weaveParents`. Returns `None` when the two
/// can't be woven.
function weave_parents(prefix: DComplex, base: DComplex) -> DComplex[]? {
    let leading_opt = merge_leading_combinators(prefix.leading, base.leading);
    if (leading_opt == null) {
        return null;
    }
    // PORT: re-bind the narrowed value; a closure does not see the narrowing.
    let leading: Combinator[] = leading_opt;

    // Queues of _only_ the parent selectors: the prefix only contains parents,
    // but `base` has a target component we don't weave in.
    // PORT: `VecDeque<TComp>` → array (`push_front` → `unshift`, `pop_front` → `shift`).
    let queue1: TComp[] = root.std.clone_vec(prefix.comps);
    let queue2: TComp[] = base.comps.slice(0, base.comps.length() - 1);

    let trailing_combinators = merge_trailing_combinators(queue1, queue2);
    if (trailing_combinators == null) {
        return null;
    }

    // `_firstIfRootish`: ensure rootish selectors (`:root` etc.) are unified and
    // pinned to the front.
    let rootish1 = first_if_rootish(queue1);
    let rootish2 = first_if_rootish(queue2);
    // PORT: `match (rootish1, rootish2)` → if/else chain.
    if (rootish1 != null && rootish2 != null) {
        let rootish = unify_compounds(rootish1.compound.simples, rootish2.compound.simples);
        if (rootish == null) {
            return null;
        }
        let comp = Compound { simples: rootish };
        let _ = queue1.unshift(TComp { compound: comp, combinators: rootish1.combinators });
        let _ = queue2.unshift(TComp { compound: comp, combinators: rootish2.combinators });
    } else if (rootish1 != null || rootish2 != null) {
        let r = rootish1 ?? root.std.unwrap(rootish2);
        let _ = queue1.unshift(r);
        let _ = queue2.unshift(r);
    }

    let groups1 = group_selectors(queue1);
    let groups2 = group_selectors(queue2);

    // LCS of the two group lists (dart-sass passes groups2, groups1).
    let groups1_vec: TComp[][] = root.std.clone_vec(groups1);
    let groups2_vec: TComp[][] = root.std.clone_vec(groups2);
    let lcs = lcs_groups(groups2_vec, groups1_vec);

    let choices: TComp[][][] = [];
    for (let group in lcs) {
        let chunk = chunks_groups(groups1, groups2, (seq: TComp[][]) -> bool {
            let front = seq.at(0);
            if (front != null) {
                complex_is_parent_superselector(front, group)
            } else {
                false
            }
        });
        // Flatten each chunk (a list of groups) into a flat component list.
        let flattened: TComp[][] = chunk.map((g: TComp[][]) -> TComp[] {
            flatten_groups(g)
        });
        choices.push(flattened);
        choices.push([group]);
        let _ = groups1.shift();
        let _ = groups2.shift();
    }
    let tail = chunks_groups(groups1, groups2, (seq: TComp[][]) -> bool {
        seq.length() == 0
    });
    choices.push(
        tail.map((g: TComp[][]) -> TComp[] {
            flatten_groups(g)
        }),
    );
    for (let tc in trailing_combinators) {
        choices.push(tc);
    }

    // Cartesian product of the non-empty choices, flattening each path. The
    // iteration order matches dart-sass `paths`: for each choice, the option is
    // the outer loop and the accumulated paths the inner loop.
    let results: TComp[][] = [[]];
    for (
        let choice in choices.filter((c: TComp[][]) -> bool {
            c.length() != 0
        })
    ) {
        let next: TComp[][] = [];
        for (let option in choice) {
            for (let path in results) {
                let p = root.std.clone_vec(path);
                root.std.extend(p, option);
                next.push(p);
            }
        }
        results = next;
        if (results.length() > 100_000) {
            break;
        }
    }
    results.map((comps: TComp[]) -> DComplex {
        DComplex { leading: root.std.clone_vec(leading), comps: comps }
    })
}

/// Flatten a list of groups (each itself a component list) into a single
/// component list.
function flatten_groups(groups: TComp[][]) -> TComp[] {
    groups.flat_map((g: TComp[]) -> TComp[] {
        g
    })
}

/// dart-sass `_firstIfRootish`: if the first queue element's compound contains a
/// rootish pseudo-class (`:root`/`:scope`/`:host`/`:host-context`), remove and
/// return it.
function first_if_rootish(queue: TComp[]) -> TComp? {
    let first = queue.at(0);
    if (first == null) {
        return null;
    }
    let is_rootish = first.compound.simples.some((s: Simple) -> bool {
        if let p: Simple_Pseudo = s {
            is_rootish_pseudo_class(p._0)
        } else {
            false
        }
    });
    if (is_rootish) {
        queue.shift()
    } else {
        null
    }
}

/// Whether a pseudo text is a rootish *class* (single colon) named one of
/// `root`/`scope`/`host`/`host-context`.
function is_rootish_pseudo_class(text: string) -> bool {
    if (text.starts_with("::")) {
        return false;
    }
    let name = root.std.trim_start_matches(text, ":");
    // PORT: `name.split(['(', ' ']).next()` → the prefix before the first `(`
    // or space (the first split piece always exists).
    let cut = root.std.find_by(name, (c: string) -> bool {
        c == "(" || c == " "
    });
    let base = root.std.ascii_lower(
        if (cut != null) {
            name.slice(0, cut)
        } else {
            name
        },
    );
    match (base) {
        "root" | "scope" | "host" | "host-context" => true,
        _ => false,
    }
}

/// dart-sass `_mergeTrailingCombinators`: extract trailing combinators from the
/// ends of `components1`/`components2` and merge them into a list of choice
/// groups (each a list of component lists). Returns `None` if they can't be
/// merged. Iterative port of the recursive Dart original.
function merge_trailing_combinators(components1: TComp[], components2: TComp[]) -> TComp[][][]? {
    // PORT: `VecDeque` → array (`back` → `last`, `pop_back` → `pop`,
    // `push_front` → `unshift`); the `?` on a failed pop returns `null`.
    let result: TComp[][][] = [];
    while (true) {
        let back1 = root.std.last(components1);
        let combinators1: Combinator[] = if (back1 != null) {
            root.std.clone_vec(back1.combinators)
        } else {
            []
        };
        let back2 = root.std.last(components2);
        let combinators2: Combinator[] = if (back2 != null) {
            root.std.clone_vec(back2.combinators)
        } else {
            []
        };
        if (combinators1.length() == 0 && combinators2.length() == 0) {
            return result;
        }
        if (combinators1.length() > 1 || combinators2.length() > 1) {
            return null;
        }
        let c1: Combinator? = combinators1.at(0);
        let c2: Combinator? = combinators2.at(0);
        // Each popped component retains its trailing combinators (mirroring
        // dart-sass `removeLast()`), so a sibling/child combinator that "wins" a
        // case is preserved on the resulting component.
        // PORT: `match (c1, c2)` → if/else chain in the same arm order.
        if (c1 == Combinator.FollowingSibling && c2 == Combinator.FollowingSibling) {
            let component1 = components1.pop();
            if (component1 == null) {
                return null;
            }
            let component2 = components2.pop();
            if (component2 == null) {
                return null;
            }
            if (compound_is_superselector(component1.compound, component2.compound, [])) {
                let _ = result.unshift([[component2]]);
            } else if (compound_is_superselector(component2.compound, component1.compound, [])) {
                let _ = result.unshift([[component1]]);
            } else {
                let choices: TComp[][] = [[component1, component2], [component2, component1]];
                let unified = unify_compounds(component1.compound.simples, component2.compound.simples);
                if (unified != null) {
                    let fs: Combinator = Combinator.FollowingSibling;
                    choices.push(
                        [TComp { compound: Compound { simples: unified }, combinators: [fs] }],
                    );
                }
                let _ = result.unshift(choices);
            }
        } else if (
            (c1 == Combinator.FollowingSibling && c2 == Combinator.NextSibling)
                || (c1 == Combinator.NextSibling && c2 == Combinator.FollowingSibling)
        ) {
            // Identify which side is `+` (next) and which is `~` (following).
            let following_first = c1 == Combinator.FollowingSibling;
            let following = if (following_first) {
                components1.pop()
            } else {
                components2.pop()
            };
            if (following == null) {
                return null;
            }
            let next = if (following_first) {
                components2.pop()
            } else {
                components1.pop()
            };
            if (next == null) {
                return null;
            }
            if (compound_is_superselector(following.compound, next.compound, [])) {
                let _ = result.unshift([[next]]);
            } else {
                let choices: TComp[][] = [[following, next]];
                let unified = unify_compounds(following.compound.simples, next.compound.simples);
                if (unified != null) {
                    choices.push(
                        [
                            TComp {
                                compound: Compound { simples: unified },
                                combinators: root.std.clone_vec(next.combinators),
                            },
                        ],
                    );
                }
                let _ = result.unshift(choices);
            }
        } else if (
            (c1 == Combinator.Child && c2 == Combinator.NextSibling)
                || (c1 == Combinator.Child && c2 == Combinator.FollowingSibling)
        ) {
            // The sibling component wins (kept with its combinator); the
            // child component is dropped.
            let sibling = components2.pop();
            if (sibling == null) {
                return null;
            }
            let _ = result.unshift([[sibling]]);
        } else if (
            (c1 == Combinator.NextSibling && c2 == Combinator.Child)
                || (c1 == Combinator.FollowingSibling && c2 == Combinator.Child)
        ) {
            let sibling = components1.pop();
            if (sibling == null) {
                return null;
            }
            let _ = result.unshift([[sibling]]);
        } else if (c1 != null && c2 != null && c1 == c2) {
            let comb1: Combinator = c1;
            let comp1 = components1.pop();
            if (comp1 == null) {
                return null;
            }
            let comp2 = components2.pop();
            if (comp2 == null) {
                return null;
            }
            let unified = unify_compounds(comp1.compound.simples, comp2.compound.simples);
            if (unified == null) {
                return null;
            }
            let _ = result.unshift(
                [[TComp { compound: Compound { simples: unified }, combinators: [comb1] }]],
            );
        } else if (c1 != null && c2 == null) {
            let combinator: Combinator = c1;
            let drop2 = false;
            if (combinator == Combinator.Child) {
                let d = root.std.last(components2);
                if (d != null) {
                    let c = root.std.last(components1);
                    if (c != null) {
                        drop2 = compound_is_superselector(d.compound, c.compound, []);
                    }
                }
            }
            if (drop2) {
                let _ = components2.pop();
            }
            let comp = components1.pop();
            if (comp == null) {
                return null;
            }
            let _ = result.unshift([[comp]]);
        } else if (c1 == null && c2 != null) {
            let combinator: Combinator = c2;
            let drop1 = false;
            if (combinator == Combinator.Child) {
                let d = root.std.last(components1);
                if (d != null) {
                    let c = root.std.last(components2);
                    if (c != null) {
                        drop1 = compound_is_superselector(d.compound, c.compound, []);
                    }
                }
            }
            if (drop1) {
                let _ = components1.pop();
            }
            let comp = components2.pop();
            if (comp == null) {
                return null;
            }
            let _ = result.unshift([[comp]]);
        } else {
            return null;
        }
    }
    // PORT: unreachable — the Rust `loop` only exits through `return`.
    null
}

/// dart-sass `_groupSelectors`: group components into the longest possible
/// sub-lists such that components without trailing combinators only appear at
/// the end of a sub-list. E.g. `A B > C D + E ~ G` → `[(A) (B > C) (D + E ~ G)]`.
function group_selectors(components: TComp[]) -> TComp[][] {
    // PORT: `VecDeque<Vec<TComp>>` → array.
    let groups: TComp[][] = [];
    let group: TComp[] = [];
    for (let component in components) {
        let ends_group = component.combinators.length() == 0;
        group.push(component);
        if (ends_group) {
            groups.push(group);
            group = [];
        }
    }
    if (group.length() != 0) {
        groups.push(group);
    }
    groups
}

/// dart-sass `_mustUnify`: whether two component lists share a unique simple
/// selector (an id or pseudo-element) and so must be unified.
function must_unify(complex1: TComp[], complex2: TComp[]) -> bool {
    // PORT: `Vec::contains` → `root.std.contains` (structural `==`; BAML
    // `Array.includes` compares class instances by identity).
    let unique: Simple[] = [];
    for (let component in complex1) {
        for (let simple in component.compound.simples) {
            if (is_unique_simple(simple) && !root.std.contains(unique, simple)) {
                unique.push(simple);
            }
        }
    }
    if (unique.length() == 0) {
        return false;
    }
    complex2.some((component: TComp) -> bool {
        component.compound.simples.some((simple: Simple) -> bool {
            is_unique_simple(simple) && root.std.contains(unique, simple)
        })
    })
}

/// dart-sass `_isUnique`: a compound may contain only one of these per type — an
/// id selector or a pseudo-element.
function is_unique_simple(simple: Simple) -> bool {
    simple is Simple_Id || is_pseudo_element(simple)
}

/// dart-sass `_chunks` over group lists: drain the leading subsequence of each
/// queue (up to where `done` first holds) and return the two orderings of the
/// combined drained groups, or a single ordering when one side is empty.
function chunks_groups(
    q1: TComp[][],
    q2: TComp[][],
    done: (TComp[][]) -> bool throws unknown,
) -> TComp[][][] {
    let chunk1: TComp[][] = [];
    while (!done(q1)) {
        let g = q1.shift();
        if (g == null) {
            break;
        }
        chunk1.push(g);
    }
    let chunk2: TComp[][] = [];
    while (!done(q2)) {
        let g = q2.shift();
        if (g == null) {
            break;
        }
        chunk2.push(g);
    }
    // PORT: `match (chunk1.is_empty(), chunk2.is_empty())` → if/else chain.
    let e1 = chunk1.length() == 0;
    let e2 = chunk2.length() == 0;
    if (e1 && e2) {
        let none: TComp[][][] = [];
        none
    } else if (e1) {
        [chunk2]
    } else if (e2) {
        [chunk1]
    } else {
        let a = root.std.clone_vec(chunk1);
        root.std.extend(a, root.std.clone_vec(chunk2));
        let b = chunk2;
        root.std.extend(b, chunk1);
        [a, b]
    }
}

/// LCS over group lists with dart-sass's `select`: two groups match if they're
/// equal, one is a parent-superselector of the other (then the more specific is
/// chosen), or they must-unify and unify to a single complex.
function lcs_groups(list1: TComp[][], list2: TComp[][]) -> TComp[][] {
    let n = list1.length();
    let m = list2.length();
    let lengths: int[][] = baml.Array.generate(n + 1, (_r: int) -> int[] {
        baml.Array.filled(m + 1, 0)
    });
    let selections: (TComp[]?)[][] = baml.Array.generate(n, (_r: int) -> (TComp[]?)[] {
        let row: (TComp[]?)[] = [];
        let k = 0;
        while (k < m) {
            row.push(null);
            k += 1;
        }
        row
    });
    let i = 0;
    while (i < n) {
        let j = 0;
        while (j < m) {
            let sel = lcs_select_groups(list1[i], list2[j]);
            let has = sel != null;
            selections[i][j] = sel;
            lengths[i + 1][j + 1]
                = if (has) {
                    lengths[i][j] + 1
                } else {
                    root.std.imax(lengths[i + 1][j], lengths[i][j + 1])
                };
            j += 1;
        }
        i += 1;
    }
    let out: TComp[][] = [];
    backtrack_groups(n - 1, m - 1, lengths, selections, out);
    out
}

function backtrack_groups(
    i: int,
    j: int,
    lengths: int[][],
    selections: (TComp[]?)[][],
    out: TComp[][],
) -> void {
    if (i == -1 || j == -1) {
        return;
    }
    let ui = i;
    let uj = j;
    let sel = selections[ui][uj];
    if (sel != null) {
        backtrack_groups(i - 1, j - 1, lengths, selections, out);
        out.push(sel);
        return;
    }
    if (lengths[ui + 1][uj] > lengths[ui][uj + 1]) {
        backtrack_groups(i, j - 1, lengths, selections, out);
    } else {
        backtrack_groups(i - 1, j, lengths, selections, out);
    }
}

/// The LCS selection for two groups (component lists), per dart-sass.
function lcs_select_groups(group1: TComp[], group2: TComp[]) -> TComp[]? {
    if (group1 == group2) {
        return root.std.clone_vec(group1);
    }
    if (complex_is_parent_superselector(group1, group2)) {
        return root.std.clone_vec(group2);
    }
    if (complex_is_parent_superselector(group2, group1)) {
        return root.std.clone_vec(group1);
    }
    if (!must_unify(group1, group2)) {
        return null;
    }
    // Unify the two groups as complete complex selectors; keep only if the
    // unification yields a single complex selector (dart-sass
    // `unified?.singleOrNull?.components`).
    let c1 = DComplex { leading: [], comps: root.std.clone_vec(group1) };
    let c2 = DComplex { leading: [], comps: root.std.clone_vec(group2) };
    let unified = unify_complex_list([c1, c2]);
    if (unified == null) {
        return null;
    }
    match (unified) {
        [let single] => single.comps,
        _ => null,
    }
}

/// dart-sass `_complexIsParentSuperselector`: like `complexIsSuperselector` but
/// as though both shared an implicit trailing base compound. Implemented by
/// appending a shared placeholder component to each and testing superselection.
function complex_is_parent_superselector(complex1: TComp[], complex2: TComp[]) -> bool {
    if (complex1.length() > complex2.length()) {
        return false;
    }
    let simples: Simple[] = [Simple_Placeholder { _0: "<temp>" }];
    let base = TComp { compound: Compound { simples: simples }, combinators: [] };
    let c1 = root.std.clone_vec(complex1);
    c1.push(base);
    let c2 = root.std.clone_vec(complex2);
    c2.push(base);
    complex_is_superselector_trailing(c1, c2)
}

/// Compute the replacement options for one component. The first option is the
/// original component (as a one-element sequence). For a compound with multiple
/// simple selectors, each simple is extended independently and the
/// within-compound Cartesian product is taken (so `.a.b` with `.a`→`.x` and
/// `.b`→`.y` yields `.a.b`, `.a.y`, `.b.x`, `.x.y`), then unified. Chains
/// (`.a` → `.b` → `.c`) expand transitively: each extender is fully extended in
/// isolation first, so the per-simple option set already contains the whole
/// chain. The within-compound product is then computed once (no re-extension of
/// the original simples, which would spuriously double-count combinations).
/// A parsed selector-bearing pseudo: `:name(arg)`.
class PseudoParts {
    /// The verbatim head including the leading colon(s), e.g. `:not` or `::is`.
    head: string,
    /// The lowercased name without colons, e.g. `not`, `is`.
    name: string,
    /// The raw argument text inside the parentheses.
    arg: string,
}

/// Parse a pseudo simple's text into its head/name/argument if it carries a
/// selector argument. Returns `None` for argument-less pseudos or non-pseudos.
function parse_pseudo_parts(text: string) -> PseudoParts? {
    let open = text.index_of("(");
    if (open == null) {
        return null;
    }
    if (!text.ends_with(")")) {
        return null;
    }
    let head = text.slice(0, open);
    let name = root.std.ascii_lower(root.std.trim_start_matches(head, ":"));
    let arg = text.slice(open + 1, text.length() - 1);
    PseudoParts { head: head, name: name, arg: arg }
}

/// Whether any simple in `complex` is a selector-bearing pseudo (`:not(...)`,
/// `:is(...)`, etc.) whose argument we might further extend on a later pass.
function complex_has_selector_pseudo(complex: Complex) -> bool {
    complex.components.some((comp: ComplexComponent) -> bool {
        comp.compound.simples.some((s: Simple) -> bool {
            let text = match (s) {
                Simple_Pseudo { _0: let t } => t,
                _ => null,
            };
            if (text == null) {
                return false;
            }
            let p = parse_pseudo_parts(text);
            if (p != null) {
                is_selector_pseudo(p.name)
            } else {
                false
            }
        })
    })
}

/// Whether `complex` contains a selector pseudo (`:not`/`:is`/`::slotted`/…)
/// whose ARGUMENT mentions one of the extension `targets`. When `only_not`, only
/// `:not` counts. Used to route extension to the legacy one-shot worklist: when
/// a target lives inside a pseudo argument, dart rewrites the compound in place
/// and applies such extensions simultaneously, which the sequential per-batch
/// fold mishandles. A pseudo whose argument is NOT a target (`:not(:first-child)`
/// in 086.1) is ignored, so those stay on the fold.
function pseudo_arg_has_target(
    complex: Complex,
    targets: map<string, bool>/* key: Simple */,
    only_not: bool,
) -> bool {
    // PORT: `targets.contains(s)` → `targets.has(s.render())` (sets of `Simple`
    // are keyed by `Simple::render()`, which is injective).
    complex.components.some((comp: ComplexComponent) -> bool {
        comp.compound.simples.some((s: Simple) -> bool {
            let text = match (s) {
                Simple_Pseudo { _0: let t } => t,
                _ => null,
            };
            if (text == null) {
                return false;
            }
            let parts = parse_pseudo_parts(text);
            if (parts == null) {
                return false;
            }
            if (!is_selector_pseudo(parts.name) || (only_not && unvendor(parts.name) != "not")) {
                return false;
            }
            let list = root.selector.parse.parse_list(parts.arg);
            if (list != null) {
                list.some((c: Complex) -> bool {
                    c.components.some((cc: ComplexComponent) -> bool {
                        cc.compound.simples.some((inner: Simple) -> bool {
                            targets.has(inner.render())
                        })
                    })
                })
            } else {
                false
            }
        })
    })
}

/// Whether `complex` mentions one of `targets` inside a selector-pseudo's
/// argument at ANY nesting depth (`:has(:not(.thing[disabled]))` reaches the
/// `.thing` target two pseudos deep). The shallow [`pseudo_arg_has_target`] only
/// inspects the immediate argument, so it misses a target buried under an outer
/// pseudo; this recursion is what flags issue_2055's `:has(:not(...))` extender
/// as self-referential so the `addSelector` pre-extension and the self-inclusive
/// `_extendExistingExtensions` re-extension apply to it.
function pseudo_arg_has_target_deep(
    complex: Complex,
    targets: map<string, bool>, /* key: Simple */
) -> bool {
    complex.components.some((comp: ComplexComponent) -> bool {
        comp.compound.simples.some((s: Simple) -> bool {
            let text = match (s) {
                Simple_Pseudo { _0: let t } => t,
                _ => null,
            };
            if (text == null) {
                return false;
            }
            let parts = parse_pseudo_parts(text);
            if (parts == null) {
                return false;
            }
            if (!is_selector_pseudo(parts.name)) {
                return false;
            }
            let list = root.selector.parse.parse_list(parts.arg);
            if (list != null) {
                list.some((c: Complex) -> bool {
                    c.components.some((cc: ComplexComponent) -> bool {
                        cc.compound.simples.some((inner: Simple) -> bool {
                            targets.has(inner.render())
                        })
                    })
                        || pseudo_arg_has_target_deep(c, targets)
                })
            } else {
                false
            }
        })
    })
}

/// Sound over-approximation of "can this batch's extensions possibly change
/// `complex`?". A `@extend` only rewrites a complex when one of its target
/// simples appears either DIRECTLY in a compound (matched by `collect_extenders`
/// via `Simple` equality) OR inside a selector-pseudo's argument at any depth
/// (rewritten in place by `expand_pseudos_in_compound`/`extend_pseudo`, which
/// only descend into [`is_selector_pseudo`] arguments). If NONE of `targets`
/// appears in either position, `extend_complex_breaks` is GUARANTEED to return
/// the complex unchanged — so the heavy `to_dart` + per-component scan can be
/// skipped. The match is exactly the union of the two sound sub-checks, so this
/// only returns `false` when the complex DEFINITELY cannot match (the byte-exact
/// ratchet and the Phase-1a guard catch any unsoundness immediately).
function complex_may_match_targets(
    complex: Complex,
    targets: map<string, bool>, /* key: Simple */
) -> bool {
    if (targets.length() == 0) {
        return false;
    }
    complex.components.some((comp: ComplexComponent) -> bool {
        comp.compound.simples.some((s: Simple) -> bool {
            targets.has(s.render())
        })
    })
        || pseudo_arg_has_target_deep(complex, targets)
}

/// Collect the EXACT set `S` of simples such that
/// `complex_may_match_targets(complex, {s})` is true: every `Simple` appearing
/// DIRECTLY in a compound, PLUS every `Simple` appearing inside a selector-pseudo
/// argument at ANY nesting depth. Mirrors [`complex_may_match_targets`] /
/// [`pseudo_arg_has_target_deep`] inverted (the membership predicate built into
/// an enumeration), so for any non-empty `targets`:
/// `complex_may_match_targets(complex, targets)` ==
/// `targets.iter().any(|t| collect_match_simples(complex).contains(t))`.
/// Used by the per-rule fold to skip a batch ALL of whose targets are absent from
/// the running selector list — a provably no-op (output- and budget-neutral)
/// batch, since `extend_list_batch` gates each complex by `can_match` BEFORE it
/// consumes any work budget.
function collect_match_simples(complex: Complex, out: map<string, bool>/* key: Simple */) -> void {
    for (let comp in complex.components) {
        for (let s in comp.compound.simples) {
            // Direct compound membership.
            let _ = out.set(s.render(), true);
            // Recurse into selector-pseudo arguments at any depth.
            let text = match (s) {
                Simple_Pseudo { _0: let t } => t,
                _ => null,
            };
            if (text == null) {
                continue;
            }
            let parts = parse_pseudo_parts(text);
            if (parts == null) {
                continue;
            }
            if (!is_selector_pseudo(parts.name)) {
                continue;
            }
            let list = root.selector.parse.parse_list(parts.arg);
            if (list != null) {
                for (let c in list) {
                    collect_match_simples(c, out);
                }
            }
        }
    }
}

/// Whether a pseudo name takes a selector list we should extend. `slotted` is
/// the selector-bearing pseudo-*element* (dart-sass `_selectorPseudoElements`).
function is_selector_pseudo(name: string) -> bool {
    let listed = match (unvendor(name)) {
        "not"
            | "is"
            | "matches"
            | "where"
            | "any"
            | "current"
            | "has"
            | "host"
            | "host-context"
            | "slotted" =>
        {
            true
        },
        _ => false,
    };
    listed || name.ends_with("-any")
}

/// Strip a CSS vendor prefix (`-pfx-is` → `is`), matching dart-sass `unvendor`,
/// so a vendor-prefixed selector pseudo is recognized. A `--custom` name or a
/// bare `-name` (no closing prefix dash) is returned unchanged.
function unvendor(name: string) -> string {
    // PORT: byte scan → char scan (`-` is ASCII, so the positions coincide).
    let bytes = name.chars();
    if (bytes.length() < 2 || bytes[0] != "-" || bytes[1] == "-") {
        return name;
    }
    let i = 2;
    while (i < bytes.length()) {
        if (bytes[i] == "-") {
            return name.slice(i + 1, bytes.length());
        }
        i += 1;
    }
    name
}

/// dart-sass `_extendList`: recursively extend a list of complex selectors,
/// dedup, and trim redundant superselectors. Used for pseudo arguments.
function extend_list(list: Complex[], extensions: Extension[]) -> Complex[] {
    let all_orig: bool[] = baml.Array.filled(list.length(), true);
    let r = extend_to_fixpoint_inner(list, [], all_orig, null, extensions, CartesianOrder.Fold, false);
    let result = r._0;
    let changed = r._1;
    // dart `_extendList`: when no complex was changed the ORIGINAL list is
    // returned untouched — no trim, duplicates preserved.
    if (!changed) {
        return root.std.clone_vec(list);
    }
    let source_spec = source_specificity_map(extensions);
    trim(
        result.map((t: root.std.Tuple3<Complex, bool, bool>) -> root.std.Tuple2<Complex, bool> {
            root.std.Tuple2<Complex, bool> { _0: t._0, _1: t._2 }
        }),
        source_spec,
    )
}

/// Build a single-extender [`Extension`] cloning `src`'s metadata. The `matched`
/// cell is SHARED (`Rc::clone`) so the `!optional` "not found" check still flips
/// when this split extension is applied to a selector.
function single_extension(
    src: Extension,
    target: Simple,
    extender: Complex,
    break_flag: bool,
) -> Extension {
    Extension {
        target: target,
        extenders: [extender],
        extender_breaks: [break_flag],
        optional: src.optional,
        // PORT: `Rc::clone` → shared alias.
        matched: src.matched,
        origin: src.origin,
        reg_idx: src.reg_idx,
        derived: false,
        via_origin: null,
        origin_closure: src.origin_closure,
    }
}

/// Register a transitively-derived extension (dart `extension.withExtender`):
/// `complex` becomes a new extender for `old`'s target unless already present
/// (then only the optional flag merges, mandatory winning). It is ALWAYS indexed
/// in the store (`sources`/`by_extender`) so a later `@extend` can chain onto it,
/// but only joins the current `batch` — dart's `additionalExtensions`, which
/// extend selectors in the SAME pass as the triggering extension — when its
/// target equals the triggering @extend's target (`batch_target_key`), per
/// dart's `if (newExtensions.containsKey(extension.target))`. In case 229 the
/// derived `b ← d c` (target `b`) must NOT extend `a b` alongside `a ← d`
/// (target `a`), or it would re-emit `d c` early and reorder the output.
function register_derived(
    registry: Extension[],
    sources: map<string, map<string, int>/* key: root.std.Tuple2<Complex, string> */>/* key: Simple */,
    by_extender: map<string, int[]>/* key: Simple */,
    batch: Extension[],
    batch_target: Simple,
    old: Extension,
    old_target: Simple,
    via: Extension,
    complex: Complex,
) -> void {
    // PORT: map keys — `Simple` → `render()`, `(Complex, String)` →
    // `complex.render() + "\0" + origin` (both renders are injective).
    assert_render_injective(complex);
    let empty_sources: map<string, int> = {};
    let target_sources = sources.get_or_insert(old_target.render(), empty_sources);
    let source_key = complex.render() + "\0" + old.origin;
    let found = target_sources.get(source_key);
    if (found != null) {
        let idx = found;
        if (!old.optional) {
            registry[idx].optional = false;
        }
        return;
    }
    let idx = registry.length();
    let simples: Simple[] = [];
    all_simples_of(complex, simples);
    let _ = target_sources.set(source_key, idx);
    // Woven/derived products carry no source line break (dart's lineBreak only
    // travels with the original extender object); the fold's flag plumbing keeps
    // an original's own flag separately.
    let derived = single_extension(old, old_target, complex, false);
    derived.derived = true;
    derived.via_origin = via.origin;
    derived.reg_idx = via.reg_idx;
    // PORT: `derived.clone()` — a distinct copy, so `registry[idx].optional = …`
    // later does not reach the batch entry.
    registry.push(Extension { ...derived });
    if (old_target == batch_target) {
        batch.push(derived);
    }
    for (let s in simples) {
        assert_simple_render_injective(s);
        let empty_idx: int[] = [];
        let _ = by_extender.get_or_insert(s.render(), empty_idx).push(idx);
    }
}

/// Faithful port of dart `ExtensionStore.addExtension` + `_extendExistingExtensions`
/// (extension_store.dart 242-399), grouped into BATCHES for sasso's 2-phase model.
///
/// dart registers `@extend`s one at a time in document order; each `addExtension`
/// (a) records the new `target ← extender` extension, (b) re-extends every
/// already-registered extension whose extender contains `target` by the new one
/// (registering those transitively-derived extensions too), then (c) extends all
/// matching selectors by the WHOLE new set — the triggering extension PLUS its
/// derived ones — in ONE `_extendList` pass (`mapAddAll2` +
/// `_extendExistingSelectors`). Applying the derived extensions in the same pass
/// (not as a separate later step) is what keeps the output order: a derived
/// `b ← d c` must extend `a b` together with `a ← d`, not after it.
///
/// So this returns one BATCH per input `@extend`: the new extensions it
/// registers (triggering + transitively-derived). A per-rule fold then applies
/// each batch as one multi-extension `_extendList`, reproducing dart's
/// registration-order output. The store (`sources`/`by_extender`) accumulates
/// across batches so a later `@extend` chains onto earlier derived extensions.
function expand_extensions(
    input: Extension[],
) -> root.std.Tuple3<Extension[][], Extension[], int[]> {
    // Flat registry of every registered single-extender extension, indexed by
    // `by_extender`/`sources` (dart `_extensions`/`_extensionsByExtender`). Also
    // returned for the pseudo path's legacy worklist, which needs the full set
    // (incl. derived extensions whose target differs from their trigger's, so no
    // batch applies them — e.g. `upstream <- :is(midstream, downstream)` for
    // dart#1297).
    // PORT: map keys — `Simple` → `render()`, `(Complex, String)` →
    // `complex.render() + "\0" + origin` (see `register_derived`).
    let registry: Extension[] = [];
    let sources: map<string, map<string, int>> = {};
    let by_extender: map<string, int[]> = {};
    let batches: Extension[][] = [];
    let registry_marks: int[] = [];
    // Store-wide source specificity (dart `_sourceSpecificity`, from the
    // original extenders) used to TRIM each transitively-derived extender just
    // as dart's `_extendCompound` does — without it a self-overlapping extender
    // (`.a` extended by `.a.mod1`) derives `.a.mod1.mod3`, `.a.mod1.mod3.mod5`,
    // … in a combinatorial blow-up (after_target:multiple_recursive). dart trims
    // each `.a.mod1.modN` away (covered by `.a.mod1` at equal specificity) before
    // it can become a registered extender, so the derivation terminates.
    let source_spec = source_specificity_map(input);
    // Every `@extend` target, for detecting a self-referential pseudo extender
    // (one whose `:not(...)`/`:has(...)` argument names a target — issue_2055).
    let all_targets: map<string, bool> = {};
    for (let e in input) {
        let t = e.target;
        if (t != null) {
            let _ = all_targets.set(t.render(), true);
        }
    }

    for (let ext in input) {
        let target_opt = ext.target;
        if (target_opt == null) {
            continue;
        }
        let target: Simple = target_opt;
        let target_key = target.render();
        // dart reads `_extensionsByExtender[target]` at the TOP of addExtension,
        // BEFORE this @extend's own extenders are registered, so it can never
        // re-extend itself. Snapshot it now.
        let existing: int[] = root.std.clone_vec(by_extender.get(target_key) ?? []);
        // dart `ExtensionStore.addSelector`: BEFORE this rule's `@extend` runs,
        // dart added the rule's own selector to the store, extending it by every
        // extension registered SO FAR (`selector = _extendList(selector,
        // _extensions)`). The extender passed to `addExtension` is therefore the
        // ALREADY-EXTENDED rule selector, not the raw one. sasso keeps the raw
        // extender per `@extend`, so reproduce `addSelector` here: pre-extend each
        // extender by the registry accumulated from earlier `@extend`s. This is
        // what gives issue_2055 its extra nesting — rule3's `:has(:not(.thing
        // [disabled]))` is registered as `:has(:not(.thing[disabled]):not(
        // [disabled]:not(.thing[disabled])))` because the earlier `:not(.thing
        // [disabled])` extension already extended its `.thing`. The pre-extension
        // is a no-op for the first `@extend` (empty registry) and for extenders
        // with no extendable simple — so issue_2399 (a single first `@extend`)
        // is untouched and stays shallow.
        // The `addSelector` pre-extension only changes the outcome for a
        // SELF-REFERENTIAL pseudo extender — one whose `:not(...)`/`:has(...)`
        // argument names a target (issue_2055). For a plain extender
        // (`.a.mod1`), the existing `_extendExistingExtensions` + application
        // fold already reproduce dart, and pre-extending there double-counts the
        // self-overlapping chains (`after_target:multiple_recursive` blows up).
        // So gate the pre-extension (and the self-inclusion below) to that case,
        // and trim like dart's `_extendList` so a derived super-broad extender
        // can't snowball.
        let self_ref_extender = ext.extenders.some((c: Complex) -> bool {
            pseudo_arg_has_target_deep(c, all_targets)
        });
        // Extensions the pre-extension below may apply: the store so far,
        // visibility-gated to what this `@extend`'s module can see (dart's
        // per-module stores).
        //
        // The gate usually drops nothing -- a sheet whose `@extend`s all come
        // from one module has one origin -- so check for that before cloning the
        // store. The block is what ends the borrow: the registration below
        // pushes to `registry`.
        let pre_extended: root.std.Tuple2<Complex, bool>[] = {
            // PORT: `Cow::Borrowed(&registry[..])` → an alias of `registry` (not
            // mutated inside this block); `Cow::Owned` → a filtered copy.
            let visible_registry: Extension[] = if (
                registry.every((r: Extension) -> bool {
                    ext.origin_closure.has(r.origin)
                })
            ) {
                registry
            } else {
                registry.filter((r: Extension) -> bool {
                    ext.origin_closure.has(r.origin)
                })
            };
            let out: root.std.Tuple2<Complex, bool>[] = [];
            let seen: map<string, bool> = {};
            let j = 0;
            for (let extender in ext.extenders) {
                let flag = ext.extender_breaks.at(j) ?? false;
                let products: Complex[] = if (registry.length() == 0) {
                    [extender]
                } else if (self_ref_extender) {
                    // dart `addSelector` = `_extendList(selector, _extensions)`.
                    // For a self-referential pseudo extender the extension is an
                    // in-place pseudo-argument rewrite (`:has(:not(.thing[…]))`
                    // becomes `:has(:not(.thing[…]):not([disabled]:not(…)))`), so
                    // it REPLACES the bare extender rather than coexisting — no
                    // top-level trim is needed and the `:not`/`:has` dedup inside
                    // `extend_complex` already bounds the recursion.
                    extend_complex(extender, registry)
                } else if (visible_registry.length() == 0) {
                    [extender]
                } else {
                    // dart `addSelector`: the rule's selector was ALREADY
                    // extended by every extension registered so far when its
                    // `@extend` runs, so the extender list arrives
                    // pre-extended in registration order — this is where
                    // chained extends get dart's FORWARD product order
                    // (bootstrap's navbar containers). Trim like `_extendList`
                    // so a product the original covers drops.
                    let empty: map<string, bool> = {};
                    trim(
                        extend_complex_breaks(
                            extender,
                            false,
                            true,
                            ext.origin,
                            visible_registry,
                            empty,
                            CartesianOrder.Fold,
                        )
                            .map((t: root.std.Tuple3<Complex, bool, bool>) -> root.std.Tuple2<Complex, bool> {
                                root.std.Tuple2<Complex, bool> { _0: t._0, _1: t._2 }
                            }),
                        source_spec,
                    )
                };
                for (let c in products) {
                    if (root.std.set_insert(seen, c.render())) {
                        out.push(root.std.Tuple2<Complex, bool> { _0: c, _1: flag });
                    }
                }
                j += 1;
            }
            out
        };
        // This @extend's new extensions (dart `newExtensionsByTarget`): the
        // triggering single-extender splits, then the derived ones below.
        let batch: Extension[] = [];
        let new_slice: Extension[] = [];
        for (let pe in pre_extended) {
            let extender = pe._0;
            let flag = pe._1;
            // Useless (multi-combinator) extenders are kept registered so the
            // extension is still applied — which marks the target "found" (so a
            // mandatory `@extend` doesn't wrongly error) — while the per-product
            // `is_useless` filter downstream drops what they'd generate. dart
            // tracks "found" via `_selectors[target]` independently; sasso flips
            // the shared `matched` cell during application, so the extension must
            // run. A single leading combinator (`> d`) is NOT useless and emits.
            assert_render_injective(extender);
            let empty_sources: map<string, int> = {};
            let target_sources = sources.get_or_insert(target_key, empty_sources);
            let source_key = extender.render() + "\0" + ext.origin;
            let found = target_sources.get(source_key);
            if (found != null) {
                // dart MergedExtension.merge: only the optional flag is
                // observable in this model — a mandatory extension wins.
                // Merging is PER-STORE (same origin); an identical extend
                // from another module keeps its own entry and rank.
                if (!ext.optional) {
                    registry[found].optional = false;
                }
                continue;
            }
            let idx = registry.length();
            let _ = target_sources.set(source_key, idx);
            let single = single_extension(ext, target, extender, flag);
            // PORT: `single.clone()` twice — distinct copies so a later
            // `registry[idx].optional = false` reaches only the registry entry.
            new_slice.push(Extension { ...single });
            batch.push(Extension { ...single });
            registry.push(single);
            let simples: Simple[] = [];
            all_simples_of(extender, simples);
            for (let s in simples) {
                assert_simple_render_injective(s);
                let empty_idx: int[] = [];
                let _ = by_extender.get_or_insert(s.render(), empty_idx).push(idx);
            }
        }
        // dart `_extendExistingExtensions`: re-extend each existing extender
        // (one whose extender contained `target`) by the new extension(s).
        //
        // dart snapshots `existingExtensions = _extensionsByExtender[target]` at
        // the TOP of `addExtension` and only enters this block when it was
        // NON-NULL (so the very first `@extend` for a target never re-extends —
        // issue_2399 stays shallow). But the snapshot is the LIVE list object,
        // and this `@extend`'s OWN extenders were appended to it (line above)
        // before `_extendExistingExtensions` reads `.toList()`. So when the block
        // runs, it iterates the EXISTING extenders PLUS this `@extend`'s own
        // extenders that contain `target`. That self-inclusion is what derives
        // issue_2055's deeper `:has(...)` (extender `[1]` re-extends its own
        // `.thing` by `[1]`). Derived extensions registered DURING the loop are
        // NOT re-processed (dart's `.toList()` is a one-time snapshot), so the
        // chain still terminates. dart gates the whole block on the TOP
        // snapshot being non-null, but `existingExtensions` is the LIVE
        // `_extensionsByExtender[target]` list and `.toList()` runs AFTER the
        // registration loop appended this @extend's own extenders — so an
        // extender that itself CONTAINS the target (`.z.x.y.c` extending
        // `.c`, extend-loop) is re-extended within its own registration, and
        // its derived products land in `additionalExtensions` (target ==
        // this batch's target) and apply in the same pass.
        let process: int[] = if (existing.length() == 0) {
            []
        } else {
            root.std.clone_vec(by_extender.get(target_key) ?? [])
        };
        if (new_slice.length() != 0 && process.length() != 0) {
            for (let old_idx in process) {
                if (!consume_extend_work()) {
                    break;
                }
                let old = Extension { ...registry[old_idx] };
                // Module visibility (dart per-module stores): a chain links only
                // when the NEW extension's origin is reachable from the OLD
                // extension's origin — the same `origin_closure.contains(origin)`
                // rule the old inline `collect_extenders` chaining used. Without
                // it, a sibling module's `@extend` would leak transitively
                // (directives/use/extend/*).
                if (!ext.origin_closure.has(old.origin)) {
                    continue;
                }
                let old_target_opt = old.target;
                if (old_target_opt == null) {
                    continue;
                }
                let old_target: Simple = old_target_opt;
                let old_extender = old.extenders[0];
                // dart `_extendComplex` trims its products (per `_extendCompound`),
                // so a derived extender covered by the original at equal-or-greater
                // specificity is dropped before registration — the bound that keeps
                // self-overlapping chains finite.
                let empty: map<string, bool> = {};
                let extended = trim(
                    extend_complex_breaks(old_extender, false, true, old.origin, new_slice, empty, CartesianOrder.Fold)
                        .map((t: root.std.Tuple3<Complex, bool, bool>) -> root.std.Tuple2<Complex, bool> {
                            root.std.Tuple2<Complex, bool> { _0: t._0, _1: t._2 }
                        }),
                    source_spec,
                );
                // dart: skip the first product when it's the unchanged extender.
                // PORT: `peekable()` → a start index.
                let start = 0;
                if (extended.at(0) == old_extender) {
                    start = 1;
                }
                for (let complex in extended.slice(start, extended.length())) {
                    register_derived(registry, sources, by_extender, batch, target, old, old_target, ext, complex);
                }
            }
        }
        if (batch.length() == 0) {
            // Every extender was dropped (trailing combinator) or this @extend
            // registered nothing new, yet the target must still be marked
            // "found" so a mandatory `@extend` doesn't wrongly error. Apply a
            // target-only marker: `collect_extenders` flips the shared `matched`
            // cell wherever the target appears, and emits no product. (dart
            // tracks "found" via `_selectors[target]`, independent of extenders.)
            batch.push(
                Extension {
                    target: target,
                    extenders: [],
                    extender_breaks: [],
                    optional: ext.optional,
                    matched: ext.matched,
                    origin: ext.origin,
                    reg_idx: ext.reg_idx,
                    derived: false,
                    via_origin: null,
                    origin_closure: ext.origin_closure,
                },
            );
        }
        batches.push(batch);
        registry_marks.push(registry.length());
    }
    root.std.Tuple3<Extension[][], Extension[], int[]> {
        _0: batches,
        _1: registry,
        _2: registry_marks,
    }
}

/// One fold step = dart `_extendList` against ONE registration's new extensions
/// (the `batch`): re-extend every selector in `list` by all of `batch` at once
/// (reusing the per-component cartesian/weave pipeline), then `_trim` with the
/// store-wide `source_spec`. When nothing changed the ORIGINAL list is returned
/// untouched (no trim, duplicates preserved — dart's `_extendList` returns its
/// input unchanged, keeping issue_2291 reparses).
///
/// Each selector carries the module ORIGIN that owns it (dart's per-module
/// extension stores): the batch — represented by its triggering `@extend`'s
/// origin/closure — only extends a selector whose origin it can SEE
/// (`closure.contains(origin)`), and a product brought in by the batch takes the
/// batch's origin. This blocks transitive cross-sibling leaks in a module
/// diamond: `left-extendee` (origin `left`) is not extended by a `right` module
/// `@extend`, since `right` doesn't use `left` (directives/use/extend/scope:*).
function extend_list_batch(
    list: root.std.Tuple4<Complex, bool, bool, string>[],
    batch: Extension[],
    orig_scope: string?,
    source_spec: map<string, int>, /* key: Simple */
) -> root.std.Tuple4<Complex, bool, bool, string>[] {
    // Representative origin of the batch (its triggering `@extend`). Every
    // single-extender split shares it; the rare derived entry keeps its source
    // module, but the batch as a whole is gated by the trigger's reach.
    let rep = batch.at(0);
    if (rep == null) {
        return root.std.clone_vec(list);
    }
    let batch_origin = rep.origin;
    let batch_closure = rep.origin_closure;
    // Which extenders carry a source line break (dart's
    // `ComplexSelector.lineBreak`), as a set of the flagged ones only. The
    // lookup at the point of use is a yes/no question, so a map from every
    // extender to a `bool` clones a `Complex` key to record `false` almost every
    // time; the flag is rare, and an absent key answers the question.
    //
    // It has to be built per store, from the entries that store holds. Building
    // one plan-level map instead is unsound: an extender registered twice with
    // different flags reads back the OR, so a store that holds only the
    // unflagged registration would see `true` -- and that flag decides a newline
    // in expanded output.
    // PORT: `FxHashSet<Complex>` → set keyed by `Complex::render()`.
    let ext_breaks: map<string, bool> = {};
    for (let ext in batch) {
        let j = 0;
        for (let c in ext.extenders) {
            if (ext.extender_breaks.at(j) ?? false) {
                let _ = ext_breaks.set(c.render(), true);
            }
            j += 1;
        }
    }
    // The batch's target simples, computed ONCE. A complex that mentions none of
    // them (directly or inside a selector-pseudo argument) cannot be changed by
    // this batch, so the per-complex `render()` + `to_dart`/`extend_complex_breaks`
    // is skipped entirely — this is the cut to the extend-heavy O(n^2) malloc.
    let batch_targets: map<string, bool> = {};
    for (let e in batch) {
        let t = e.target;
        if (t != null) {
            let _ = batch_targets.set(t.render(), true);
        }
    }
    let out: root.std.Tuple3<Complex, bool, bool>[] = [];
    // complex -> owning origin, also serving as the `seen` set (a key's presence
    // marks it emitted). Keyed by `Hashed<Complex>` so each product's `Complex`
    // tree is walked ONCE (at `Hashed::new`) and reused for the entry probe AND
    // the post-trim origin lookup, instead of the derived `Complex` `Hash`
    // re-walking components→compounds→simples→`String` on every map operation.
    // (Phase-1a proved typed `Complex` keys partition identically to `render()`;
    // `Hashed` keeps `Eq` structural so the partition is byte-identical.)
    // PORT: `FxHashMap<Hashed<Complex>, String>` → map keyed by `Complex::render()`.
    let origin_of: map<string, string> = {};
    let changed = false;
    for (let item in list) {
        let complex = item._0;
        let in_break = item._1;
        let c_orig = item._2;
        let c_origin = item._3;
        let visible = batch_closure.has(c_origin);
        // Cheap sound pre-filter: a complex containing none of the batch's
        // targets is GUARANTEED unchanged, so pass it through without `render()`,
        // `to_dart`, or `extend_complex_breaks`.
        let can_match = visible && complex_may_match_targets(complex, batch_targets);
        let products = if (can_match && consume_extend_work() && out.length() <= 100_000) {
            extend_complex_breaks(complex, in_break, c_orig, orig_scope, batch, ext_breaks, CartesianOrder.Fold)
        } else {
            [root.std.Tuple3<Complex, bool, bool> { _0: complex, _1: in_break, _2: c_orig }]
        };
        if (can_match && !(products.length() == 1 && products[0]._0 == complex)) {
            changed = true;
        }
        for (let p in products) {
            let c = p._0;
            let f = p._1;
            let o_flag = p._2;
            // The unchanged self-copy keeps its origin; a genuinely new product
            // takes the batch's origin so further batches gate against it. An
            // ORIGINAL instance always joins `out` even when a value-equal
            // product came first (dart's identity `_originals`; the coverage
            // trim resolves the pair in the original's favor).
            let key = c.render();
            if (!origin_of.has(key)) {
                let o = if (c == complex) {
                    c_origin
                } else {
                    batch_origin
                };
                let _ = origin_of.set(key, o);
                out.push(root.std.Tuple3<Complex, bool, bool> { _0: c, _1: f, _2: o_flag });
            } else {
                if (o_flag) {
                    out.push(root.std.Tuple3<Complex, bool, bool> { _0: c, _1: f, _2: o_flag });
                }
            }
        }
    }
    if (!changed) {
        return root.std.clone_vec(list);
    }
    trim_breaks(out, source_spec).map((t: root.std.Tuple3<Complex, bool, bool>) -> root.std.Tuple4<Complex, bool, bool, string> {
        let key = t._0.render();
        let o = origin_of.delete(key) ?? batch_origin;
        root.std.Tuple4<Complex, bool, bool, string> { _0: t._0, _1: t._1, _2: t._2, _3: o }
    })
}

/// Run the extension to a fixpoint: extend each selector, then feed every
/// newly-produced selector back through extension until nothing new appears.
/// This realizes dart-sass's extension-graph behavior where an extender produced
/// by one `@extend` can itself be extended by another (transitively, including
/// targets buried in pseudo arguments). Bounded to guarantee termination.
/// Threads per-selector line-break flags (each product carries its input's
/// flag OR any contributing extender's) and reports whether ANY input complex
/// was changed by an extension — dart `_extendList` returns the original list
/// untouched when nothing changed.
function extend_to_fixpoint_breaks(
    list: Complex[],
    list_breaks: bool[],
    list_origs: bool[],
    orig_scope: string?,
    extensions: Extension[],
    order: CartesianOrder,
) -> root.std.Tuple2<root.std.Tuple3<Complex, bool, bool>[], bool> {
    extend_to_fixpoint_inner(list, list_breaks, list_origs, orig_scope, extensions, order, true)
}

/// As [`extend_to_fixpoint_breaks`], with explicit control over re-feeding a
/// freshly-produced pseudo-bearing selector. dart's `_extendList` is a SINGLE
/// pass over the components; ALL nested extension comes from `_extendPseudo`
/// recursing back into `_extendList` on a pseudo's argument. A pseudo ARGUMENT
/// therefore must NOT also re-feed at the list level: doing so runs a redundant
/// extra fixpoint at every recursion level, multiplying the work geometrically
/// with depth (the self-referential `:not`/`:has` blowup that exhausted the
/// budget in issue_2055). The top-level selector list keeps the re-feed, which
/// resolves a few plain transitive chains a lone pass misses.
function extend_to_fixpoint_inner(
    list: Complex[],
    list_breaks: bool[],
    list_origs: bool[],
    orig_scope: string?,
    extensions: Extension[],
    order: CartesianOrder,
    refeed: bool,
) -> root.std.Tuple2<root.std.Tuple3<Complex, bool, bool>[], bool> {
    // Extender flags by extender selector, for the per-option lookup: the
    // flagged extenders only, and built from this store rather than hoisted (see
    // the same set in `extend_list_batch`).
    // PORT: `FxHashSet<Complex>` → set keyed by `Complex::render()`.
    let ext_breaks: map<string, bool> = {};
    for (let ext in extensions) {
        let j = 0;
        for (let c in ext.extenders) {
            if (ext.extender_breaks.at(j) ?? false) {
                let _ = ext_breaks.set(c.render(), true);
            }
            j += 1;
        }
    }
    let result: root.std.Tuple3<Complex, bool, bool>[] = [];
    let seen: map<string, bool> = {};
    let changed = false;
    // Worklist of selectors still to extend. `is_input` marks a caller-seeded
    // entry (its unchanged round-trip doesn't count as a change); `is_orig`
    // is the ORIGINAL-INSTANCE flag (dart's identity `_originals`), carried
    // through to the first product of each round-trip.
    // PORT: `VecDeque` + `pop_front` → array + read cursor `qi` (same FIFO order).
    let queue: root.std.Tuple4<Complex, bool, bool, bool>[] = [];
    let i = 0;
    for (let c in list) {
        queue.push(
            root.std.Tuple4<Complex, bool, bool, bool> {
                _0: c,
                _1: list_breaks.at(i) ?? false,
                _2: true,
                _3: list_origs.at(i) ?? true,
            },
        );
        i += 1;
    }
    let qi = 0;
    while (qi < queue.length()) {
        let item = queue[qi];
        qi += 1;
        let complex = item._0;
        let in_break = item._1;
        let is_input = item._2;
        let is_orig = item._3;
        if (!consume_extend_work() || result.length() > 100_000) {
            break;
        }
        let products = extend_complex_breaks(complex, in_break, is_orig, orig_scope, extensions, ext_breaks, order);
        if (is_input && !(products.length() == 1 && products[0]._0.render() == complex.render())) {
            changed = true;
        }
        for (let p in products) {
            let c = p._0;
            let flag = p._1;
            let orig = p._2;
            let rendered = c.render();
            // PORT: `String::len()` is the UTF-8 byte length.
            let len = rendered.byte_length();
            // An ORIGINAL instance always joins the result even when a
            // value-equal PRODUCT came first: dart's identity `_originals`
            // keeps both until `_trim`, where the product (not identity-
            // original) is coverage-dropped and the original survives at its
            // own position with its own line break.
            if (root.std.set_insert(seen, rendered) || orig) {
                // Re-extend a freshly-produced selector only when it carries a
                // selector-bearing pseudo: that's the sole case where a second
                // pass can reveal *more* extensions (a target buried in a
                // pseudo argument that became extendable, or an extender pseudo
                // that is itself a target). Plain class/placeholder/type chains
                // are resolved transitively in a single pass by
                // `collect_extenders` (including multi-component extenders via
                // the visible-store re-extension), so re-feeding them would
                // only risk re-deriving cyclic self-extends without producing
                // anything new. An over-long selector (a self-referential
                // blowup) is emitted but not re-fed.
                if (refeed && complex_has_selector_pseudo(c) && len <= EXTEND_REFEED_MAX_LEN()) {
                    queue.push(
                        root.std.Tuple4<Complex, bool, bool, bool> {
                            _0: c,
                            _1: flag,
                            _2: false,
                            _3: false,
                        },
                    );
                }
                result.push(root.std.Tuple3<Complex, bool, bool> { _0: c, _1: flag, _2: orig });
            }
        }
    }
    root.std.Tuple2<root.std.Tuple3<Complex, bool, bool>[], bool> { _0: result, _1: changed }
}

/// dart-sass `_extendPseudo`: extend the selector argument of a selector-bearing
/// pseudo. Returns the replacement simple selectors for this pseudo position, or
/// `None` if nothing changed (keep the original simple unchanged).
///
/// For `:not()` with a single-complex original argument, the result is the set of
/// `:not()` simples to merge into the surrounding compound (older browsers can't
/// parse a complex/compound inside `:not`, so each becomes its own `:not`). For
/// every other pseudo (and `:not` whose argument was already a list), the result
/// is a single rewritten pseudo carrying the extended argument list.
// Recursion guard for nested pseudo-argument extension. A target that is itself
// a selector-pseudo containing the extended selector (`:not(.c) {@extend .c}`)
// would otherwise recurse without bound through `extend_pseudo` → `extend_list`
// → ... → `extend_pseudo`. dart-sass bounds this implicitly via its
// target-tracking; a small fixed depth covers every real case while keeping the
// engine total.
function MAX_PSEUDO_DEPTH() -> int {
    8
}

// PORT: `thread_local! { static PSEUDO_DEPTH: Cell<usize> = Cell::new(0) }`.
// BAML has no globals or thread-locals; a top-level `client` declaration is the
// only top-level value (evaluated once, then shared), so it holds the mutable
// cell and `PSEUDO_DEPTH()` hands it out: `PSEUDO_DEPTH.with(|d| d.get())` →
// `PSEUDO_DEPTH().get()`, `…d.set(x)` → `PSEUDO_DEPTH().set(x)`. The state is
// process-wide rather than per-thread (the port is single-threaded here).
client PSEUDO_DEPTH_CELL = root.std.Cell<int> { value: 0 };

function PSEUDO_DEPTH() -> root.std.Cell<int> {
    PSEUDO_DEPTH_CELL
}

// Global work budget for one top-level extend operation, shared by every
// recursion level (pseudo arguments re-enter the fixpoint via `extend_pseudo*`).
// The per-level iteration caps alone don't bound the COMBINED work: a
// self-referential extension (`:not(.c) {@extend .c}`, issue 2055/2399) makes
// each of the 8 pseudo levels run its own near-full fixpoint over selectors
// whose rendered length doubles every generation — astronomically slow even
// though technically finite. Legitimate stylesheets use a few hundred units at
// most, so exhaustion only truncates pathological self-referential output.
function EXTEND_WORK_BUDGET() -> int {
    20_000
}

/// A produced selector longer than this is still emitted but not re-fed for
/// further extension (real transitive outputs stay around ~2 KB; unbounded
/// re-feeding doubles the length every generation).
function EXTEND_REFEED_MAX_LEN() -> int {
    8_192
}

// PORT: `thread_local! { static EXTEND_WORK: Cell<usize> = Cell::new(EXTEND_WORK_BUDGET) }`
// → a `client`-held process-wide cell, as for `PSEUDO_DEPTH` above:
// `EXTEND_WORK.with(|w| w.get())` → `EXTEND_WORK().get()`,
// `EXTEND_WORK.with(|w| w.set(x))` → `EXTEND_WORK().set(x)`.
client EXTEND_WORK_CELL = root.std.Cell<int> { value: EXTEND_WORK_BUDGET() };

function EXTEND_WORK() -> root.std.Cell<int> {
    EXTEND_WORK_CELL
}

/// Refill the work budget when entering extension at the top level (recursive
/// pseudo-argument entries run under `PSEUDO_DEPTH > 0` and share the budget).
function reset_extend_budget() -> void {
    if (PSEUDO_DEPTH().get() == 0) {
        EXTEND_WORK().set(EXTEND_WORK_BUDGET());
    }
}

/// Consume one unit of extension work; `false` once the budget is exhausted
/// (callers stop draining their worklist, keeping the results produced so far).
function consume_extend_work() -> bool {
    let w = EXTEND_WORK();
    let left = w.get();
    if (left == 0) {
        return false;
    }
    w.set(left - 1);
    true
}

function extend_pseudo(text: string, extensions: Extension[]) -> Simple[]? {
    let parts = parse_pseudo_parts(text);
    if (parts == null) {
        return null;
    }
    if (!is_selector_pseudo(parts.name)) {
        return null;
    }
    if (PSEUDO_DEPTH().get() >= MAX_PSEUDO_DEPTH()) {
        return null;
    }
    let original = root.selector.parse.parse_list(parts.arg);
    if (original == null) {
        return null;
    }
    PSEUDO_DEPTH().set(PSEUDO_DEPTH().get() + 1);
    let extended = extend_list(original, extensions);
    PSEUDO_DEPTH().set(PSEUDO_DEPTH().get() - 1);
    finish_extend_pseudo(parts, original, extended)
}

/// The `selector.extend`/`selector.replace` compound-target counterpart of
/// [`extend_pseudo`]: recursively extend a selector-pseudo's argument list in
/// the compound-target model so `extend(":is(.c)", ".c", ".d")` -> `:is(.c,
/// .d)`.
function extend_pseudo_compound_target(
    text: string,
    targets: Compound[],
    extenders: Complex[],
    replace: bool,
) -> Simple[]? {
    if (PSEUDO_DEPTH().get() >= MAX_PSEUDO_DEPTH()) {
        return null;
    }
    // `:nth-child(An+B of <selector>)` extends only its `of` selector.
    let nth = nth_of_parts(text);
    if (nth != null) {
        let name = nth._0;
        let anb = nth._1;
        let sel = nth._2;
        let original = root.selector.parse.parse_list(sel);
        if (original == null) {
            return null;
        }
        PSEUDO_DEPTH().set(PSEUDO_DEPTH().get() + 1);
        let extended = extend_compound_target(original, targets, extenders, replace);
        PSEUDO_DEPTH().set(PSEUDO_DEPTH().get() - 1);
        return finish_nth_of(name, anb, original, extended);
    }
    let parts = parse_pseudo_parts(text);
    if (parts == null) {
        return null;
    }
    if (!is_selector_pseudo(parts.name)) {
        return null;
    }
    let original = root.selector.parse.parse_list(parts.arg);
    if (original == null) {
        return null;
    }
    PSEUDO_DEPTH().set(PSEUDO_DEPTH().get() + 1);
    let extended = extend_compound_target(original, targets, extenders, replace);
    PSEUDO_DEPTH().set(PSEUDO_DEPTH().get() - 1);
    finish_extend_pseudo(parts, original, extended)
}

/// Re-wrap an extended `:nth-child(An+B of …)` selector list, or `None` when the
/// `of` selector was unchanged. A nested same-`(name, An+B)` nth pseudo produced
/// by the extension is unwrapped to its own `of` selectors (dart-sass merges
/// them); a different-`(name, An+B)` one is dropped (it can't be combined).
function finish_nth_of(
    name: string,
    anb: string,
    original: Complex[],
    extended: Complex[],
) -> Simple[]? {
    let flattened: Complex[] = [];
    let seen: map<string, bool> = {};
    let push = (c: Complex, flattened: Complex[]) -> void {
        if (root.std.set_insert(seen, c.render())) {
            flattened.push(c);
        }
    };
    for (let c in extended) {
        // PORT: `match single_pseudo(&c).and_then(nth_of_parts)` → if/else.
        let sp = single_pseudo(c);
        let nth: root.std.Tuple3<string, string, string>? = if (sp != null) {
            nth_of_parts(sp)
        } else {
            null
        };
        if (nth != null) {
            if (nth._0 == name && nth._1 == anb) {
                // Merge a nested same-`(name, An+B)` nth pseudo's own `of`
                // selectors (deduping so a self-referential extension settles).
                let list = root.selector.parse.parse_list(nth._2);
                if (list != null) {
                    for (let inner in list) {
                        push(inner, flattened);
                    }
                }
            }
            // A nested nth pseudo with a different name or An+B can't merge.
        } else {
            push(c, flattened);
        }
    }
    if (flattened.length() == original.length()) {
        // PORT: `zip(..).all(..)` → index loop.
        let all_same = true;
        let k = 0;
        while (k < flattened.length()) {
            if (flattened[k].render() != original[k].render()) {
                all_same = false;
                break;
            }
            k += 1;
        }
        if (all_same) {
            return null;
        }
    }
    let inner = root.std.join(
        flattened.map((c: Complex) -> string {
            c.render()
        }),
        ", ",
    );
    if (inner == "") {
        return null;
    }
    let pseudo: Simple = Simple_Pseudo { _0: `${name}(${anb} of ${inner})` };
    [pseudo]
}

/// The verbatim pseudo text when `complex` is a single component holding a
/// single pseudo simple (`:nth-child(…)`), else `None`.
function single_pseudo(complex: Complex) -> string? {
    // PORT: slice patterns `let [x] = … else` → length checks.
    if (complex.components.length() != 1) {
        return null;
    }
    let comp = complex.components[0];
    if (comp.compound.simples.length() != 1) {
        return null;
    }
    match (comp.compound.simples[0]) {
        Simple_Pseudo { _0: let text } => text,
        _ => null,
    }
}

/// Selector-pseudo extension of every pseudo in `compound` in the
/// compound-target model (the `selector.extend`/`replace` counterpart of
/// [`expand_pseudos_in_compound`]).
function expand_pseudos_compound_target(
    compound: Compound,
    targets: Compound[],
    extenders: Complex[],
    replace: bool,
) -> Compound {
    let simples: Simple[] = [];
    for (let s in compound.simples) {
        match (s) {
            let p: Simple_Pseudo => {
                // An UNCHANGED pseudo keeps duplicates (`:baz:baz` is valid
                // CSS). A replacement's products dedup against what's already
                // pushed AND against the other ORIGINAL simples (which the
                // unchanged path will keep verbatim later).
                let replacement = extend_pseudo_compound_target(p._0, targets, extenders, replace);
                if (replacement == null) {
                    simples.push(s);
                } else {
                    for (let r in replacement) {
                        let dup_of_other_original = r != s
                            && compound.simples.some((o: Simple) -> bool {
                                o != s && o == r
                            });
                        if (dup_of_other_original || root.std.contains(simples, r)) {
                            continue;
                        }
                        simples.push(r);
                    }
                }
            },
            _ => {
                simples.push(s);
            },
        }
    }
    Compound { simples: simples }
}

/// Shared post-processing for [`extend_pseudo`] and
/// [`extend_pseudo_compound_target`]: given the original and extended argument
/// lists, build the replacement simple selector(s) (the `:not` split, nested
/// pseudo unwrap, and matchish-pseudo re-wrap).
function finish_extend_pseudo(
    parts: PseudoParts,
    original: Complex[],
    extended: Complex[],
) -> Simple[]? {
    // Nothing changed.
    // PORT: the `zip(..).all(render ==)` is a comparison of the rendered lists.
    if (
        extended.length() == original.length()
            && extended.map((a: Complex) -> string {
                a.render()
            })
                == original.map((b: Complex) -> string {
                    b.render()
                })
    ) {
        return null;
    }

    // For `:not`, drop complex selectors from the extension result unless the
    // original argument itself contained a complex selector (otherwise we'd
    // produce a `:not()` no browser can parse). We can keep them if every
    // extension result is complex, since then nothing already-working breaks.
    let original_has_complex = original.some((c: Complex) -> bool {
        c.components.length() > 1
    });
    let complexes: Complex[] = if (
        parts.name == "not"
            && !original_has_complex
            && extended.some((c: Complex) -> bool {
                c.components.length() == 1
            })
    ) {
        extended.filter((c: Complex) -> bool {
            c.components.length() <= 1
        })
    } else {
        extended
    };

    // Unwrap nested matching pseudos in single-compound results, mirroring
    // dart-sass: e.g. for `:not`, a result `:is(...)`/`:matches`/`:where` is
    // unwrapped to its inner selectors; for matchish pseudos, a result of the
    // same name+argument is likewise unwrapped.
    let unwrapped: Complex[] = [];
    // PORT: `complexes.drain(..)` → plain iteration (the drained vec is not reused).
    for (let complex in complexes) {
        let inner = single_pseudo_inner(complex, parts.name);
        match (inner) {
            let _k: PseudoUnwrap_Keep => {
                unwrapped.push(complex);
            },
            let _d: PseudoUnwrap_Drop => {},
            let list: PseudoUnwrap_Replace => {
                root.std.extend(unwrapped, list._0);
            },
            _ => {
                root.std.unreachable();
            },
        }
    }
    let complexes = unwrapped;

    // `:not` with a single-complex original argument splits into separate
    // `:not()` simples merged into the surrounding compound.
    if (parts.name == "not" && original.length() == 1) {
        let result: Simple[] = complexes.map((c: Complex) -> Simple {
            Simple_Pseudo { _0: `${parts.head}(${c.render()})` }
        });
        if (result.length() == 0) {
            return null;
        }
        return result;
    }

    if (complexes.length() == 0) {
        return null;
    }
    // Dedup the rewritten argument list so a second extension pass (our
    // worklist re-feed; dart-sass extends in a single simultaneous pass)
    // settles instead of appending the same selectors again.
    let seen: map<string, bool> = {};
    let rendered: string[] = complexes
        .map((c: Complex) -> string {
            c.render()
        })
        .filter((r: string) -> bool {
            root.std.set_insert(seen, r)
        });
    if (
        rendered.length() == original.length()
            && rendered
                == original.map((b: Complex) -> string {
                    b.render()
                })
    ) {
        return null;
    }
    let rewrapped: Simple = Simple_Pseudo { _0: `${parts.head}(${rendered.join(", ")})` };
    [rewrapped]
}

interface PseudoUnwrap {}

/// Keep the complex as-is.
class PseudoUnwrap_Keep {
    implements PseudoUnwrap {}
}

/// Drop the complex (nested pseudo we can't safely unwrap).
class PseudoUnwrap_Drop {
    implements PseudoUnwrap {}
}

/// Replace with these inner complex selectors.
class PseudoUnwrap_Replace {
    _0: Complex[],
    implements PseudoUnwrap {}
}

/// For a single-compound complex whose sole simple is a nested selector-pseudo,
/// decide how `_extendPseudo` should treat it relative to the outer pseudo
/// `outer_name`.
function single_pseudo_inner(complex: Complex, outer_name: string) -> PseudoUnwrap {
    if (complex.components.length() != 1) {
        return PseudoUnwrap_Keep {  };
    }
    let compound = complex.components[0].compound;
    if (compound.simples.length() != 1) {
        return PseudoUnwrap_Keep {  };
    }
    let text = match (compound.simples[0]) {
        let p: Simple_Pseudo => p._0,
        _ => {
            return PseudoUnwrap_Keep {  };
        },
    };
    let inner = parse_pseudo_parts(text);
    if (inner == null) {
        return PseudoUnwrap_Keep {  };
    }
    let inner_list = root.selector.parse.parse_list(inner.arg);
    if (inner_list == null) {
        return PseudoUnwrap_Keep {  };
    }
    match (unvendor(outer_name)) {
        "not" => {
            // `:not(:is(...))` etc. unwraps; other nested pseudos can't be
            // expanded (each layer adds semantics) so the selector is dropped.
            let inner_base = unvendor(inner.name);
            if (inner_base == "is" || inner_base == "matches" || inner_base == "where") {
                PseudoUnwrap_Replace { _0: inner_list }
            } else {
                PseudoUnwrap_Drop {  }
            }
        },
        "is" | "matches" | "where" | "any" | "current" | "nth-child" | "nth-last-child" => {
            // The names must match *including* any vendor prefix to merge
            // (`:-ms-matches` and `:-moz-matches` don't combine).
            if (inner.name == outer_name) {
                PseudoUnwrap_Replace { _0: inner_list }
            } else {
                PseudoUnwrap_Drop {  }
            }
        },
        _ => PseudoUnwrap_Keep {  },
    }
}

/// Expand selector-pseudo arguments inside a compound in place, returning the
/// effective compound. `:not()` (single-complex arg) contributes extra `:not()`
/// simples merged at the pseudo's position; other matchish pseudos rewrite their
/// argument list. Non-pseudo simples and argument-less pseudos pass through.
function expand_pseudos_in_compound(compound: Compound, extensions: Extension[]) -> Compound {
    let simples: Simple[] = [];
    // A `:not()` expanded from one simple may collide with another `:not()`
    // already present in the compound (e.g. `:not(.c)` extends `.c`→`.b` while a
    // sibling `:not(.b)` is also present). Dedup pseudo simples so the expansion
    // is idempotent and the fixpoint terminates.
    for (let s in compound.simples) {
        match (s) {
            let p: Simple_Pseudo => {
                // An UNCHANGED pseudo keeps duplicates (`:baz:baz` is valid
                // CSS). A replacement's products dedup against what's already
                // pushed AND against the other ORIGINAL simples (which the
                // unchanged path will keep verbatim later).
                let replacement = extend_pseudo(p._0, extensions);
                if (replacement == null) {
                    simples.push(s);
                } else {
                    for (let r in replacement) {
                        let dup_of_other_original = r != s
                            && compound.simples.some((o: Simple) -> bool {
                                o != s && o == r
                            });
                        if (dup_of_other_original || root.std.contains(simples, r)) {
                            continue;
                        }
                        simples.push(r);
                    }
                }
            },
            _ => {
                simples.push(s);
            },
        }
    }
    Compound { simples: simples }
}

function extend_component(
    comp: TComp,
    extensions: Extension[],
    ext_breaks: map<string, bool>/* key: Complex */,
    order: CartesianOrder,
) -> root.std.Tuple2<DComplex, bool>[]? {
    // First, extend any selector-pseudo arguments (`:not(...)`, `:is(...)`,
    // etc.) in place, producing an "effective" compound. For `:not()` with a
    // single-complex argument this *adds* simples to the compound (dart-sass
    // `_extendPseudo` merges them rather than creating an alternative);
    // matchish pseudos (`:is`/`:matches`/`:where`/...) rewrite their argument
    // list in place. The resulting compound is then run through the normal
    // per-simple extension below.
    let effective = expand_pseudos_in_compound(comp.compound, extensions);
    // The component changed if a pseudo argument was extended in place (e.g.
    // `:not(.c)` → `:not(.c):not(.a)`) even when no simple has an extender.
    let pseudo_changed = effective.simples != comp.compound.simples;
    let comp = TComp { compound: effective, combinators: root.std.clone_vec(comp.combinators) };
    // PORT: `let comp = &comp;` needs no counterpart.
    let simples = comp.compound.simples;
    // Per-simple option list: index 0 is "keep self" (None); the rest are
    // (transitively expanded) extender complex selectors targeting this simple.
    let per_simple: (root.std.Tuple2<Complex, bool>?)[][] = [];
    let any = false;
    for (let s in simples) {
        let opts: (root.std.Tuple2<Complex, bool>?)[] = [null];
        // key: Complex (`render()`)
        let seen: map<string, bool> = {};
        for (let extender in collect_extenders(s, extensions, [])) {
            // PORT: the `Complex` set key is its `render()`, computed once.
            let key = extender.render();
            if (seen.has(key)) {
                continue;
            }
            // The extender's source line-break flag travels with the option
            // (dart's ComplexSelector.lineBreak).
            let flag = ext_breaks.has(key);
            root.std.set_insert(seen, key);
            opts.push(root.std.Tuple2 { _0: extender, _1: flag });
            any = true;
        }
        per_simple.push(opts);
    }
    // The original component is always the first option (dart-sass keeps it so
    // the rule still matches what it always matched; `_trim` may drop it later
    // for non-originals).
    let options_first = DComplex { leading: [], comps: [comp] };
    if (!any) {
        // No simple has an extender; the component only "changed" if a pseudo
        // argument was rewritten in place.
        return if (pseudo_changed) {
            [root.std.Tuple2 { _0: options_first, _1: false }]
        } else {
            null
        };
    }
    let options: root.std.Tuple2<DComplex, bool>[] = [root.std.Tuple2 { _0: options_first, _1: false }];

    // Cartesian product of per-simple choices. The incremental (registration-
    // order) fold varies the FIRST simple slowest (path outer, option inner) —
    // `.foo.bar` + two extends -> `.foo.bar, .foo.bang, .bar.baz, .baz.bang`.
    // dart's one-shot `_extendCompound` uses literal `paths(options)`: the LAST
    // simple varies SLOWEST (option outer, path inner) — the order that unifies
    // `:not(c):not(d)`/`.e.f` rule-after-extends to match dart.
    let paths: (root.std.Tuple2<Complex, bool>?)[][] = [[]];
    for (let opts in per_simple) {
        let next: (root.std.Tuple2<Complex, bool>?)[][] = [];
        if (order == CartesianOrder.OneShot) {
            for (let opt in opts) {
                for (let path in paths) {
                    let p = root.std.clone_vec(path);
                    p.push(opt);
                    next.push(p);
                }
            }
        } else {
            for (let path in paths) {
                for (let opt in opts) {
                    let p = root.std.clone_vec(path);
                    p.push(opt);
                    next.push(p);
                }
            }
        }
        paths = next;
        if (paths.length() > 100_000) {
            break;
        }
    }

    let seen: map<string, bool> = {};
    root.std.set_insert(seen, render_dcomplex(options[0]._0));
    for (let path in paths) {
        // Skip the all-self path (the original compound, already option 0).
        if (
            path.every((o: root.std.Tuple2<Complex, bool>?) -> bool {
                o == null
            })
        ) {
            continue;
        }
        // The option's flag is the OR of the contributing extenders' flags.
        let flag = path.some((o: root.std.Tuple2<Complex, bool>?) -> bool {
            o?._1 ?? false
        });
        let plain: (Complex?)[] = path.map((o: root.std.Tuple2<Complex, bool>?) -> Complex? {
            o?._0
        });
        // PORT: `refs: Vec<&Option<Complex>>` is `plain` itself.
        let refs = plain;
        for (let d in build_extended_compound(comp, simples, refs)) {
            let key = render_dcomplex(d);
            if (root.std.set_insert(seen, key)) {
                options.push(root.std.Tuple2 { _0: d, _1: flag });
            }
        }
    }
    options
}

/// Collect every extender complex selector for `target`, transitively: a direct
/// extender that is itself a target of another extension is expanded into its
/// own extenders too. `stack` guards against extension cycles.
/// Collect the direct extenders registered for `target`, in registration
/// order (dart-sass `_extendSimple` iterates `extensions[simple].values`). This
/// is now a DIRECT lookup: transitivity (an extender that is itself a target)
/// is precomputed by [`expand_extensions`] into the batch the caller passes, so
/// chasing chains here would double-expand. `stack` is unused (kept for the call
/// signature) now that recursion is gone.
function collect_extenders(
    target: Simple,
    extensions: Extension[],
    unused_stack: Simple[],
) -> Complex[] {
    let out: Complex[] = [];
    for (let ext in extensions) {
        let t = ext.target;
        if (t == null) {
            continue;
        }
        if (t != target) {
            continue;
        }
        ext.matched.set(true);
        for (let extender in ext.extenders) {
            out.push(extender);
        }
    }
    out
}

/// Build the extended component sequences for one within-compound product path.
/// `path[i]` is `None` to keep `simples[i]`, or `Some(extender)` to replace it.
/// The self-kept simples form an "original" compound that is unified together
/// with every chosen extender via dart-sass `_unifyExtenders`/`unifyComplex`,
/// which weaves any multi-component extenders (including several at once). The
/// original component's incoming combinator is attached to each result's first
/// component. May return several sequences (one per woven unification).
function build_extended_compound(comp: TComp, simples: Simple[], path: (Complex?)[]) -> DComplex[] {
    // Self-kept simples (originals not being extended) and the chosen extenders.
    let base: Simple[] = [];
    let extenders: Complex[] = [];
    let i = 0;
    for (let choice in path) {
        if (choice == null) {
            base.push(simples[i]);
        } else {
            extenders.push(choice);
        }
        i += 1;
    }

    // `_unifyExtenders`: the self-kept base compound (if any) is an "original"
    // selector unified first, then each extender complex.
    let to_unify: DComplex[] = [];
    if (base.length() > 0) {
        to_unify.push(
            DComplex {
                leading: [],
                comps: [TComp { compound: Compound { simples: base }, combinators: [] }],
            },
        );
    }
    for (let ext in extenders) {
        let d = to_dart(ext);
        // dart-sass `_unifyExtenders`: a useless extender fails the whole path.
        if (d.is_useless()) {
            return [];
        }
        to_unify.push(d);
    }

    let unified = unify_complex_list(to_unify);
    if (unified == null) {
        return [];
    }

    // dart-sass: each unified result gets the original component's trailing
    // combinator run appended (`withAdditionalCombinators`); results that
    // become useless are dropped.
    unified
        .map((complex: DComplex) -> DComplex {
            complex.with_additional_combinators(comp.combinators)
        })
        .filter((complex: DComplex) -> bool {
            !complex.is_useless()
        })
}

/// Render a dart-model complex selector to a stable string key (for dedup).
function render_dcomplex(d: DComplex) -> string {
    from_dart(d).render()
}

/// Unify a `base` compound with `extra` (the extender's trailing compound),
/// returning the combined compound or `None` if they can't unify. A faithful
/// port of dart-sass `unifyCompound`: start from `base`, then fold each `extra`
/// simple in via `simple_unify`, keeping pseudo-classes after a pseudo-element
/// in `pseudo_result` to preserve their relative order.
function unify_compounds(base: Simple[], extra: Simple[]) -> Simple[]? {
    // A `:host`/`:host-context` pseudo can't share its compound with an
    // incompatible simple (a class, type, universal, ordinary pseudo-class, …),
    // so such a pair can't unify (dart-sass).
    if (host_unify_invalid(base, extra)) {
        return null;
    }
    let result: Simple[] = root.std.clone_vec(base);
    let pseudo_result: Simple[] = [];
    let pseudo_element_found = false;
    for (let simple in extra) {
        if (pseudo_element_found && simple is Simple_Pseudo) {
            let unified = simple_unify(simple, pseudo_result);
            if (unified == null) {
                return null;
            }
            pseudo_result = unified;
        } else {
            if (is_pseudo_element(simple)) {
                pseudo_element_found = true;
            }
            let unified = simple_unify(simple, result);
            if (unified == null) {
                return null;
            }
            result = unified;
        }
    }
    root.std.extend(result, pseudo_result);
    if (result.length() == 0) {
        return null;
    }
    result
}

/// Unify a single simple selector into a compound (`SimpleSelector.unify`).
function simple_unify(this: Simple, compound: Simple[]) -> Simple[]? {
    match (this) {
        let _u: Simple_Universal => {
            // PORT: `match compound.split_first()` → explicit checks (the
            // `None` arm is tested first; the arms are disjoint).
            let first = compound.at(0);
            if (first == null) {
                return [this];
            }
            if (first is Simple_Universal || first is Simple_Type) {
                let unified = unify_universal_and_element(this, first);
                if (unified == null) {
                    return null;
                }
                let out: Simple[] = [unified];
                root.std.extend(out, compound.slice(1, compound.length()));
                out
            } else {
                // A `null` or `*` namespace adds nothing; drop the universal.
                if (universal_ns_droppable(this)) {
                    root.std.clone_vec(compound)
                } else {
                    let out: Simple[] = [this];
                    root.std.extend(out, compound);
                    out
                }
            }
        },
        let _t: Simple_Type => {
            let first = compound.at(0);
            if (first is Simple_Universal || first is Simple_Type) {
                let unified = unify_universal_and_element(this, first);
                if (unified == null) {
                    return null;
                }
                let out: Simple[] = [unified];
                root.std.extend(out, compound.slice(1, compound.length()));
                out
            } else {
                let out: Simple[] = [this];
                root.std.extend(out, compound);
                out
            }
        },
        // A pseudo selector inserts before the first pseudo-ELEMENT (so pseudo
        // classes stay ahead of pseudo elements); two distinct pseudo elements
        // can't share a compound.
        let _p: Simple_Pseudo => {
            if (compound.length() == 1 && compound[0] is Simple_Universal) {
                return simple_unify(compound[0], [this]);
            }
            if (root.std.contains(compound, this)) {
                return root.std.clone_vec(compound);
            }
            // A selector-list pseudo (`:is`/`:where`) folding into an all-host
            // compound goes BEFORE the host (`:is(.d):host(.c)`); dart-sass
            // orders `:host`/`:host-context` after the first such wrapper.
            if (
                is_selector_list_pseudo(this)
                    && compound.length() > 0
                    && compound.every((x: Simple) -> bool {
                        is_host_pseudo(x)
                    })
            ) {
                let out: Simple[] = [this];
                root.std.extend(out, compound);
                return out;
            }
            let this_is_element = is_pseudo_element(this);
            let out: Simple[] = [];
            let added = false;
            for (let s in compound) {
                if (!added && is_pseudo_element(s)) {
                    if (this_is_element) {
                        // The same pseudo-element (e.g. legacy `:after` ≡
                        // `::after`) already present is kept as-is; two
                        // *different* pseudo-elements can't share a compound.
                        if (pseudo_elements_equal(this, s)) {
                            return root.std.clone_vec(compound);
                        }
                        return null;
                    }
                    out.push(this);
                    added = true;
                }
                out.push(s);
            }
            if (!added) {
                out.push(this);
            }
            out
        },
        // Class / id / attribute / placeholder: insert before the first pseudo.
        _ => {
            // Two distinct ids can never share a compound: an id won't unify
            // into a compound that already holds a different id (dart-sass
            // IDSelector.unify), so the whole unification fails.
            if let id: Simple_Id = this {
                if (
                    compound.some((s: Simple) -> bool {
                        match (s) {
                            let other: Simple_Id => other._0 != id._0,
                            _ => false,
                        }
                    })
                ) {
                    return null;
                }
            }
            if (compound.length() == 1 && compound[0] is Simple_Universal) {
                // `other.unify([this])` where other is the universal.
                return simple_unify(compound[0], [this]);
            }
            if (root.std.contains(compound, this)) {
                return root.std.clone_vec(compound);
            }
            // Insert `this` before the first pseudo selector.
            let out: Simple[] = [];
            let added = false;
            for (let s in compound) {
                if (!added && s is Simple_Pseudo) {
                    out.push(this);
                    added = true;
                }
                out.push(s);
            }
            if (!added) {
                out.push(this);
            }
            out
        },
    }
}

/// Whether a universal selector contributes nothing to a compound that already
/// has other simples (namespace `null` or `*`).
function universal_ns_droppable(s: Simple) -> bool {
    match (s) {
        let u: Simple_Universal => u.ns == null || u.ns == "*",
        _ => false,
    }
}

/// Unify two universal/type selectors (`unifyUniversalAndElement`). Each is a
/// `(namespace, name)` pair where a universal has `name == None`.
function unify_universal_and_element(a: Simple, b: Simple) -> Simple? {
    let parts1 = namespace_and_name(a);
    if (parts1 == null) {
        return null;
    }
    let ns1 = parts1._0;
    let name1 = parts1._1;
    let parts2 = namespace_and_name(b);
    if (parts2 == null) {
        return null;
    }
    let ns2 = parts2._0;
    let name2 = parts2._1;

    let namespace: string? = if (ns1 == ns2 || ns2 == "*") {
        ns1
    } else if (ns1 == "*") {
        ns2
    } else {
        return null;
    };

    let name: string? = if (name1 == name2 || name2 == null) {
        name1
    } else if (name1 == null || name1 == "*") {
        name2
    } else {
        return null;
    };

    // PORT: `match name { None => …, Some(n) => match namespace { … } }`.
    if (name == null) {
        Simple_Universal { ns: namespace }
    } else if (namespace != null) {
        Simple_Type { _0: `${namespace}|${name}` }
    } else {
        Simple_Type { _0: name }
    }
}

/// Decompose a universal/type selector into `(namespace, name)`.
function namespace_and_name(s: Simple) -> root.std.Tuple2<string?, string?>? {
    match (s) {
        let u: Simple_Universal => {
            let pair: root.std.Tuple2<string?, string?> = root.std.Tuple2 { _0: u.ns, _1: null };
            pair
        },
        let t: Simple_Type => {
            let split = split_type(t._0);
            let ns = split._0;
            let name = split._1;
            let pair: root.std.Tuple2<string?, string?> = root.std.Tuple2 { _0: ns, _1: name };
            pair
        },
        _ => null,
    }
}

/// Whether a pseudo selector is a pseudo-element (`::name` or a legacy
/// single-colon pseudo-element).
/// The lowercased base name of a pseudo selector (`:host(.c)` → `"host"`), or
/// `None` for a non-pseudo simple.
function pseudo_base(s: Simple) -> string? {
    let text = match (s) {
        let p: Simple_Pseudo => p._0,
        _ => {
            return null;
        },
    };
    let name = root.std.trim_start_matches(text, ":");
    // PORT: `name.split(['(', ' ']).next().unwrap_or(name)` → the text before
    // the first `(`/space.
    let cut = root.std.find_by(name, (c: string) -> bool {
        c == "(" || c == " "
    });
    let first_part = if (cut != null) {
        name.slice(0, cut)
    } else {
        name
    };
    root.std.ascii_lower(first_part)
}

/// Whether two pseudo-elements are the same selector, treating a legacy
/// single-colon form as equal to its double-colon form (`:after` ≡ `::after`).
function pseudo_elements_equal(a: Simple, b: Simple) -> bool {
    // PORT: `match (a, b)` on a tuple → nested matches.
    match (a) {
        let ta: Simple_Pseudo => match (b) {
            let tb: Simple_Pseudo => {
                let norm = (t: string) -> string {
                    `::${root.std.trim_start_matches(t, ":")}`
                };
                norm(ta._0) == norm(tb._0)
            },
            _ => false,
        },
        _ => false,
    }
}

/// Whether `s` is a `:host` / `:host-context` pseudo.
function is_host_pseudo(s: Simple) -> bool {
    let base = pseudo_base(s);
    base == "host" || base == "host-context"
}

/// Whether `s` is a selector-list pseudo (`:is`/`:where`/`:matches`/`:any`/
/// `:-*-any`) that wraps a selector list.
function is_selector_list_pseudo(s: Simple) -> bool {
    let base = pseudo_base(s);
    base == "is"
        || base == "where"
        || base == "matches"
        || base == "any"
        || base == "-moz-any"
        || base == "-webkit-any"
}

/// Whether a simple selector may share a compound with a `:host` /
/// `:host-context` pseudo: only other host pseudos, the selector-list pseudos
/// (`:is`/`:where`/`:matches`/`:any`/`:-*-any`), or pseudo-elements — never a
/// type/class/id/universal/attribute or an ordinary pseudo-class.
function host_compatible(s: Simple) -> bool {
    is_host_pseudo(s) || is_pseudo_element(s) || is_selector_list_pseudo(s)
}

/// Whether unifying `base` and `extra` would put a `:host`/`:host-context`
/// pseudo in a compound with a simple it can't combine with (checked across
/// both inputs, before a universal selector is dropped).
function host_unify_invalid(base: Simple[], extra: Simple[]) -> bool {
    let all = () -> Simple[] {
        base.concat(extra)
    };
    all().some((s: Simple) -> bool {
        is_host_pseudo(s)
    })
        && all().some((s: Simple) -> bool {
            !host_compatible(s)
        })
}

function is_pseudo_element(s: Simple) -> bool {
    let text = match (s) {
        let p: Simple_Pseudo => p._0,
        _ => {
            return false;
        },
    };
    if (text.starts_with("::")) {
        return true;
    }
    // Legacy single-colon pseudo-elements.
    let name = root.std.trim_start_matches(text, ":");
    // PORT: `name.split(['(', ' ']).next().unwrap_or(name)` → the text before
    // the first `(`/space.
    let cut = root.std.find_by(name, (c: string) -> bool {
        c == "(" || c == " "
    });
    let first_part = if (cut != null) {
        name.slice(0, cut)
    } else {
        name
    };
    let base = root.std.ascii_lower(first_part);
    base == "before" || base == "after" || base == "first-line" || base == "first-letter"
}

// ---- public helpers for the `sass:selector` builtin family -------------
//
// These are thin, additive re-exports of the engine internals above. They add
// no new behavior to the `@extend` directive path; they only expose the
// algorithms (superselector test, compound/complex unification, parent
// weaving) to `crate::builtins::selector`.
/// Whether selector list `sup` is a superselector of `sub`: every complex in
/// `sub` must be matched by some complex in `sup` (dart-sass `listIsSuperselector`).
function list_is_superselector(sup: Complex[], sub: Complex[]) -> bool {
    sub.every((c2: Complex) -> bool {
        sup.some((c1: Complex) -> bool {
            complex_is_superselector(c1, c2)
        })
    })
}

/// Unify two complex selectors into the (possibly several) complex selectors
/// they jointly match, or `None` if they can't unify (dart-sass `unifyComplex`
/// for the two-selector case).
function unify_complex(c1: Complex, c2: Complex) -> Complex[]? {
    let unified = unify_complex_list([to_dart(c1), to_dart(c2)]);
    if (unified == null) {
        return null;
    }
    let out: Complex[] = [];
    // key: rendered `Complex`
    let seen: map<string, bool> = {};
    for (let d in unified) {
        let complex = from_dart(d);
        if (root.std.set_insert(seen, complex.render())) {
            out.push(complex);
        }
    }
    if (out.length() == 0) {
        return null;
    }
    out
}

/// A faithful port of dart-sass `unifyComplex`: the contents of a selector list
/// matching only elements matched by every complex in `complexes`, or `None`
/// if no such list can be produced. All final compounds are unified into a
/// single base (with at most one shared leading and trailing combinator); the
/// remaining parent components are woven together.
function unify_complex_list(complexes: DComplex[]) -> DComplex[]? {
    if (complexes.length() == 0) {
        return null;
    }
    if (complexes.length() == 1) {
        return root.std.clone_vec(complexes);
    }

    let unified_base: Simple[]? = null;
    let leading_combinator: Combinator? = null;
    let trailing_combinator: Combinator? = null;
    for (let complex in complexes) {
        if (complex.is_useless()) {
            return null;
        }

        // A single-component complex with exactly one leading combinator
        // contributes it to the unified base; two different ones can't unify.
        if (complex.comps.length() == 1) {
            if (complex.leading.length() == 1) {
                let new_leading = complex.leading[0];
                // PORT: `match leading_combinator { None => …, Some(lc) if lc != new => … }`.
                if (leading_combinator == null) {
                    leading_combinator = new_leading;
                } else if (leading_combinator != new_leading) {
                    return null;
                }
            }
        }

        let base = root.std.last(complex.comps);
        if (base == null) {
            return null;
        }
        if (base.combinators.length() == 1) {
            let new_trailing = base.combinators[0];
            if (trailing_combinator != null && trailing_combinator != new_trailing) {
                return null;
            }
            trailing_combinator = new_trailing;
        }

        // PORT: `match &mut unified_base { None => …, Some(acc) => *acc = … }`.
        if (unified_base == null) {
            unified_base = root.std.clone_vec(base.compound.simples);
        } else {
            let acc = unify_compounds(unified_base, base.compound.simples);
            if (acc == null) {
                return null;
            }
            unified_base = acc;
        }
    }

    // Each multi-component complex minus its base, keeping its own leading run
    // and the combinator that joined the (removed) base.
    let without_bases: DComplex[] = complexes
        .filter((c: DComplex) -> bool {
            c.comps.length() > 1
        })
        .map((c: DComplex) -> DComplex {
            DComplex {
                leading: root.std.clone_vec(c.leading),
                comps: c.comps.slice(0, c.comps.length() - 1),
            }
        });

    if (unified_base == null) {
        return null;
    }
    let base = DComplex {
        leading: if (leading_combinator != null) {
            [leading_combinator]
        } else {
            []
        },
        comps: [
            TComp {
                compound: Compound { simples: unified_base },
                combinators: if (trailing_combinator != null) {
                    [trailing_combinator]
                } else {
                    []
                },
            },
        ],
    };

    // PORT: `match without_bases.split_last()` → a length check.
    let path: DComplex[] = if (without_bases.length() == 0) {
        [base]
    } else {
        let last = without_bases[without_bases.length() - 1];
        let init = without_bases.slice(0, without_bases.length() - 1);
        let path = init;
        path.push(last.concatenate(base));
        path
    };

    let woven = weave(path);
    if (woven.length() == 0) {
        null
    } else {
        woven
    }
}

/// Unify two selector lists: the cartesian product of `unify_complex` over each
/// pair of complex selectors, dropping pairs that don't unify (dart-sass
/// `SelectorList.unify`). Returns `None` if nothing unifies.
function unify_lists(list1: Complex[], list2: Complex[]) -> Complex[]? {
    let out: Complex[] = [];
    // key: rendered `Complex`
    let seen: map<string, bool> = {};
    for (let c1 in list1) {
        for (let c2 in list2) {
            let unified = unify_complex(c1, c2);
            if (unified != null) {
                for (let c in unified) {
                    if (root.std.set_insert(seen, c.render())) {
                        out.push(c);
                    }
                }
            }
        }
    }
    if (out.length() == 0) {
        return null;
    }
    out
}

/// Render a complex selector as the items of a Sass space-separated list:
/// compound strings interleaved with combinator strings (`>`/`+`/`~`), matching
/// dart-sass's `ComplexSelector.asSassList`.
function complex_to_list_parts(c: Complex) -> string[] {
    let parts: string[] = [];
    for (let comp in c.components) {
        for (let comb in comp.combinators) {
            parts.push(comb.as_str());
        }
        parts.push(comp.compound.render());
    }
    for (let comb in c.trailing) {
        parts.push(comb.as_str());
    }
    parts
}

/// Parse a single compound selector (no combinators, no commas). Returns the
/// list of simple-selector strings, or `None` if the text isn't a single valid
/// compound (dart-sass `simple-selectors` parses a `CompoundSelector`).
function parse_compound_simples(s: string) -> string[]? {
    let chars = root.std.trim(s).chars();
    let i = root.std.Cell.new(0);
    let compound = root.selector.parse.parse_compound(chars, i);
    if (compound == null) {
        return null;
    }
    root.selector.parse.skip_ws(chars, i);
    if (i.value != chars.length()) {
        return null; // trailing combinator / second compound / garbage
    }
    compound.simples.map((x: Simple) -> string {
        x.render()
    })
}

/// Extend a selector list against one or more *compound* targets (used by the
/// `selector-extend` / `selector-replace` builtins, which — unlike the
/// `@extend` directive — allow a multi-simple compound extendee, and also a
/// list of such compounds). Wherever a `target` compound is a subselector of a
/// component's compound, the `extender` selectors are woven in. With `replace`
/// true the matched original is dropped (`selector-replace`); otherwise it is
/// kept (`selector-extend`). This mirrors dart-sass `_extendComplex`/
/// `_extendCompound`: every target is applied simultaneously, and freshly
/// produced selectors are re-extended to a fixpoint so a selector matching two
/// targets collapses correctly (e.g. extending `c.d` by `c, .d` with `.e`).
function extend_compound_target(
    selectors: Complex[],
    targets: Compound[],
    extenders: Complex[],
    replace: bool,
) -> Complex[] {
    reset_extend_budget();
    // Originals are never trimmed away (dart-sass keeps the input selectors so a
    // rule still matches what it always matched). In replace mode the matched
    // originals are dropped before this point, so the set is the surviving ones.
    // key: rendered `Complex`
    let originals: map<string, bool> = {};
    if (!replace) {
        for (let complex in selectors) {
            root.std.set_insert(originals, complex.render());
        }
    }

    let result: Complex[] = [];
    let seen: map<string, bool> = {};
    // Each input complex is extended independently and its results emitted
    // consecutively (dart-sass groups a selector's extensions right after it),
    // so the per-complex fixpoint stays local to its input.
    for (let complex in selectors) {
        // Worklist so that a selector produced by one target can itself be
        // re-extended by another target (dart-sass applies all extensions
        // simultaneously). Bounded to guarantee termination.
        // PORT: `VecDeque` → array (`push` / `shift`).
        let queue: Complex[] = [];
        queue.push(complex);
        let local_seen: map<string, bool> = {};
        // dart `_extendComplex` promotes the FIRST product of extending an
        // original input complex to an original itself (extension_store.dart
        // `if (first && _originals.contains(complex)) _originals.add(output)`).
        // dart extends every target simultaneously, so that first product is the
        // FULLY-replaced selector. Our worklist replaces one target per step, so
        // the fully-replaced selector is the first one that extends to only
        // itself (`is_self_only` — no target left to replace). In replace mode
        // that terminal selector is the original that must survive `_trim`, so
        // `selector.replace((c, d c), c, e)` keeps `d e` (the bare `e` from
        // input `c` would otherwise trim it) while `replace("c.d", "c, .d", .e)`
        // still collapses to `.e` (the intermediate `.d.e` is NOT promoted).
        // Non-replace mode keeps the unchanged input as its first product
        // (already in `originals`), so the promotion is needed only for replace.
        let promote_first = replace;
        while let cur: Complex = queue.shift() {
            if (!consume_extend_work() || result.length() > 100_000) {
                break;
            }
            let cur_rendered = cur.render();
            let extended = extend_complex_compound(cur, targets, extenders, replace);
            // Whether this complex produced anything other than itself: only
            // then do we re-feed the new selectors (re-feeding an unchanged
            // selector would loop forever).
            let is_self_only = extended.length() == 1 && extended.at(0)?.render() == cur_rendered;
            for (let c in extended) {
                let rendered = c.render();
                // Promote the first FULLY-replaced product of this input to an
                // original (dart `_extendComplex` line 630). A product is fully
                // replaced once no target remains — i.e. re-extending it yields
                // only itself. Checked structurally here (not via the re-feed
                // worklist) because a terminal product can be redundant and thus
                // never re-fed: in `replace((c, d c), c, e)`, `d e` is covered
                // by the sibling `e` so it is not re-fed, yet must be promoted so
                // `_trim` keeps it.
                if (promote_first) {
                    let re = extend_complex_compound(c, targets, extenders, replace);
                    let terminal = re.length() == 1 && re.at(0)?.render() == rendered;
                    if (terminal) {
                        root.std.set_insert(originals, rendered);
                        promote_first = false;
                    }
                }
                // A selector already covered by a previously-produced one is
                // redundant; it is trimmed from the output and, crucially, must
                // not be re-fed — a self-referential extender (`.x` -> `.x .y`)
                // would otherwise grow `.x .y .y …` without bound. dart-sass
                // trims during its fixpoint. Checked before `c` joins `result`.
                let redundant = result.some((r: Complex) -> bool {
                    complex_is_superselector(r, c)
                });
                // PORT: `rendered.len()` is a UTF-8 byte length.
                if (
                    !is_self_only
                        && rendered != cur_rendered
                        && !redundant
                        && rendered.byte_length() <= EXTEND_REFEED_MAX_LEN()
                        && root.std.set_insert(local_seen, rendered)
                ) {
                    queue.push(c);
                }
                if (root.std.set_insert(seen, rendered)) {
                    result.push(c);
                }
            }
        }
    }
    // Drop selectors made redundant by a superselector elsewhere in the list
    // (dart-sass `_trim`), keeping originals. The one-off builtin store never
    // fills `_sourceSpecificity` (only `@extend`'s addExtension does), so
    // every max-specificity here is 0 and plain superselector coverage trims.
    let source_spec: map<string, int> = {};
    trim(
        result.map((c: Complex) -> root.std.Tuple2<Complex, bool> {
            let o = originals.has(c.render());
            root.std.Tuple2 { _0: c, _1: o }
        }),
        source_spec,
    )
}

/// Extend one complex selector against one or more compound targets: compute
/// each component's options (original first unless replaced), take the Cartesian
/// product, and `weave` each path — the same shape as `extend_complex`.
function extend_complex_compound(
    complex: Complex,
    targets: Compound[],
    extenders: Complex[],
    replace: bool,
) -> Complex[] {
    let d = to_dart(complex);
    // dart-sass: a complex selector with more than one leading combinator is
    // never extended (the caller keeps the original).
    if (d.leading.length() > 1) {
        return [complex];
    }

    let per_component: DComplex[][] = [];
    let any_extended = false;
    let i = 0;
    for (let comp in d.comps) {
        let extended = extend_component_compound(comp, targets, extenders, replace);
        if (extended == null) {
            per_component.push(
                [
                    DComplex {
                        leading: if (i == 0) {
                            root.std.clone_vec(d.leading)
                        } else {
                            []
                        },
                        comps: [comp],
                    },
                ],
            );
        } else {
            any_extended = true;
            if (i == 0 && d.leading.length() > 0) {
                // dart-sass: a first-component extension must have no
                // leading combinators (or the same ones); the complex's own
                // leading run is then re-attached.
                per_component.push(
                    extended
                        .filter((n: DComplex) -> bool {
                            n.leading.length() == 0 || n.leading == d.leading
                        })
                        .map((n: DComplex) -> DComplex {
                            DComplex { leading: root.std.clone_vec(d.leading), comps: n.comps }
                        }),
                );
            } else {
                per_component.push(extended);
            }
        }
        i += 1;
    }
    if (!any_extended) {
        return [complex];
    }

    // dart-sass `paths`: for each component's options, the *option* is the outer
    // loop and the accumulated paths the inner loop, so the first component's
    // choice varies fastest in the output order.
    let combos: DComplex[][] = [[]];
    for (let opts in per_component) {
        let next: DComplex[][] = [];
        for (let opt in opts) {
            for (let combo in combos) {
                let c = root.std.clone_vec(combo);
                c.push(opt);
                next.push(c);
            }
        }
        combos = next;
        if (combos.length() > 100_000) {
            break;
        }
    }

    let out: Complex[] = [];
    // key: rendered `Complex`
    let seen: map<string, bool> = {};
    for (let path in combos) {
        for (let woven in weave(path)) {
            let c = from_dart(woven);
            let r = c.render();
            if (root.std.set_insert(seen, r)) {
                out.push(c);
            }
        }
    }
    out
}

/// Options for one component against a compound target. The original component
/// is option 0 in extend mode (and in replace mode when it does not match);
/// each matching extender contributes the woven replacement.
function extend_component_compound(
    comp: TComp,
    targets: Compound[],
    extenders: Complex[],
    replace: bool,
) -> DComplex[]? {
    // First extend any selector-pseudo arguments (`:is(...)`, `:not(...)`, …)
    // in place, producing an "effective" compound that the per-compound
    // extension below then runs against.
    let effective = expand_pseudos_compound_target(comp.compound, targets, extenders, replace);
    let pseudo_changed = effective.simples != comp.compound.simples;
    let comp = TComp { compound: effective, combinators: root.std.clone_vec(comp.combinators) };
    // PORT: `let comp = &comp;` needs no counterpart.
    // The original component (as a one-component complex), keeping its
    // trailing combinator run.
    let original = DComplex { leading: [], comps: [comp] };
    // Targets whose compound is a subselector of this component's compound: each
    // matching target contributes its own woven extensions (dart-sass applies
    // every extension simultaneously).
    let matching: Compound[] = targets.filter((t: Compound) -> bool {
        compound_is_superselector(t, comp.compound, [])
    });
    if (matching.length() == 0) {
        return if (pseudo_changed) {
            [original]
        } else {
            null
        };
    }

    let options: DComplex[] = [];
    if (!replace) {
        options.push(original);
    }
    // key: rendered `DComplex`
    let seen: map<string, bool> = {};
    for (let target in matching) {
        // The simples of this compound not covered by this target.
        let remaining: Simple[] = comp.compound.simples.filter((s: Simple) -> bool {
            !root.std.contains(target.simples, s)
        });
        for (let ext in extenders) {
            let ext_d = to_dart(ext);
            if (ext_d.is_useless()) {
                continue;
            }
            // PORT: `let Some((last, parents)) = ext_d.comps.split_last() else { … }`.
            if (ext_d.comps.length() == 0) {
                // A combinator-only extender (`>`): when it replaces the whole
                // compound, the extension is the extender itself plus the
                // component's trailing run (dart-sass's single-simple shortcut;
                // with leftover simples dart-sass errors — we skip instead).
                if (remaining.length() == 0) {
                    // PORT: `ext_d.clone()` dropped — `with_additional_combinators`
                    // builds a new value rather than consuming its receiver.
                    let candidate = ext_d.with_additional_combinators(comp.combinators);
                    if (
                        !candidate.is_useless()
                            && root.std.set_insert(seen, render_dcomplex(candidate))
                    ) {
                        options.push(candidate);
                    }
                }
                continue;
            }
            let last = ext_d.comps[ext_d.comps.length() - 1];
            let parents = ext_d.comps.slice(0, ext_d.comps.length() - 1);
            let unified = unify_compounds(remaining, last.compound.simples);
            if (unified == null) {
                continue;
            }
            // The extender's parent components, then the unified trailing
            // compound keeping the extender's own trailing run; the original
            // component's trailing run is appended after that (dart-sass
            // `withAdditionalCombinators`).
            let comps = parents;
            comps.push(
                TComp {
                    compound: Compound { simples: unified },
                    combinators: root.std.clone_vec(last.combinators),
                },
            );
            let candidate = DComplex { leading: root.std.clone_vec(ext_d.leading), comps: comps }
                .with_additional_combinators(comp.combinators);
            if (candidate.is_useless()) {
                continue;
            }
            let key = render_dcomplex(candidate);
            if (root.std.set_insert(seen, key)) {
                options.push(candidate);
            }
        }
    }
    if (options.length() == 0) {
        // Replace mode with no successful unification: keep the original so the
        // selector isn't silently dropped (dart-sass leaves an unmatched
        // component intact).
        options.push(DComplex { leading: [], comps: [comp] });
    }
    options
}

/// Whether any compound in `s` contains `target` as one of its simple
/// selectors (used to satisfy `@extend` target lookup against rules whose
/// bogus combinators omitted them from the CSS).
function selector_contains_simple(s: string, target: Simple) -> bool {
    for (let part in root.selector.parse.split_top(s, ",")) {
        let complex = root.selector.parse.parse_complex(root.std.trim(part));
        if (complex != null) {
            for (let comp in complex.components) {
                if (
                    comp.compound.simples.some((x: Simple) -> bool {
                        x == target
                    })
                ) {
                    return true;
                }
            }
        }
    }
    false
}

// ---- specificity (dart SimpleSelector/ComplexSelector.specificity) -----
/// dart `SimpleSelector.specificity`: classes/attributes/placeholders and
/// plain pseudo-classes weigh 1000, IDs weigh 1000², types 1, universal 0.
/// `:where()` is 0; selector-argument pseudos (`:is`/`:not`/`:matches`/
/// `:has`…) take the max of their argument complexes.
function simple_specificity(s: Simple) -> int {
    match (s) {
        let _u: Simple_Universal => 0,
        let t: Simple_Type => {
            // `ns|*` renders as a Type carrying `*`; the universal part is 0.
            if (t._0.ends_with("*")) {
                0
            } else {
                1
            }
        },
        let _i: Simple_Id => 1_000_000,
        Simple_Class {} | Simple_Placeholder {} | Simple_Attribute {} => 1000,
        let p: Simple_Pseudo => pseudo_specificity(p._0),
        _ => root.std.unreachable(),
    }
}

function pseudo_specificity(text: string) -> int {
    let is_element = text.starts_with("::");
    let body = root.std.trim_start_matches(text, ":");
    let split = root.std.split_once(body, "(");
    // PORT: `let (name, arg) = match body.split_once('(') { … }` → a tuple.
    let name_arg: root.std.Tuple2<string, string?> = if (split != null) {
        root.std.Tuple2 {
            _0: root.std.ascii_lower(split._0),
            _1: root.std.trim_end_matches(split._1, ")"),
        }
    } else {
        root.std.Tuple2 { _0: root.std.ascii_lower(body), _1: null }
    };
    let name = name_arg._0;
    let arg = name_arg._1;
    let base = unvendor(name);
    if (base == "where") {
        return 0;
    }
    if (arg != null) {
        let selectorish = base == "is"
            || base == "matches"
            || base == "any"
            || base == "not"
            || base == "has"
            || base.ends_with("-any");
        if (selectorish) {
            let list = root.selector.parse.parse_list(arg);
            if (list != null) {
                // PORT: `.max().unwrap_or(0)` over non-negative values.
                return list
                    .map((c: Complex) -> int {
                        complex_specificity(c)
                    })
                    .reduce(
                        (a: int, b: int) -> int {
                            root.std.imax(a, b)
                        },
                        0,
                    );
            }
        }
    }
    if (is_element) {
        1
    } else {
        1000
    }
}

function compound_specificity(c: Compound) -> int {
    c.simples
        .map((s: Simple) -> int {
            simple_specificity(s)
        })
        .reduce(
            (a: int, b: int) -> int {
                a + b
            },
            0,
        )
}

/// dart `ComplexSelector.specificity`: the sum of its compounds'.
function complex_specificity(c: Complex) -> int {
    c.components
        .map((comp: ComplexComponent) -> int {
            compound_specificity(comp.compound)
        })
        .reduce(
            (a: int, b: int) -> int {
                a + b
            },
            0,
        )
}

/// All simple selectors in a complex, recursing into selector-argument
/// pseudos (dart `_simpleSelectors`).
function all_simples_of(complex: Complex, out: Simple[]) -> void {
    for (let comp in complex.components) {
        for (let s in comp.compound.simples) {
            out.push(s);
            if let p: Simple_Pseudo = s {
                let text = p._0;
                let open = text.index_of("(");
                if (open != null) {
                    if (text.ends_with(")")) {
                        let list = root.selector.parse.parse_list(text.slice(open + 1, text.length() - 1));
                        if (list != null) {
                            for (let inner in list) {
                                all_simples_of(inner, out);
                            }
                        }
                    }
                }
            }
        }
    }
}

/// Build dart's `_sourceSpecificity` map: every simple selector of every
/// extender records (first write wins) its complex's specificity.
function source_specificity_map(extensions: Extension[]) -> map<string, int> /* key: Simple */ {
    // key: `Simple::render()`
    let map: map<string, int> = {};
    for (let ext in extensions) {
        for (let complex in ext.extenders) {
            let spec = complex_specificity(complex);
            let simples: Simple[] = [];
            all_simples_of(complex, simples);
            for (let s in simples) {
                // `map.entry(s).or_insert(spec)`: the first write wins.
                let _ = map.get_or_insert(s.render(), spec);
            }
        }
    }
    map
}
