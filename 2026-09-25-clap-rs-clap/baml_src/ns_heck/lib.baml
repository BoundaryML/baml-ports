// Port of heck-0.5.0/src/lib.rs
//
// **heck** is a case conversion library. A dependency of `clap_derive`, which
// uses it to derive argument/command names from field and type names.
//
//   mod kebab;        -> kebab.baml        (to_kebab_case)
//   mod lower_camel;  -> lower_camel.baml  (to_lower_camel_case)
//   mod shouty_kebab; -> shouty_kebab.baml (to_shouty_kebab_case)
//   mod shouty_snake; -> shouty_snake.baml (to_shouty_snake_case)
//   mod snake;        -> snake.baml        (to_snake_case)
//   mod title;        -> title.baml        (to_title_case)
//   mod train;        -> train.baml        (to_train_case)
//   mod upper_camel;  -> upper_camel.baml  (to_upper_camel_case / to_pascal_case)
//
// Rust exposes the conversions as `ToXxxCase` extension traits on `str`; in
// BAML they are free functions over `string`.

enum WordMode {
    /// There have been no lowercase or uppercase characters in the current
    /// word.
    Boundary,
    /// The previous cased character in the current word was lowercase.
    Lowercase,
    /// The previous cased character in the current word was uppercase.
    Uppercase,
}

/// How each word is written
enum WordStyle {
    Lower,
    Upper,
    Capitalize,
}

/// Split `s` into words the way heck does: on non-alphanumeric characters and
/// on case boundaries (`fooBar` => `foo`, `Bar`; `HTTPServer` => `HTTP`, `Server`).
function words(s: string) -> string[] {
    let out: string[] = [];
    // `s.split(|c: char| !c.is_alphanumeric())`
    let pieces: string[] = [];
    let current = "";
    for (let c in s.chars()) {
        if (c.is_alphanumeric()) {
            current = current + c;
        } else {
            pieces.push(current);
            current = "";
        }
    }
    pieces.push(current);

    for (let word in pieces) {
        let chars = word.chars();
        let init = 0;
        let mode: WordMode = WordMode.Boundary;
        for (let i in baml.iter.Range.new(0, chars.length())) {
            let c = chars[i];
            if (i + 1 < chars.length()) {
                let next = chars[i + 1];
                let next_mode: WordMode = if (c.is_lowercase() && !c.is_uppercase() && c.is_alphabetic()) {
                    WordMode.Lowercase
                } else if (c.is_uppercase() && c.is_alphabetic()) {
                    WordMode.Uppercase
                } else {
                    mode
                };

                // Word boundary after if next is uppercase
                if (next_mode == WordMode.Lowercase && next.is_uppercase() && next.is_alphabetic()) {
                    out.push(chars.slice(init, i + 1).join(""));
                    init = i + 1;
                    mode = WordMode.Boundary;

                // Otherwise if current and previous are uppercase and next
                // is lowercase, word boundary before
                } else if (mode == WordMode.Uppercase && c.is_uppercase() && c.is_alphabetic() && next.is_lowercase() && next.is_alphabetic()) {
                    out.push(chars.slice(init, i).join(""));
                    init = i;
                    mode = WordMode.Boundary;

                // Otherwise no word boundary, just update the mode
                } else {
                    mode = next_mode;
                }
            } else {
                // Collect trailing characters as a word
                out.push(chars.slice(init, chars.length()).join(""));
                break;
            }
        }
    }
    out
}

function transform(s: string, style: WordStyle, boundary: string, first_style: WordStyle? = null) -> string {
    let ws = words(s);
    let out: string[] = [];
    for (let i in baml.iter.Range.new(0, ws.length())) {
        let st = if (i == 0) { first_style ?? style } else { style };
        out.push(match (st) {
            WordStyle.Lower => lowercase(ws[i]),
            WordStyle.Upper => ws[i].to_upper_case(),
            WordStyle.Capitalize => capitalize(ws[i]),
        });
    }
    out.join(boundary)
}

function lowercase(s: string) -> string {
    let chars = s.chars();
    let out = "";
    for (let i in baml.iter.Range.new(0, chars.length())) {
        let c = chars[i];
        if (c == "Σ" && i == chars.length() - 1) {
            out = out + "ς";
        } else {
            out = out + c.to_lower_case();
        }
    }
    out
}

function capitalize(s: string) -> string {
    if (s.is_empty()) {
        return s;
    }
    s.slice(0, 1).to_upper_case() + lowercase(s.slice(1, s.length()))
}
