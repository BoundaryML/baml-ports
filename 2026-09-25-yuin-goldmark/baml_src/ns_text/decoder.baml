// Port of goldmark text/decoder.go.

/// A Decoder decodes a byte slice, e.g. resolving backslash escapes and
/// character references, and returns or writes out the decoded bytes.
///
/// Note that this interface is not intended to 'normalize' a byte slice, but to decode it.
/// For example, CommonMark requires that code spans normalize leading spaces, trailing spaces
/// and newlines, but this interface does not do that.
interface Decoder {
    /// Decode decodes the given byte slice and returns the decoded bytes.
    function decode(self, b: uint8array) -> uint8array throws never

    /// DecodeTo decodes the given byte slice and writes the decoded bytes to w.
    function decode_to(self, w: root.util.BufWriter, b: uint8array) -> int throws never
}

/// Go's `decoderConfig`, configured through DecoderOption functions.
class DecoderConfig {
    escaped_space: bool,
}

/// DecoderOption is a function that configures a decoder.
type DecoderOption = (cfg: DecoderConfig) -> void throws never

/// WithEscapedSpace configures the decoder to treat escaped spaces as an empty character.
function with_escaped_space() -> DecoderOption {
    (cfg: DecoderConfig) -> void {
        cfg.escaped_space = true;
    }
}

/// Collects decoded output either into a CopyOnWriteBuffer (Decode) or a
/// writer (DecodeTo). Go duplicates the decoding loop for both; BAML closures
/// let the loop be shared, which is the only structural change here.
class DecodeSink {
    cob: root.util.CopyOnWriteBuffer?,
    w: root.util.BufWriter?,
    written: int,

    function write(self, b: uint8array) -> void {
        // BAML does not narrow `self.field != null`; bind locals first.
        let cob = self.cob;
        let w = self.w;
        if (cob != null) {
            cob.write(b);
        } else if (w != null) {
            self.written += w.write(b);
        }
    }
}

/// DefaultDecoder is the default implementation of the Decoder interface.
///
/// CommonMark defines texts except some inline elements (e.g., code span, auto link, etc)
/// can contain character references and backslash escapes. This decoder decodes them.
///
/// - decodes entity references (e.g., `&amp; -> &`)
/// - decodes numeric character references (e.g., `&#x26; -> &`)
/// - decodes `\` escaped punctuations (e.g., `\* -> *`)
///   - If WithEscapedSpace is set, it will also decode `\ ` to an empty character.
class DefaultDecoder {
    cfg: DecoderConfig,

    /// Shared body of Decode and DecodeTo. Returns the index `n` of the first
    /// byte not yet written to the sink.
    function run(self, b: uint8array, sink: DecodeSink) -> int {
        let limit = b.length();
        let amp_pos = root.util.index_byte(b, 38);
        let bs_pos = root.util.index_byte(b, 92);
        let n = 0;
        // Instead of scanning every byte, jump directly between the cached
        // positions of the next '&' and '\\', re-deriving only the cursor
        // that was actually consumed (or overrun) by the last match.
        while (amp_pos != -1 || bs_pos != -1) {
            let i = if (bs_pos != -1 && (amp_pos == -1 || bs_pos < amp_pos)) { bs_pos } else { amp_pos };
            let next = i + 1;
            if (b[i] == 92) {
                if (i < limit - 1 && (root.util.is_punct(b[next]) || (self.cfg.escaped_space && b[next] == 32))) {
                    sink.write(b.slice(n, i));
                    if (b[next] != 32) {
                        sink.write(b.slice(next, next + 1));
                    }
                    n = next + 1;
                    next = n;
                }
            } else {
                // b[i] == '&'
                let pos = i;
                let handled = false;
                if (next < limit) {
                    if (b[next] == 35) {
                        let nnext = next + 1;
                        if (nnext < limit) {
                            let nc = b[nnext];
                            // code point like #x22;
                            if ((nnext < limit && nc == 120) || nc == 88) {
                                let start = nnext + 1;
                                let rw = root.util.read_while(b, start, limit, root.util.is_hex_decimal);
                                let j = rw.pos;
                                if (rw.ok && j < limit && b[j] == 59 && j - start < 7) {
                                    let v = parse_uint(b.slice(start, j), 16);
                                    sink.write(b.slice(n, pos));
                                    n = j + 1;
                                    sink.write(root.util.utf8_encode_rune(root.util.to_valid_rune(v)));
                                    next = n;
                                    handled = true;
                                }
                                // code point like #1234;
                            } else if (nc >= 48 && nc <= 57) {
                                let start = nnext;
                                let rw = root.util.read_while(b, start, limit, root.util.is_numeric);
                                let j = rw.pos;
                                if (rw.ok && j < limit && j - start < 8 && b[j] == 59) {
                                    let v = parse_uint(b.slice(start, j), 10);
                                    sink.write(b.slice(n, pos));
                                    n = j + 1;
                                    sink.write(root.util.utf8_encode_rune(root.util.to_valid_rune(v)));
                                    next = n;
                                    handled = true;
                                }
                            }
                        }
                    } else {
                        let start = next;
                        let rw = root.util.read_while(b, start, limit, root.util.is_alpha_numeric);
                        let j = rw.pos;
                        if (rw.ok && j < limit && b[j] == 59) {
                            let name = b.slice(start, j).to_string();
                            let entity = root.util.lookup_html5_entity_by_name(name);
                            if (entity != null) {
                                sink.write(b.slice(n, pos));
                                n = j + 1;
                                sink.write(entity.characters);
                                next = n;
                                handled = true;
                            }
                        }
                    }
                }
                if (!handled) {
                    next = pos + 1;
                }
            }
            if (amp_pos != -1 && amp_pos < next) {
                amp_pos = root.util.index_byte_from(b, next, 38);
            }
            if (bs_pos != -1 && bs_pos < next) {
                bs_pos = root.util.index_byte_from(b, next, 92);
            }
        }
        n
    }

    implements Decoder {
        /// Decode implements the [Decoder] interface.
        function decode(self, b: uint8array) -> uint8array throws never {
            if (!b.includes(38) && !b.includes(92)) {
                return b;
            }
            let cob = root.util.new_copy_on_write_buffer(b);
            let sink = DecodeSink { cob: cob, w: null, written: 0 };
            let n = self.run(b, sink);
            if (cob.is_copied()) {
                cob.write(b.slice(n, b.length()));
            }
            cob.bytes()
        }

        /// DecodeTo implements the [Decoder] interface.
        function decode_to(self, w: root.util.BufWriter, b: uint8array) -> int throws never {
            if (!b.includes(38) && !b.includes(92)) {
                return w.write(b);
            }
            let sink = DecodeSink { cob: null, w: w, written: 0 };
            let n = self.run(b, sink);
            sink.written + w.write(b.slice(n, b.length()))
        }
    }
}

/// Go: `strconv.ParseUint(s, base, 32)`, ignoring errors (the caller has
/// already validated the digits and their count).
function parse_uint(b: uint8array, base: int) -> int {
    let v = 0;
    let n = b.length();
    let i = 0;
    while (i < n) {
        let c = b[i];
        let d = if (c >= 48 && c <= 57) {
            c - 48
        } else if (c >= 97 && c <= 102) {
            c - 87
        } else {
            c - 55
        };
        v = v * base + d;
        i += 1;
    }
    if (v > 0xFFFFFFFF) {
        // ParseUint with bitSize 32 returns the max value on overflow.
        return 0xFFFFFFFF;
    }
    v
}

/// NewDecoder creates a new Decoder with the given options.
function new_decoder(opts: DecoderOption[]) -> DefaultDecoder {
    let cfg = DecoderConfig { escaped_space: false };
    for (let opt in opts) {
        opt(cfg);
    }
    DefaultDecoder { cfg: cfg }
}

/// Go's unexported `identityDecoder`.
class IdentityDecoderImpl {
    implements Decoder {
        function decode(self, b: uint8array) -> uint8array throws never {
            b
        }

        function decode_to(self, w: root.util.BufWriter, b: uint8array) -> int throws never {
            w.write(b)
        }
    }
}

/// IdentityDecoder is a decoder that does not perform any decoding and returns the bytes as is.
/// (Go: package-level var `IdentityDecoder`; BAML has no package-level values.)
function identity_decoder() -> Decoder {
    IdentityDecoderImpl {}
}
