// Port of goldmark extension/typographer.go.
//
// Porting notes:
// - `TypographicPunctuation` is an int (Go: `iota`-based int constants), with
//   the constants as zero-argument functions. BAML maps only allow `string`
//   keys (E0067, also for enum keys), so Go's
//   `TypographicSubstitutions map[TypographicPunctuation]string` becomes an
//   array of `TypographicSubstitution { punctuation, value }` pairs.
// - Go's `unicode.IsPunct` / `unicode.IsSpace` map to
//   `root.util.is_unicode_punct` / `root.util.is_unicode_space`.
//   `unicode.IsDigit` / `unicode.IsLetter` have no generated table in
//   `root.util`; they are implemented here with an ASCII fast path and a
//   `baml.regex` `\p{Nd}` / `\p{L}` fallback (the regex engine's Unicode
//   version may differ slightly from Go's).
// - Go's `CloseBlock(gast.Node, parser.Context)` has the wrong arity for v2's
//   `parser.CloseBlocker` (which also takes a `text.Reader`), so goldmark never
//   calls it and the unclosed-quote counter is never reset between blocks.
//   It is ported as a plain method that does not implement
//   `root.parser.CloseBlocker`, preserving Go's observable behavior.

/// Go: `uncloseCounterKey = parser.NewContextKey()`.
function unclose_counter_key() -> root.parser.ContextKey {
    root.parser.new_context_key("extension.uncloseCounter")
}

/// Go's unexported `unclosedCounter`.
class UnclosedCounter {
    single: int,
    double: int,

    function reset(self) -> void {
        self.single = 0;
        self.double = 0;
    }
}

function get_unclosed_counter(pc: root.parser.Context) -> UnclosedCounter {
    let found = match (pc.get(unclose_counter_key())) {
        let v: UnclosedCounter => v,
        _ => null,
    };
    if (found != null) {
        return found;
    }
    let v = UnclosedCounter { single: 0, double: 0 };
    pc.set(unclose_counter_key(), v);
    v
}

/// TypographicPunctuation is a key of the punctuations that can be replaced with
/// typographic entities.
type TypographicPunctuation = int

/// LeftSingleQuote is ' .
function LEFT_SINGLE_QUOTE() -> TypographicPunctuation {
    1
}

/// RightSingleQuote is ' .
function RIGHT_SINGLE_QUOTE() -> TypographicPunctuation {
    2
}

/// LeftDoubleQuote is " .
function LEFT_DOUBLE_QUOTE() -> TypographicPunctuation {
    3
}

/// RightDoubleQuote is " .
function RIGHT_DOUBLE_QUOTE() -> TypographicPunctuation {
    4
}

/// EnDash is -- .
function EN_DASH() -> TypographicPunctuation {
    5
}

/// EmDash is --- .
function EM_DASH() -> TypographicPunctuation {
    6
}

/// Ellipsis is ... .
function ELLIPSIS() -> TypographicPunctuation {
    7
}

/// LeftAngleQuote is << .
function LEFT_ANGLE_QUOTE() -> TypographicPunctuation {
    8
}

/// RightAngleQuote is >> .
function RIGHT_ANGLE_QUOTE() -> TypographicPunctuation {
    9
}

/// Apostrophe is ' .
function APOSTROPHE() -> TypographicPunctuation {
    10
}

/// Go's unexported `typographicPunctuationMax`.
function TYPOGRAPHIC_PUNCTUATION_MAX() -> int {
    11
}

/// Go's unexported `typographerConfig`.
class TypographerConfig {
    substitutions: string[],
}

function new_default_substitutions() -> string[] {
    let replacements: string[] = [];
    let i = 0;
    while (i < TYPOGRAPHIC_PUNCTUATION_MAX()) {
        replacements.push("");
        i += 1;
    }
    replacements[LEFT_SINGLE_QUOTE()] = "&lsquo;";
    replacements[RIGHT_SINGLE_QUOTE()] = "&rsquo;";
    replacements[LEFT_DOUBLE_QUOTE()] = "&ldquo;";
    replacements[RIGHT_DOUBLE_QUOTE()] = "&rdquo;";
    replacements[EN_DASH()] = "&ndash;";
    replacements[EM_DASH()] = "&mdash;";
    replacements[ELLIPSIS()] = "&hellip;";
    replacements[LEFT_ANGLE_QUOTE()] = "&laquo;";
    replacements[RIGHT_ANGLE_QUOTE()] = "&raquo;";
    replacements[APOSTROPHE()] = "&rsquo;";
    replacements
}

/// TypographerParserOption is a functional option for the Typographer parser.
interface TypographerParserOption {
    function set_typographer_option(self, c: TypographerConfig) -> void throws never
}

/// One entry of Go's `TypographicSubstitutions map[TypographicPunctuation]string`.
class TypographicSubstitution {
    punctuation: TypographicPunctuation,
    value: string,
}

/// TypographicSubstitutions is a list of the substitutions for the Typographer extension.
type TypographicSubstitutions = TypographicSubstitution[]

function typographic_substitution(punctuation: TypographicPunctuation, value: string) -> TypographicSubstitution {
    TypographicSubstitution { punctuation: punctuation, value: value }
}

class WithTypographicSubstitutionsOption {
    replacements: string[],

    implements TypographerParserOption {
        function set_typographer_option(self, p: TypographerConfig) -> void {
            p.substitutions = self.replacements;
        }
    }
}

/// WithTypographicSubstitutions is a functional option that specify replacement text
/// for punctuations.
function with_typographic_substitutions(values: TypographicSubstitutions) -> TypographerParserOption {
    let replacements = new_default_substitutions();
    for (let v in values) {
        if (v.value.length() == 0) {
            replacements[v.punctuation] = "";
        } else {
            replacements[v.punctuation] = v.value;
        }
    }
    WithTypographicSubstitutionsOption { replacements: replacements }
}

/// Go's unexported `typographerParser` (embeds `typographerConfig`).
class TypographerParser {
    cfg: TypographerConfig,
    /// Cached `\p{L}` / `\p{Nd}` regexps for non-ASCII `unicode.IsLetter` /
    /// `unicode.IsDigit`.
    letter_re: baml.regex.Regex,
    digit_re: baml.regex.Regex,

    implements root.parser.InlineParser {
        function trigger(self) -> uint8array {
            // '\'', '"', '-', '.', ',', '<', '>', '*', '['
            root.util.bytes_of([39, 34, 45, 46, 44, 60, 62, 42, 91])
        }

        function parse(self, parent: root.ast.Node, block: root.text.Reader, pc: root.parser.Context) -> root.ast.Node? {
            let subs = self.cfg.substitutions;
            let pl = block.peek_line();
            let line = pl.line ?? root.util.new_bytes();
            let c = line[0];
            if (line.length() > 2) {
                if (c == 45) { // '-'
                    if (subs[EM_DASH()].length() != 0 && line[1] == 45 && line[2] == 45) { // ---
                        let node = root.ast.new_text(root.text.new_single_line_value_from_string(subs[EM_DASH()], block.decoder()));
                        block.advance(3);
                        return node;
                    }
                } else if (c == 46) { // '.'
                    if (subs[ELLIPSIS()].length() != 0 && line[1] == 46 && line[2] == 46) { // ...
                        let node = root.ast.new_text(root.text.new_single_line_value_from_string(subs[ELLIPSIS()], block.decoder()));
                        block.advance(3);
                        return node;
                    }
                    return null;
                }
            }
            if (line.length() > 1) {
                if (c == 60) { // '<'
                    if (subs[LEFT_ANGLE_QUOTE()].length() != 0 && line[1] == 60) { // <<
                        let node = root.ast.new_text(root.text.new_single_line_value_from_string(subs[LEFT_ANGLE_QUOTE()], block.decoder()));
                        block.advance(2);
                        return node;
                    }
                    return null;
                } else if (c == 62) { // '>'
                    if (subs[RIGHT_ANGLE_QUOTE()].length() != 0 && line[1] == 62) { // >>
                        let node = root.ast.new_text(root.text.new_single_line_value_from_string(subs[RIGHT_ANGLE_QUOTE()], block.decoder()));
                        block.advance(2);
                        return node;
                    }
                    return null;
                } else if (c == 45) { // '-'
                    if (subs[EN_DASH()].length() != 0 && line[1] == 45) { // --
                        let node = root.ast.new_text(root.text.new_single_line_value_from_string(subs[EN_DASH()], block.decoder()));
                        block.advance(2);
                        return node;
                    }
                }
            }
            if (c == 39 || c == 34) { // '\'' or '"'
                let before = block.preceding_character();
                let after = 32; // ' '
                if (line.length() > 1) {
                    after = root.util.to_rune(line, 1);
                }
                let can_open = root.parser.is_left_flanking_delimiter_run(before, after);
                let can_close = root.parser.is_right_flanking_delimiter_run(before, after);
                if (!can_open && !can_close) {
                    return null;
                }
                let counter = get_unclosed_counter(pc);
                if (c == 39) { // '\''
                    if (subs[APOSTROPHE()].length() != 0) {
                        // Handle decade abbrevations such as '90s
                        if (can_open && !can_close && line.length() > 3 && root.util.is_numeric(line[1]) && root.util.is_numeric(line[2]) && line[3] == 115) { // 's'
                            let after2 = 32; // ' '
                            if (line.length() > 4) {
                                after2 = root.util.to_rune(line, 4);
                            }
                            if (line.length() == 3 || root.util.is_space_rune(after2) || root.util.is_punct_rune(after2)) {
                                let node = root.ast.new_text(root.text.new_single_line_value_from_string(subs[APOSTROPHE()], block.decoder()));
                                block.advance(1);
                                return node;
                            }
                        }
                        // special cases: 'twas, 'em, 'net
                        if (line.length() > 1 && (root.util.is_unicode_punct(before) || root.util.is_unicode_space(before)) && (line[1] == 116 || line[1] == 101 || line[1] == 110 || line[1] == 108)) { // 't' 'e' 'n' 'l'
                            let node = root.ast.new_text(root.text.new_single_line_value_from_string(subs[APOSTROPHE()], block.decoder()));
                            block.advance(1);
                            return node;
                        }
                        // Convert normal apostrophes. This is probably more flexible than necessary but
                        // converts any apostrophe in between two alphanumerics.
                        if (line.length() > 1 && (self.is_digit(before) || self.is_letter(before)) && self.is_letter(root.util.to_rune(line, 1))) {
                            let node = root.ast.new_text(root.text.new_single_line_value_from_string(subs[APOSTROPHE()], block.decoder()));
                            block.advance(1);
                            return node;
                        }
                    }
                    if (subs[LEFT_SINGLE_QUOTE()].length() != 0 && can_open && !can_close) {
                        let nt = LEFT_SINGLE_QUOTE();
                        // special cases: Alice's, I'm, Don't, You'd
                        if (line.length() > 1 && (line[1] == 115 || line[1] == 109 || line[1] == 116 || line[1] == 100) && (line.length() < 3 || root.util.is_punct(line[2]) || root.util.is_space(line[2]))) { // 's' 'm' 't' 'd'
                            nt = RIGHT_SINGLE_QUOTE();
                        }
                        // special cases: I've, I'll, You're
                        if (line.length() > 2 && ((line[1] == 118 && line[2] == 101) || (line[1] == 108 && line[2] == 108) || (line[1] == 114 && line[2] == 101)) && (line.length() < 4 || root.util.is_punct(line[3]) || root.util.is_space(line[3]))) { // "ve" "ll" "re"
                            nt = RIGHT_SINGLE_QUOTE();
                        }
                        if (nt == LEFT_SINGLE_QUOTE()) {
                            counter.single += 1;
                        }

                        let node = root.ast.new_text(root.text.new_single_line_value_from_string(subs[nt], block.decoder()));
                        block.advance(1);
                        return node;
                    }
                    if (subs[RIGHT_SINGLE_QUOTE()].length() != 0) {
                        // plural possesive and abbreviations: Smiths', doin'
                        // Go: `A && B || C && (D && E)` (&& binds tighter than ||).
                        if ((line.length() > 1 && root.util.is_unicode_space(root.util.to_rune(line, 0))) || (root.util.is_unicode_punct(root.util.to_rune(line, 0)) && (line.length() > 2 && !self.is_digit(root.util.to_rune(line, 1))))) {
                            let node = root.ast.new_text(root.text.new_single_line_value_from_string(subs[RIGHT_SINGLE_QUOTE()], block.decoder()));
                            block.advance(1);
                            return node;
                        }
                    }
                    if (subs[RIGHT_SINGLE_QUOTE()].length() != 0 && counter.single > 0) {
                        let is_close = can_close && !can_open;
                        let maybe_close = can_close && can_open && line.length() > 1 && root.util.is_unicode_punct(root.util.to_rune(line, 1)) && (line.length() == 2 || ((line.length() > 2 && root.util.is_punct(line[2])) || root.util.is_space(line[2])));
                        if (is_close || maybe_close) {
                            let node = root.ast.new_text(root.text.new_single_line_value_from_string(subs[RIGHT_SINGLE_QUOTE()], block.decoder()));
                            block.advance(1);
                            counter.single -= 1;
                            return node;
                        }
                    }
                }
                if (c == 34) { // '"'
                    if (subs[LEFT_DOUBLE_QUOTE()].length() != 0 && can_open && !can_close) {
                        let node = root.ast.new_text(root.text.new_single_line_value_from_string(subs[LEFT_DOUBLE_QUOTE()], block.decoder()));
                        block.advance(1);
                        counter.double += 1;
                        return node;
                    }
                    if (subs[RIGHT_DOUBLE_QUOTE()].length() != 0 && counter.double > 0) {
                        let is_close = can_close && !can_open;
                        let maybe_close = can_close && can_open && line.length() > 1 && root.util.is_unicode_punct(root.util.to_rune(line, 1)) && (line.length() == 2 || ((line.length() > 2 && root.util.is_punct(line[2])) || root.util.is_space(line[2])));
                        if (is_close || maybe_close) {
                            // special case: "Monitor 21""
                            if (line.length() > 1 && line[1] == 34 && self.is_digit(before)) {
                                return null;
                            }
                            let node = root.ast.new_text(root.text.new_single_line_value_from_string(subs[RIGHT_DOUBLE_QUOTE()], block.decoder()));
                            block.advance(1);
                            counter.double -= 1;
                            return node;
                        }
                    }
                }
            }
            null
        }
    }

    /// Go: `CloseBlock(_ gast.Node, pc parser.Context)`. Its signature does
    /// not match `parser.CloseBlocker`, so goldmark never calls it; this port
    /// keeps it as a plain method for the same behavior.
    function close_block(self, parent: root.ast.Node, pc: root.parser.Context) -> void {
        get_unclosed_counter(pc).reset();
    }

    /// Go: `unicode.IsDigit(r)`.
    function is_digit(self, r: int) -> bool {
        if (r < 0x80) {
            return r >= 48 && r <= 57;
        }
        typographer_rune_matches(self.digit_re, r)
    }

    /// Go: `unicode.IsLetter(r)`.
    function is_letter(self, r: int) -> bool {
        if (r < 0x80) {
            return (r >= 97 && r <= 122) || (r >= 65 && r <= 90);
        }
        typographer_rune_matches(self.letter_re, r)
    }
}

/// Whether the single code point `r` matches `re` (an anchored class regexp).
function typographer_rune_matches(re: baml.regex.Regex, r: int) -> bool {
    let s = baml.String.from_code_points([r]) catch_all (e) {
        _ => ""
    };
    if (s == "") {
        return false;
    }
    re.has_match(s)
}

function typographer_must_regexp(pattern: string) -> baml.regex.Regex {
    baml.regex.new(pattern) catch_all (e) {
        _ => {
            baml.sys.panic("typographer: invalid regexp: " + pattern);
            baml.regex.new("x") catch_all (e2) { _ => baml.sys.panic("unreachable") }
        }
    }
}

/// Go: unexported `newTypographerParser`.
function new_typographer_inline_parser(opts: TypographerParserOption[] = []) -> root.parser.InlineParser {
    let cfg = TypographerConfig { substitutions: new_default_substitutions() };
    for (let o in opts) {
        o.set_typographer_option(cfg);
    }
    TypographerParser {
        cfg: cfg,
        letter_re: typographer_must_regexp("^\\p{L}$"),
        digit_re: typographer_must_regexp("^\\p{Nd}$"),
    }
}

/// Go's unexported `typographerParserExtension`.
class TypographerParserExtension {
    options: TypographerParserOption[],

    implements root.parser.Extension {
        function parser_options(self, cfg: root.parser.Config) -> root.parser.Option[] {
            let result: root.parser.Option[] = [
                root.parser.with_inline_parsers([
                    root.util.prioritized(new_typographer_inline_parser(opts = self.options), 9999),
                ]),
            ];
            result
        }
    }
}

/// NewTypographerParser returns a new parser.Extension that replaces punctuations with typographic entities.
function new_typographer_parser(opts: TypographerParserOption[] = []) -> root.parser.Extension {
    TypographerParserExtension { options: opts }
}

/// TypographerParser is a default [parser.Extension] for replacing punctuations with typographic entities.
/// (Go: package-level `var TypographerParser = NewTypographerParser()`.)
function typographer_parser() -> root.parser.Extension {
    new_typographer_parser()
}
