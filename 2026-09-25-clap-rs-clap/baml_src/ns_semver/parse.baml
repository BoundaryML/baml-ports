// Port of semver-1.x/src/parse.rs

class Cursor {
    chars: string[],
    pos: int,
}

function parse_version(text: string) -> Version throws Error {
    if (text.is_empty()) {
        throw error_empty();
    }
    let c = Cursor { chars: text.chars(), pos: 0 };
    let major = numeric_identifier(c, Position.Major);
    dot(c, Position.Major);
    let minor = numeric_identifier(c, Position.Minor);
    dot(c, Position.Minor);
    let patch = numeric_identifier(c, Position.Patch);

    let pre = "";
    if (c.pos < c.chars.length() && c.chars[c.pos] == "-") {
        c.pos += 1;
        pre = identifier(c, Position.Pre);
    }
    let build = "";
    if (c.pos < c.chars.length() && c.chars[c.pos] == "+") {
        c.pos += 1;
        build = identifier(c, Position.Build);
    }
    if (c.pos < c.chars.length()) {
        let pos: Position = if (!build.is_empty()) { Position.Build } else if (!pre.is_empty()) { Position.Pre } else { Position.Patch };
        throw error_unexpected_char_after(pos, c.chars[c.pos]);
    }
    Version { major: major, minor: minor, patch: patch, pre: pre, build: build }
}

function numeric_identifier(c: Cursor, pos: Position) -> int throws Error {
    let start = c.pos;
    let value = 0;
    while (c.pos < c.chars.length() && c.chars[c.pos].is_ascii_numeric()) {
        if (c.pos > start && c.chars[start] == "0") {
            throw error_leading_zero(pos);
        }
        let d = (c.chars[c.pos].code_point_at(0) ?? 48) - 48;
        if (value > (4611686018427387903 - d) / 10) {
            throw error_overflow(pos);
        }
        value = value * 10 + d;
        c.pos += 1;
    }
    if (c.pos == start) {
        if (c.pos >= c.chars.length()) {
            throw error_unexpected_end(pos);
        }
        throw error_unexpected_char(pos, c.chars[c.pos]);
    }
    value
}

function dot(c: Cursor, pos: Position) -> void throws Error {
    if (c.pos >= c.chars.length()) {
        throw error_unexpected_end(pos);
    }
    if (c.chars[c.pos] != ".") {
        throw error_unexpected_char_after(pos, c.chars[c.pos]);
    }
    c.pos += 1;
}

function identifier(c: Cursor, pos: Position) -> string throws Error {
    let start = c.pos;
    let segment_start = c.pos;
    while (c.pos < c.chars.length()) {
        let ch = c.chars[c.pos];
        if (ch.is_ascii_alphanumeric() || ch == "-") {
            c.pos += 1;
        } else if (ch == ".") {
            if (c.pos == segment_start) {
                throw error_empty_segment(pos);
            }
            c.pos += 1;
            segment_start = c.pos;
        } else {
            break;
        }
    }
    if (c.pos == segment_start) {
        if (c.pos >= c.chars.length()) {
            throw error_empty_segment(pos);
        }
        throw error_unexpected_char(pos, c.chars[c.pos]);
    }
    c.chars.slice(start, c.pos).join("")
}

testset "semver" {
    test "parse" {
        let v = Version.parse("10.0.0") catch_all (e) { _ => Version.new(0, 0, 0) };
        assert.equal(v.debug(), "Version { major: 10, minor: 0, patch: 0 }");
        assert.equal(`${Version.parse("1.2.3-alpha.1+build") catch_all (e) { _ => Version.new(0, 0, 0) }}`, "1.2.3-alpha.1+build")
    }
    test "errors" {
        let e1 = Version.parse("10") catch (e) { let x: Error => x.message };
        assert.equal(`${e1}`, "unexpected end of input while parsing major version number");
        let e2 = Version.parse("blue") catch (e) { let x: Error => x.message };
        assert.equal(`${e2}`, "unexpected character 'b' while parsing major version number");
        let e3 = Version.parse("1.0.01") catch (e) { let x: Error => x.message };
        assert.equal(`${e3}`, "invalid leading zero in patch version number");
        let e4 = Version.parse("") catch (e) { let x: Error => x.message };
        assert.equal(`${e4}`, "empty string, expected a semver version")
    }
}
