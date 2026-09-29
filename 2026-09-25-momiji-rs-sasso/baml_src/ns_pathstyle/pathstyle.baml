// Ported from sasso `src/pathstyle.rs` (namespace `root.pathstyle`).
//
// Path spelling rules as a value, so the Windows ones can be tested anywhere.
//
// `std::path` splits and compares by the HOST's rules, which left every
// Windows-only path rule unreachable from a test that does not run on Windows:
// on macOS `c:\a\b` is a single `Component`, so the Windows branch of a
// relativisation could not be exercised at all. #146 lived in exactly that
// blind spot — two relativisations compared a lowercased canonical key against
// a mixed-case `current_dir()`, matched nothing past the drive letter, and
// quietly printed absolute paths in every diagnostic instead.
//
// dart's `path` package models this as `Style.posix` / `Style.windows` on an
// explicit `Context`, which is how its own suite checks Windows behaviour on a
// POSIX host. This is the same idea, narrowed to the one operation sasso
// needs: the relative path from one absolute path to another.

/// Which platform's rules a path is read and written by.
enum Style {
    /// `/` separates, and two names differing in case are two files.
    Posix,
    /// `\` separates for output and `/` is read as one too; two names differing
    /// in ASCII case are ONE file, and a drive letter belongs to the root
    /// rather than being a segment.
    Windows,
}

/// The rules of the platform this build runs on.
function HOST() -> Style {
    // PORT: `if cfg!(windows) { Style::Windows } else { Style::Posix }` — the
    // macOS/Linux host branch.
    Style.Posix
}

interface StyleMethods {
    /// The separator to spell a path WITH. Windows reads `/` as a separator too
    /// (see [`Style::is_sep`]), but dart writes `\` there, so a diagnostic path
    /// does.
    function sep(self) -> string throws unknown;

    /// Whether `c` separates two segments.
    function is_sep(self, c: string) -> bool throws unknown;

    /// The byte length of `p`'s absolute root — `0` when `p` is relative.
    ///
    /// Windows has four spellings: a drive (`C:\`), a UNC share
    /// (`\\server\share\`), the current drive's root (`\`), and a verbatim or
    /// device wrapper around a drive (`\\?\C:\`, `\\.\C:\`) — which
    /// `std::fs::canonicalize` produces and `current_dir` never does.
    function root_len(self, p: string) -> int throws unknown;

    /// `p`'s absolute root, or `None` when `p` is relative.
    function root(self, p: string) -> string? throws unknown;

    /// `p`'s non-empty segments, with its root and any repeated separators
    /// dropped.
    function segments(self, p: string) -> string[] throws unknown;

    /// Whether two absolute roots name the same one. On Windows a drive letter
    /// is case-insensitive, `/` and `\` are the same separator, and a verbatim
    /// or device marker is not part of the identity: `std::fs::canonicalize`
    /// emits one where `current_dir` does not, so the two sides of a comparison
    /// routinely disagree about it.
    ///
    /// A trailing separator is not part of the identity either: a share is
    /// spelled `\\server\share` when it is the whole path and
    /// `\\server\share\` when something follows, so the two sides of a
    /// comparison disagree about it whenever the working directory IS the
    /// share.
    ///
    /// The verbatim UNC form (`\\?\UNC\server\share`) is NOT unwrapped —
    /// nothing here produces it.
    function roots_eq(self, a: string, b: string) -> bool throws unknown;

    /// Whether two segments (or two roots) name the same thing.
    ///
    /// The Windows fold is ASCII-only, matching dart's `Style.windows`
    /// comparison. That is deliberately narrower than the full-Unicode
    /// `to_lowercase()` that `importer::absolute_normalized` applies to a
    /// canonical key, so a path with a non-ASCII uppercase letter does not
    /// relativise and is displayed absolute — which is what dart does with it
    /// too, out of the same mismatch between its `canonicalizePart` and its
    /// comparison.
    function same(self, a: string, b: string) -> bool throws unknown;
}

implements StyleMethods for Style {
    /// The separator to spell a path WITH. Windows reads `/` as a separator too
    /// (see [`Style::is_sep`]), but dart writes `\` there, so a diagnostic path
    /// does.
    function sep(self) -> string {
        match (self) {
            Style.Posix => "/",
            Style.Windows => "\\",
        }
    }

    /// Whether `c` separates two segments.
    function is_sep(self, c: string) -> bool {
        c == "/" || (self == Style.Windows && c == "\\")
    }

    /// The byte length of `p`'s absolute root — `0` when `p` is relative.
    ///
    /// Windows has four spellings: a drive (`C:\`), a UNC share
    /// (`\\server\share\`), the current drive's root (`\`), and a verbatim or
    /// device wrapper around a drive (`\\?\C:\`, `\\.\C:\`) — which
    /// `std::fs::canonicalize` produces and `current_dir` never does.
    ///
    /// PORT: measured in CHARACTERS (every use slices `p` with it); the
    /// root's characters are all ASCII in the shapes that count.
    function root_len(self, p: string) -> int {
        if (self == Style.Posix) {
            return if (p.starts_with("/")) { 1 } else { 0 };
        }
        let skip = if (p.starts_with("\\\\?\\") || p.starts_with("\\\\.\\")) {
            4
        } else {
            0
        };
        let rest = p.slice(skip, p.length());
        let b = rest.chars();
        // A drive letter is a root only with a separator after it. `C:foo` is
        // DRIVE-RELATIVE — the current directory on C:, which a process tracks
        // per drive — so it has no root at all and nothing can be measured
        // from it.
        if (b.length() >= 2 && root.std.is_ascii_alphabetic(b[0]) && b[1] == ":") {
            let sep = b.length() > 2 && self.is_sep(b[2]);
            return if (sep) { skip + 3 } else { 0 };
        }
        // A UNC share: two separators, a server, a separator, a share. The
        // share is part of the root — `\\a\b` and `\\a\c` share no directory.
        if (skip == 0 && b.length() >= 2 && self.is_sep(b[0]) && self.is_sep(b[1])) {
            let end = 2;
            let k = 0;
            while (k < 2) {
                end += root.std.find_by(rest.slice(end, b.length()), (c: string) -> bool { self.is_sep(c) }) ?? (b.length() - end);
                if (end < b.length()) {
                    end += 1;
                }
                k += 1;
            }
            return end;
        }
        // The current drive's root.
        if (b.length() > 0 && self.is_sep(b[0])) { 1 } else { 0 }
    }

    /// `p`'s absolute root, or `None` when `p` is relative.
    function root(self, p: string) -> string? {
        let n = self.root_len(p);
        if (n > 0) { p.slice(0, n) } else { null }
    }

    /// `p`'s non-empty segments, with its root and any repeated separators
    /// dropped.
    function segments(self, p: string) -> string[] {
        // PORT: `split(|c| self.is_sep(c))` (a char-predicate split) done by
        // hand; the iterator is collected eagerly.
        let rest = p.slice(self.root_len(p), p.length());
        let cs = rest.chars();
        let parts: string[] = [];
        let start = 0;
        let i = 0;
        while (i < cs.length()) {
            if (self.is_sep(cs[i])) {
                parts.push(rest.slice(start, i));
                start = i + 1;
            }
            i += 1;
        }
        parts.push(rest.slice(start, cs.length()));
        parts.filter((s: string) -> bool { s != "" })
    }

    /// Whether two absolute roots name the same one. On Windows a drive letter
    /// is case-insensitive, `/` and `\` are the same separator, and a verbatim
    /// or device marker is not part of the identity: `std::fs::canonicalize`
    /// emits one where `current_dir` does not, so the two sides of a comparison
    /// routinely disagree about it.
    ///
    /// A trailing separator is not part of the identity either: a share is
    /// spelled `\\server\share` when it is the whole path and
    /// `\\server\share\` when something follows, so the two sides of a
    /// comparison disagree about it whenever the working directory IS the
    /// share.
    ///
    /// The verbatim UNC form (`\\?\UNC\server\share`) is NOT unwrapped —
    /// nothing here produces it.
    function roots_eq(self, a: string, b: string) -> bool {
        if (self == Style.Posix) {
            return a == b;
        }
        // PORT: nested `fn bare` hoisted to `roots_eq__bare` below.
        self.same(roots_eq__bare(self, a), roots_eq__bare(self, b))
    }

    /// Whether two segments (or two roots) name the same thing.
    ///
    /// The Windows fold is ASCII-only, matching dart's `Style.windows`
    /// comparison. That is deliberately narrower than the full-Unicode
    /// `to_lowercase()` that `importer::absolute_normalized` applies to a
    /// canonical key, so a path with a non-ASCII uppercase letter does not
    /// relativise and is displayed absolute — which is what dart does with it
    /// too, out of the same mismatch between its `canonicalizePart` and its
    /// comparison.
    function same(self, a: string, b: string) -> bool {
        if (self == Style.Posix) {
            return a == b;
        }
        // PORT: the two `chars()` iterators become index cursors.
        let x = a.chars();
        let y = b.chars();
        let i = 0;
        while (true) {
            let p = x.at(i);
            let q = y.at(i);
            i += 1;
            if (p == null && q == null) {
                return true;
            } else if (p != null && q != null) {
                let alike = root.std.eq_ignore_ascii_case(p, q) || (self.is_sep(p) && self.is_sep(q));
                if (!alike) {
                    return false;
                }
            } else {
                return false;
            }
        }
        false
    }

}

/// `fn bare` nested in [`Style::roots_eq`].
function roots_eq__bare(style: Style, r: string) -> string {
    let inner = root.std.strip_prefix(r, "\\\\?\\") ?? root.std.strip_prefix(r, "\\\\.\\");
    if (inner != null) {
        // Only a drive root survives the unwrap: see the note above.
        if (style.root_len(inner) == inner.length()) {
            r = inner;
        }
    }
    // `> 0` keeps the current drive's root, which is nothing BUT a
    // separator, from being trimmed away to the empty string.
    let c = root.std.last_char(r);
    let i = r.length() - 1;
    if (c != null) {
        if (i > 0 && style.is_sep(c)) {
            return r.slice(0, i);
        }
    }
    r
}

/// The segments of the relative path from directory `base` to `target`, or
/// `None` when there is no relative spelling at all: one of the two is not
/// absolute, or their roots differ (`D:\x` from `C:\y`, `\\a\b` from `\\a\c`).
///
/// Callers join with whatever separator their OUTPUT wants — `/` for a
/// source-map URL on every platform, [`Style::sep`] for a diagnostic path —
/// which is why this hands back the pieces rather than a string.
function relative_parts(style: Style, base: string, target: string) -> string[]? {
    let base_root = style.root(base);
    if (base_root == null) {
        return null;
    }
    let target_root = style.root(target);
    if (target_root == null) {
        return null;
    }
    if (!style.roots_eq(base_root, target_root)) {
        return null;
    }
    let base = style.segments(base);
    let target = style.segments(target);
    // PORT: `zip(..).take_while(same).count()` as an index loop.
    let common = 0;
    while (common < base.length() && common < target.length() && style.same(base[common], target[common])) {
        common += 1;
    }
    let parts = baml.Array.filled(base.length() - common, "..");
    root.std.extend(parts, target.slice(common, target.length()));
    parts
}

/// dart's `p.prettyUri` for a filesystem path: `abs` spelled relative to the
/// directory `cwd`, unless that would take more segments than `abs` itself (a
/// file far outside the tree reads better as itself than as a stack of `..`).
///
/// Both arguments must already be absolute and lexically normalized — this
/// decides a SPELLING, it does not resolve `.` or `..`. dart renders every
/// stack frame through it, the entry stylesheet's included (#151), which is
/// why it lives here rather than beside one caller.
function pretty(style: Style, abs: string, cwd: string) -> string {
    let parts = relative_parts(style, cwd, abs);
    if (parts == null) {
        // No relative spelling exists — a different drive or share, or a
        // current directory that is not absolute. dart's `p.relative` hands
        // the target back unchanged there.
        return abs;
    }
    // dart keeps the relative spelling only while it is no longer, in segments,
    // than the absolute one; its `p.split` counts the root (`/`, `C:\`,
    // `\\server\share`) as one segment, which `segments` excludes.
    if (parts.length() > 1 + style.segments(abs).length()) {
        return abs;
    }
    if (parts.length() == 0) {
        // `abs` IS `cwd`: dart's `p.relative(x, from: x)` is `.`, and one
        // segment never loses the comparison above.
        return ".";
    }
    root.std.join(parts, style.sep())
}

/// The filesystem path a `file://` URL names, or `None` for anything else —
/// a `data:` URL, a custom importer's key, a bare path.
///
/// Only the shapes a stylesheet URL actually takes are handled, and the rest
/// are declined rather than guessed at. `file:///a/b` is `/a/b`;
/// `file://localhost/a/b` is the same file spelled the long way (RFC 8089, and
/// the importer's own decoder in `napi` accepts it, so a frame must too);
/// `file://server/share/a` is a UNC path under [`Style::Windows`] and nothing
/// under [`Style::Posix`], which has no spelling for it. Percent escapes are
/// decoded, because a directory called `my docs` arrives as `my%20docs` and a
/// frame that said so would name a file nobody has.
function file_url_path(style: Style, url: string) -> string? {
    // LOSSY, because this one produces a path to SHOW: a frame naming a
    // file with an undecodable byte in it is still better than no frame.
    // Whoever is about to OPEN the path wants the strict half instead —
    // `crate::file_url_to_path`.
    let bytes = file_url_bytes(style, url);
    if (bytes == null) {
        return null;
    }
    root.std.from_utf8_lossy(bytes)
}

/// The bytes a `file:` URL names: percent-decoding done, and nothing about
/// UTF-8 decided.
///
/// This is the half that kept drifting. `napi/src/lib.rs` had its own copy
/// of it, and the two had already disagreed twice:
///
///   file://localhost/a   napi accepted it, this one declined   (fixed #161)
///   file:///a%FFb        this one decoded lossily, napi refused
///
/// The first was a bug in one copy. The second is not — they want
/// different answers, because one produces a path to SHOW and the other
/// one to READ. So the structure lives here once (the `file://` prefix,
/// the empty and `localhost` authorities, a drive letter arriving as
/// `/C:/`, a UNC authority, which separator comes out) and the UTF-8
/// policy is stated at each edge instead of copied with the rest.
function file_url_bytes(style: Style, url: string) -> uint8array? {
    let rest = root.std.strip_prefix(url, "file://");
    if (rest == null) {
        return null;
    }
    // The `localhost` authority means the local machine, exactly as the empty
    // one does. Keep the slash that introduces the path.
    let after_localhost = root.std.strip_prefix(rest, "localhost/");
    rest
        = if (after_localhost != null) {
            rest.slice(rest.length() - after_localhost.length() - 1, rest.length())
        } else {
            rest
        };
    // `file:///a` (empty authority, the usual spelling) vs `file://host/share`.
    let sep = (b: uint8array) -> uint8array {
        if (style == Style.Windows) {
            // PORT: `uint8array` has no element assignment; the bytes are
            // copied with each `/` turned into `\`.
            let out = "".to_utf8();
            for (let c in b.to_array()) {
                out.push(
                    if (c == 47) {
                        92
                    } else {
                        c
                    },
                );
            }
            out
        } else {
            b
        }
    };
    let local = root.std.strip_prefix(rest, "/");
    let bytes = if (local != null) {
        let decoded = percent_decode_bytes(local);
        match (style) {
            // A drive letter arrives as `/C:/a`, and the leading slash is the
            // URL's, not the path's.
            Style.Windows if is_drive_start_bytes(decoded) => sep(decoded),
            Style.Windows => {
                let out = "\\".to_utf8();
                out.concat(sep(decoded))
            },
            Style.Posix => {
                let out = "/".to_utf8();
                out.concat(decoded)
            },
        }
    } else if (rest == "") {
        return null;
    } else {
        // An authority. Only Windows can spell it.
        if (style == Style.Posix) {
            return null;
        }
        let out = "\\\\".to_utf8();
        out.concat(sep(percent_decode_bytes(rest)))
    };
    bytes
}

/// Whether `name` begins with a URL scheme.
///
/// A scheme of ONE letter is read as a Windows drive instead (`C:\a`), which
/// is the rule dart's `package:path` and every browser use; without it every
/// Windows path would look like a URL. `data:` has no `//`, so looking for
/// one is not enough.
function has_scheme(name: string) -> bool {
    let colon = name.index_of(":");
    if (colon == null) {
        return false;
    }
    if (colon < 2) {
        return false;
    }
    let chars = name.slice(0, colon).chars();
    root.std.is_ascii_alphabetic(chars.at(0))
        && chars.slice(1, chars.length()).every((c: string) -> bool {
            c.is_ascii_alphanumeric() || c == "+" || c == "-" || c == "."
        })
}

/// Whether `p` starts with a drive letter (`C:` or `C:/`).
function is_drive_start_bytes(p: uint8array) -> bool {
    // PORT: the slice patterns `[c, b':', ..]` / `[c, b':']` as length checks.
    (p.length() >= 2 && root.std.is_ascii_alphabetic(root.std.chr_unchecked(p[0])) && p[1] == 58)
        || (
            p.length() == 2
                && root.std.is_ascii_alphabetic(root.std.chr_unchecked(p[0]))
                && p[1] == 58
        )
}

function is_drive_start(p: string) -> bool {
    let b = p.to_utf8();
    b.length() >= 2 && root.std.is_ascii_alphabetic(root.std.chr_unchecked(b[0])) && b[1] == 58
}

/// `%XX` escapes decoded, everything else left alone. A stray `%` that is not
/// followed by two hex digits is a literal `%`, which is what browsers and
/// dart's `Uri.toFilePath` both do.
function percent_decode(s: string) -> string {
    root.std.from_utf8_lossy(percent_decode_bytes(s))
}

/// [`percent_decode`] without deciding what the bytes mean.
function percent_decode_bytes(s: string) -> uint8array {
    if (!s.includes("%")) {
        return s.to_utf8();
    }
    let b = s.to_utf8();
    let out = "".to_utf8();
    let i = 0;
    while (i < b.length()) {
        let hex = (c: int) -> int? {
            root.std.to_digit(root.std.chr_unchecked(c), 16)
        };
        let b1 = b.at(i + 1);
        let b2 = b.at(i + 2);
        let hi = if (b1 != null) {
            hex(b1)
        } else {
            null
        };
        let lo = if (b2 != null) {
            hex(b2)
        } else {
            null
        };
        if (b.at(i) == 37 && hi != null && lo != null) {
            out.push(hi * 16 + lo);
            i += 3;
        } else {
            out.push(b[i]);
            i += 1;
        }
    }
    out
}

/// How a stack frame names a file, given whatever the compiler was handed:
/// a path or a `file://` URL, absolute or not.
///
/// The two front ends arrive here with different spellings of the same thing —
/// the binary passes paths, the JS API passes `file://` URLs because its
/// importer bridge resolves relative `@use` against them — and dart shows both
/// as a path relative to the working directory. `cwd` is `None` when the
/// process has no readable one, which for `wasm32-unknown-unknown` is always:
/// there is no `getcwd` to call, so the host has to say.
///
/// Returns `None` unless `name` names a file ABSOLUTELY — a `data:` URL, a
/// custom importer's key, and a name that is already relative all keep
/// whatever rule the caller has for them. A relative key in particular must
/// not be mistaken for a path: a custom importer's `virtual/foo.scss` shows
/// as `foo.scss`, and handing it back whole would be a different frame.
function pretty_name(style: Style, name: string, cwd: string?) -> string? {
    let from_url = file_url_path(style, name);
    let abs = if (from_url != null) {
        from_url
    } else if (has_scheme(name)) {
        return null; // an importer's URL, not a file
    } else {
        name
    };
    if (style.root_len(abs) == 0) {
        return null;
    }
    match (cwd) {
        let c: string => pretty(style, abs, c),
        null => abs,
    }
}

/// Which platform's rules to read a diagnostic name by.
///
/// [`HOST`] is decided when the binary is COMPILED, and one build runs
/// somewhere it cannot describe: the wasm module is `wasm32-unknown-unknown`,
/// so `HOST` is always `Posix` there — including on Windows node, where the
/// host hands it `C:\work` and `file:///C:/work/a.scss`. Reading those by
/// POSIX rules leaves `/C:/work/a.scss` in the frame, which is neither the
/// path nor what the addon on the same machine prints.
///
/// So the spelling decides, and `HOST` is the answer only when nothing in the
/// data says otherwise. A POSIX working directory never begins with a drive
/// letter or a UNC root, so this cannot change what a native build does.
function style_for(cwd: string?, name: string) -> Style {
    let windows_shaped = (s: string) -> bool {
        // An authority that is not the local machine is a UNC share, and only
        // Windows has a spelling for one — so such a URL says which platform
        // it came from even when nothing else does. Without this the no-cwd
        // fallback declined `file://server/share/a.scss` and printed it.
        let auth = root.std.strip_prefix(s, "file://");
        if (auth != null) {
            if (
                auth != ""
                    && !auth.starts_with("/")
                    && auth != "localhost"
                    && !auth.starts_with("localhost/")
            ) {
                return true;
            }
        }
        // Decoded first, because `file_url_path` decodes and these two have
        // to agree: `file:///C%3A/work/a.scss` is a drive, and reading it
        // raw makes it a POSIX path called `C%3A`.
        let rest = root.std.strip_prefix(s, "file:///");
        let s = if (rest != null) {
            percent_decode(rest)
        } else {
            s
        };
        // A drive letter or a UNC root. NOT a lone leading backslash: a POSIX
        // file name may contain one, and `process.cwd()` on Windows is always
        // drive-rooted, so nothing is lost by declining the ambiguous case.
        is_drive_start(s) || s.starts_with("\\\\")
    };
    if (cwd != null) {
        if (windows_shaped(cwd)) {
            Style.Windows
        } else {
            HOST()
        }
    } else if (windows_shaped(name)) {
        Style.Windows
    } else {
        HOST()
    }
}
