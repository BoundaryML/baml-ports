// Port of goldmark extension/linkify.go.
//
// Porting notes:
// - Go `regexp.Regexp` (RE2, byte-oriented, ASCII `\d`/`\w`/`\s`) becomes
//   `baml.regex.Regex` (Unicode-aware `\d`/`\w`/`\s`, code-point offsets).
//   Match offsets are converted back to byte offsets by
//   `root.text.regexp_find_submatch_index`. The built-in patterns below only
//   use explicit ASCII classes (Go's `\d` is spelled `[0-9]`) so they match the
//   same strings as in Go. User-supplied patterns (`with_url_regexp` & co.)
//   get the BAML engine's semantics.
// - Regexps are matched against `line.to_string()`; a line with invalid UTF-8
//   is decoded lossily (U+FFFD), which may shift offsets. Go matches raw bytes.
// - Go's package-level regexps / byte tables are zero-argument functions.
// - Go's `CloseBlock(ast.Node, parser.Context)` has the wrong arity for v2's
//   `parser.CloseBlocker` (which also takes a `text.Reader`), so goldmark never
//   calls it. It is ported as a plain method that does not implement
//   `root.parser.CloseBlocker`, preserving that behavior.

/// Go: `wwwURLRegxp`.
function www_url_regexp() -> baml.regex.Regex {
    // Go: `^www\.[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-z]+(?:[/#?][-a-zA-Z0-9@:%_\+.~#!?&/=\(\);,'">\^{}\[\]` + "`" + `]*)?`
    baml.regex.new("^www\\.[-a-zA-Z0-9@:%._\\+~#=]{1,256}\\.[a-z]+(?:[/#?][-a-zA-Z0-9@:%_\\+.~#!?&/=\\(\\);,'\">\\^{}\\[\\]`]*)?") catch_all (e) {
        _ => {
            baml.sys.panic("linkify: invalid www regexp");
            baml.regex.new("x") catch_all (e2) { _ => baml.sys.panic("unreachable") }
        }
    }
}

/// Go: `urlRegexp`.
function url_regexp() -> baml.regex.Regex {
    // Go: `^(?:http|https|ftp)://[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-z]+(?::\d+)?(?:[/#?][-a-zA-Z0-9@:%_+.~#$!?&/=\(\);,'">\^{}\[\]` + "`" + `]*)?`
    // Go's `\d` is ASCII-only; the BAML engine's `\d` is Unicode, so `[0-9]`.
    baml.regex.new("^(?:http|https|ftp)://[-a-zA-Z0-9@:%._\\+~#=]{1,256}\\.[a-z]+(?::[0-9]+)?(?:[/#?][-a-zA-Z0-9@:%_+.~#$!?&/=\\(\\);,'\">\\^{}\\[\\]`]*)?") catch_all (e) {
        _ => {
            baml.sys.panic("linkify: invalid url regexp");
            baml.regex.new("x") catch_all (e2) { _ => baml.sys.panic("unreachable") }
        }
    }
}

/// Go's unexported `linkifyConfig`.
class LinkifyConfig {
    /// Go: `AllowedProtocols [][]byte`; null mirrors a nil slice.
    allowed_protocols: uint8array[]?,
    url_regexp: baml.regex.Regex,
    www_regexp: baml.regex.Regex,
    email_regexp: baml.regex.Regex?,
}

/// LinkifyParserOption is a functional option for the Linkify parser.
interface LinkifyParserOption {
    function set_linkify_option(self, c: LinkifyConfig) -> void throws never
}

class WithAllowedProtocolsOption {
    value: uint8array[],

    implements LinkifyParserOption {
        function set_linkify_option(self, p: LinkifyConfig) -> void {
            for (let v in self.value) {
                let list = p.allowed_protocols ?? [];
                list.push(v);
                p.allowed_protocols = list;
            }
        }
    }
}

/// WithAllowedProtocols is a functional option that specify allowed
/// protocols in autolinks. Each protocol must end with ':' like
/// 'http:' .
function with_allowed_protocols(value: string[]) -> LinkifyParserOption {
    let bs: uint8array[] = [];
    for (let v in value) {
        bs.push(v.to_utf8());
    }
    WithAllowedProtocolsOption { value: bs }
}

/// WithAllowedProtocols for `[][]byte` values (Go's generic `T []byte | string`).
function with_allowed_protocols_bytes(value: uint8array[]) -> LinkifyParserOption {
    WithAllowedProtocolsOption { value: value }
}

class WithURLRegexpOption {
    value: baml.regex.Regex,

    implements LinkifyParserOption {
        function set_linkify_option(self, p: LinkifyConfig) -> void {
            p.url_regexp = self.value;
        }
    }
}

/// WithURLRegexp is a functional option that specify
/// a pattern of the URL including a protocol.
function with_url_regexp(value: baml.regex.Regex) -> LinkifyParserOption {
    WithURLRegexpOption { value: value }
}

class WithWWWRegexpOption {
    value: baml.regex.Regex,

    implements LinkifyParserOption {
        function set_linkify_option(self, p: LinkifyConfig) -> void {
            p.www_regexp = self.value;
        }
    }
}

/// WithWWWRegexp is a functional option that specify
/// a pattern of the URL without a protocol.
/// This pattern must start with 'www.' .
function with_www_regexp(value: baml.regex.Regex) -> LinkifyParserOption {
    WithWWWRegexpOption { value: value }
}

class WithEmailRegexpOption {
    value: baml.regex.Regex,

    implements LinkifyParserOption {
        function set_linkify_option(self, p: LinkifyConfig) -> void {
            p.email_regexp = self.value;
        }
    }
}

/// WithEmailRegexp is a functional option that specify
/// a pattern of the email address.
function with_email_regexp(value: baml.regex.Regex) -> LinkifyParserOption {
    WithEmailRegexpOption { value: value }
}

/// Go's unexported `linkifyParser` (embeds `linkifyConfig`).
class LinkifyParser {
    cfg: LinkifyConfig,
    /// Go: package-level `emailDomainRegexp`, compiled once per parser here.
    email_domain_re: baml.regex.Regex,

    implements root.parser.InlineParser {
        function trigger(self) -> uint8array {
            // ' ' indicates any white spaces and a line head
            root.util.bytes_of([32, 42, 95, 126, 40]) // ' ', '*', '_', '~', '('
        }

        function parse(self, parent: root.ast.Node, block: root.text.Reader, pc: root.parser.Context) -> root.ast.Node? {
            if (pc.is_in_link_label()) {
                return null;
            }
            let pl = block.peek_line();
            let line = pl.line ?? root.util.new_bytes();
            let segment = pl.segment;
            let consumes = 0;
            let start = segment.start;
            let c = line[0];
            // advance if current position is not a line head.
            if (c == 32 || c == 42 || c == 95 || c == 126 || c == 40) {
                consumes += 1;
                start += 1;
                line = line.slice(1, line.length());
            }

            let m: int[]? = null;
            let is_email = false;
            let is_www = false;
            let allowed = self.cfg.allowed_protocols;
            if (allowed == null) {
                if (root.util.has_prefix_at(line, 0, "http:") || root.util.has_prefix_at(line, 0, "https:") || root.util.has_prefix_at(line, 0, "ftp:")) {
                    m = root.text.regexp_find_submatch_index(self.cfg.url_regexp, line);
                }
            } else {
                for (let prefix in allowed) {
                    if (root.util.has_prefix(line, prefix)) {
                        m = root.text.regexp_find_submatch_index(self.cfg.url_regexp, line);
                        break;
                    }
                }
            }
            if (m == null && root.util.has_prefix_at(line, 0, "www.")) {
                m = root.text.regexp_find_submatch_index(self.cfg.www_regexp, line);
                is_www = true;
            }
            let mm = m;
            if (mm != null) {
                if (mm[0] != 0) {
                    m = null;
                }
            }
            let stop_at = 0; // Go: m[1]
            let found = m;
            if (found == null) {
                if (line.length() > 0 && root.util.is_punct(line[0])) {
                    return null;
                }
                is_email = true;
                let stop = -1;
                let email_re = self.cfg.email_regexp;
                if (email_re == null) {
                    stop = linkify_find_email_index(line, self.email_domain_re);
                } else {
                    let em = root.text.regexp_find_submatch_index(email_re, line);
                    if (em != null) {
                        if (em[0] == 0) {
                            stop = em[1];
                        }
                    }
                }
                if (stop < 0) {
                    return null;
                }
                let at = root.util.index_byte(line, 64); // '@'
                // Go: `m = []int{0, stop, at, stop - 1}`; `line[at:stop-1]`
                // panics in Go when there is no '@' (only possible with a
                // custom email regexp); return no match instead.
                if (at < 0 || at > stop - 1) {
                    return null;
                }
                if (root.util.index_byte_in_range(line, at, stop - 1, 46) < 0) { // '.'
                    return null;
                }
                stop_at = stop;
                let last_char = line[stop_at - 1];
                if (last_char == 46) { // '.'
                    stop_at -= 1;
                }
                if (stop_at < line.length()) {
                    let next_char = line[stop_at];
                    if (next_char == 45 || next_char == 95) { // '-', '_'
                        return null;
                    }
                }
            } else {
                stop_at = found[1];
            }
            if (consumes != 0) {
                let s = segment.with_stop(segment.start + 1);
                parent.append_child(root.ast.new_text(root.text.new_single_line_value_from_segment(s, block.decoder())));
            }
            let opening = 0;
            let closing = 0;
            let k = 0;
            while (k < stop_at) {
                if (line[k] == 40) { // '('
                    opening += 1;
                } else if (line[k] == 41) { // ')'
                    closing += 1;
                }
                k += 1;
            }
            let i = stop_at;
            // Go: `for i > 1 { switch ... goto endfor }`.
            while (i > 1) {
                let ch = line[i - 1];
                // '?', '!', '.', ',', ':', '*', '_', '~'
                if (ch == 63 || ch == 33 || ch == 46 || ch == 44 || ch == 58 || ch == 42 || ch == 95 || ch == 126) {
                    i -= 1;
                } else if (ch == 41) { // ')'
                    if (closing <= opening) {
                        break;
                    }
                    closing -= 1;
                    i -= 1;
                } else if (ch == 59) { // ';'
                    let j = i - 2;
                    while (j > 0) {
                        if (root.util.is_alpha_numeric(line[j])) {
                            j -= 1;
                            continue;
                        }
                        break;
                    }
                    if (j == i - 2 || line[j] != 38) { // '&'
                        break;
                    }
                    i = j;
                } else {
                    break;
                }
            }
            consumes += i;
            block.advance(consumes);
            let raw_val = root.text.new_single_line_value_from_index(root.text.new_index(start, start + i), root.text.identity_decoder());
            let dest = if (is_email) {
                root.text.new_single_line_value_from_string("mailto:" + line.slice(0, i).to_string(), root.text.identity_decoder())
            } else if (is_www) {
                root.text.new_single_line_value_from_string("http://" + line.slice(0, i).to_string(), root.text.identity_decoder())
            } else {
                raw_val
            };
            root.ast.new_auto_link(dest, raw_val, opts = [root.ast.with_auto_link_text(raw_val)])
        }
    }

    /// Go: `CloseBlock(_ ast.Node, _ parser.Context)` — nothing to do. (Its
    /// signature does not match `parser.CloseBlocker`, so it is never called.)
    function close_block(self, parent: root.ast.Node, pc: root.parser.Context) -> void {
        // nothing to do
    }
}

/// Go: unexported `newLinkifyParser`.
function new_linkify_inline_parser(opts: LinkifyParserOption[] = []) -> root.parser.InlineParser {
    let cfg = LinkifyConfig {
        allowed_protocols: null,
        url_regexp: url_regexp(),
        www_regexp: www_url_regexp(),
        email_regexp: null,
    };
    for (let o in opts) {
        o.set_linkify_option(cfg);
    }
    LinkifyParser { cfg: cfg, email_domain_re: email_domain_regexp() }
}

/// Go's unexported `linkifyParserExtension`.
class LinkifyParserExtension {
    options: LinkifyParserOption[],

    implements root.parser.Extension {
        function parser_options(self, cfg: root.parser.Config) -> root.parser.Option[] {
            let result: root.parser.Option[] = [
                root.parser.with_inline_parsers([
                    root.util.prioritized(new_linkify_inline_parser(opts = self.options), 999),
                ]),
            ];
            result
        }
    }
}

/// NewLinkifyParser returns a new parser.Extension that parses text that seems like a URL.
function new_linkify_parser(opts: LinkifyParserOption[] = []) -> root.parser.Extension {
    LinkifyParserExtension { options: opts }
}

/// LinkifyParser is a default [parser.Extension] that parses text that seems like a URL.
/// (Go: package-level `var LinkifyParser = NewLinkifyParser()`.)
function linkify_parser() -> root.parser.Extension {
    new_linkify_parser()
}

/// Go: `emailDomainRegexp`.
function email_domain_regexp() -> baml.regex.Regex {
    // Go: `^[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*`
    baml.regex.new("^[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*") catch_all (e) {
        _ => {
            baml.sys.panic("linkify: invalid email domain regexp");
            baml.regex.new("x") catch_all (e2) { _ => baml.sys.panic("unreachable") }
        }
    }
}

/// findEmailIndex returns a stop index value if the given bytes seem an email address.
/// (Go's `findEmailIndex` in linkify.go; `emailTable` is identical to the one
/// ported in `root.parser.email_table`.)
function linkify_find_email_index(b: uint8array, email_domain_re: baml.regex.Regex) -> int {
    // TODO: eliminate regexps
    let i = 0;
    while (i < b.length()) {
        let c = b[i];
        if ((root.parser.email_table(c) & 1) != 1) {
            break;
        }
        i += 1;
    }
    if (i == 0) {
        return -1;
    }
    if (i >= b.length() || b[i] != 64) { // '@'
        return -1;
    }
    i += 1;
    if (i >= b.length()) {
        return -1;
    }
    let rest = b.slice(i, b.length());
    let m = root.text.regexp_find_submatch_index(email_domain_re, rest);
    if (m == null) {
        return -1;
    }
    i + m[1]
}
