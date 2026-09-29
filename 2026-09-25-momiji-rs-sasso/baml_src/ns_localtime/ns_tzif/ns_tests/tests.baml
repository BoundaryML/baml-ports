// Ported from sasso `src/localtime/tzif.rs` `mod tests` (namespace `root.localtime.tzif.tests`).
//
// PORT: `use super::*;` → items of `root.localtime.tzif` are written fully qualified.

// Vendored rather than read from the host: the test must give the same
// answer on a machine with different tzdata, on Windows CI where there
// is no zoneinfo at all, and in five years when these zones' rules have
// moved on.
// PORT: each `const X: &[u8] = include_bytes!("../../tests/fixtures/tz/…")`
// → a zero-arg function returning the same bytes, embedded as base64 (so
// they are compiled in, as `include_bytes!` does). Each call returns a
// FRESH array, so `NEW_YORK.to_vec()` is written `NEW_YORK()`.
// America_New_York: 3552 bytes, sha256 e9ed07d7…e6c18a95.
function NEW_YORK() -> uint8array {
    uint8array.from_base64(
        "VFppZjIAAAAAAAAAAAAAAAAAAAAAAAAGAAAABgAAAAAAAADsAAAABgAAABSAAAAAnqYecJ+662CghgBwoZrNYKJl4nCjg+ngpGqucKU1p2CmU8rwpxWJYKgzrPCo/qXgqhOO8Kreh+Cr83DwrL5p4K3TUvCunkvgr7M08LB+LeCxnFFwsmdKYLN8M3C0RyxgtVwVcLYnDmC3O/dwuAbwYLkb2XC55tJguwT18LvGtGC85Nfwva/Q4L7EufC/j7LgwKSb8MFvlODChH3ww0924MRkX/DFL1jgxk18cMcPOuDILV5wyPhXYMoNQHDK2Dlgy4jwcNIj9HDSYPvg03Xk8NRA3eDVVcbw1iC/4Nc1qPDYAKHg2RWK8Nngg+Da/qdw28Bl4NzeiXDdqYJg3r5rcN+JZGDgnk1w4WlGYOJ+L3DjSShg5F4RcOVXLuDmRy3w5zcQ4OgnD/DpFvLg6gbx8Or21ODr5tPw7Na24O3GtfDuv9Ng76/ScPCftWDxj7Rw8n+XYPNvlnD0X3lg9U94cPY/W2D3L1pw+Ch34PkPPHD6CFng+vhY8PvoO+D82Drw/cgd4P64HPD/p//gAJf+8AGH4eACd+DwA3D+YARg/XAFUOBgBkDfcAcwwmAHjRlwCRCkYAmtlPAK8IZgC+CFcAzZouANwGdwDrmE4A+pg/AQmWbgEYll8BJ5SOATaUfwFFkq4BVJKfAWOQzgFykL8BgiKWAZCO3wGgILYBryCnAb4e1gHNHscB3Bz2Aesc5wH6GxYCB2APAhgZNgIlXi8CNqr+AkNcTwJUqR4CYVpvAnKnPgJ/7DcCkKVeAp3qVwKuo34Cu+h3As01RgLZ5pcC6zNmAvfktwMJMYYDFnZ/AycvpgM0dJ8DRS3GA1JyvwNjK+YDcHDfA4G9rgOObv8Dn7vOA6xtHwO9ue4Dyv7nA9u4DgPo/QcD+bYuBAb7JwQYR/YEJPlHBDZGFgRC92cEVEQ2BF86jwRy1f4EfTivBJDUHgSbNs8ErtI+BLnIlwTNZAYE18a3BOtiJgT1xNcFCWBGBRPC9wUnXmYFMcEXBUVchgVPvzcFY1qmBW5Q/wWB7G4FjE8fBZ/qjgWqTT8FveiuBchLXwXb5s4F5kl/Bfnk7gYE20cGGHa2BiLZZwY2dNYGQNeHBlRy9gZe1acGcnEWBnzTxwaQbzYGmtHnBq5tVga5Y68GzP8eBtdhzwbq/T4G9V/vBwj7XgcTXg8HJvl+BzFcLwdE954HT+33B2OJZgdt7BcHgYeGB4vqNwefhaYHqehXB72DxgfH5ncH24HmB+Xklwf5gAYAMBAgECAQIBAgECAQIBAgECAQIBAgECAQIBAgECAQIBAgECAQIBAgECAQIBAgECAQIEBQIBAgECAQIBAgECAQIBAgECAQIBAgECAQIBAgECAQIBAgECAQIBAgECAQIBAgECAQIBAgECAQIBAgECAQIBAgECAQIBAgECAQIBAgECAQIBAgECAQIBAgECAQIBAgECAQIBAgECAQIBAgECAQIBAgECAQIBAgECAQIBAgECAQIBAgECAQIBAgECAQIBAgECAQIBAgECAQIBAgECAQIBAgECAQIBAgECAQIBAgECAQIBAgECAQIBAgEC//+6ngAA///HwAEE//+5sAAI//+5sAAI///HwAEM///HwAEQTE1UAEVEVABFU1QARVdUAEVQVAAAAAABAAEAAAABAAFUWmlmMgAAAAAAAAAAAAAAAAAAAAAAAAYAAAAGAAAAAAAAAOwAAAAGAAAAFP////9eA/CQ/////56mHnD/////n7rrYP////+ghgBw/////6GazWD/////omXicP////+jg+ng/////6RqrnD/////pTWnYP////+mU8rw/////6cViWD/////qDOs8P////+o/qXg/////6oTjvD/////qt6H4P////+r83Dw/////6y+aeD/////rdNS8P////+unkvg/////6+zNPD/////sH4t4P////+xnFFw/////7JnSmD/////s3wzcP////+0Ryxg/////7VcFXD/////ticOYP////+3O/dw/////7gG8GD/////uRvZcP////+55tJg/////7sE9fD/////u8a0YP////+85Nfw/////72v0OD/////vsS58P////+/j7Lg/////8Ckm/D/////wW+U4P/////ChH3w/////8NPduD/////xGRf8P/////FL1jg/////8ZNfHD/////xw864P/////ILV5w/////8j4V2D/////yg1AcP/////K2Dlg/////8uI8HD/////0iP0cP/////SYPvg/////9N15PD/////1EDd4P/////VVcbw/////9Ygv+D/////1zWo8P/////YAKHg/////9kVivD/////2eCD4P/////a/qdw/////9vAZeD/////3N6JcP/////dqYJg/////96+a3D/////34lkYP/////gnk1w/////+FpRmD/////4n4vcP/////jSShg/////+ReEXD/////5Vcu4P/////mRy3w/////+c3EOD/////6CcP8P/////pFvLg/////+oG8fD/////6vbU4P/////r5tPw/////+zWtuD/////7ca18P/////uv9Ng/////++v0nD/////8J+1YP/////xj7Rw//////J/l2D/////82+WcP/////0X3lg//////VPeHD/////9j9bYP/////3L1pw//////god+D/////+Q88cP/////6CFng//////r4WPD/////++g74P/////82Drw//////3IHeD//////rgc8P//////p//gAAAAAACX/vAAAAAAAYfh4AAAAAACd+DwAAAAAANw/mAAAAAABGD9cAAAAAAFUOBgAAAAAAZA33AAAAAABzDCYAAAAAAHjRlwAAAAAAkQpGAAAAAACa2U8AAAAAAK8IZgAAAAAAvghXAAAAAADNmi4AAAAAANwGdwAAAAAA65hOAAAAAAD6mD8AAAAAAQmWbgAAAAABGJZfAAAAAAEnlI4AAAAAATaUfwAAAAABRZKuAAAAAAFUkp8AAAAAAWOQzgAAAAABcpC/AAAAAAGCIpYAAAAAAZCO3wAAAAABoCC2AAAAAAGvIKcAAAAAAb4e1gAAAAABzR7HAAAAAAHcHPYAAAAAAesc5wAAAAAB+hsWAAAAAAIHYA8AAAAAAhgZNgAAAAACJV4vAAAAAAI2qv4AAAAAAkNcTwAAAAACVKkeAAAAAAJhWm8AAAAAAnKnPgAAAAACf+w3AAAAAAKQpV4AAAAAAp3qVwAAAAACrqN+AAAAAAK76HcAAAAAAs01RgAAAAAC2eaXAAAAAALrM2YAAAAAAvfktwAAAAADCTGGAAAAAAMWdn8AAAAAAycvpgAAAAADNHSfAAAAAANFLcYAAAAAA1JyvwAAAAADYyvmAAAAAANwcN8AAAAAA4G9rgAAAAADjm7/AAAAAAOfu84AAAAAA6xtHwAAAAADvbnuAAAAAAPK/ucAAAAAA9u4DgAAAAAD6P0HAAAAAAP5ti4AAAAABAb7JwAAAAAEGEf2AAAAAAQk+UcAAAAABDZGFgAAAAAEQvdnAAAAAARURDYAAAAABF86jwAAAAAEctX+AAAAAAR9OK8AAAAABJDUHgAAAAAEmzbPAAAAAASu0j4AAAAABLnIlwAAAAAEzWQGAAAAAATXxrcAAAAABOtiJgAAAAAE9cTXAAAAAAUJYEYAAAAABRPC9wAAAAAFJ15mAAAAAAUxwRcAAAAABUVchgAAAAAFT783AAAAAAVjWqYAAAAABW5Q/wAAAAAFgexuAAAAAAWMTx8AAAAABZ/qjgAAAAAFqk0/AAAAAAW96K4AAAAABchLXwAAAAAF2+bOAAAAAAXmSX8AAAAABfnk7gAAAAAGBNtHAAAAAAYYdrYAAAAABiLZZwAAAAAGNnTWAAAAAAZA14cAAAAABlRy9gAAAAAGXtWnAAAAAAZycRYAAAAABnzTxwAAAAAGkG82AAAAAAaa0ecAAAAABq5tVgAAAAAGuWOvAAAAAAbM/x4AAAAABtdhzwAAAAAG6v0+AAAAAAb1X+8AAAAABwj7XgAAAAAHE14PAAAAAAcm+X4AAAAABzFcLwAAAAAHRPeeAAAAAAdP7fcAAAAAB2OJZgAAAAAHbewXAAAAAAeBh4YAAAAAB4vqNwAAAAAHn4WmAAAAAAep6FcAAAAAB72DxgAAAAAHx+Z3AAAAAAfbgeYAAAAAB+XklwAAAAAH+YAGADAQIBAgECAQIBAgECAQIBAgECAQIBAgECAQIBAgECAQIBAgECAQIBAgECAQIBAgECBAUCAQIBAgECAQIBAgECAQIBAgECAQIBAgECAQIBAgECAQIBAgECAQIBAgECAQIBAgECAQIBAgECAQIBAgECAQIBAgECAQIBAgECAQIBAgECAQIBAgECAQIBAgECAQIBAgECAQIBAgECAQIBAgECAQIBAgECAQIBAgECAQIBAgECAQIBAgECAQIBAgECAQIBAgECAQIBAgECAQIBAgECAQIBAgECAQIBAgECAQIBAgECAQIBAgECAQIBAv//up4AAP//x8ABBP//ubAACP//ubAACP//x8ABDP//x8ABEExNVABFRFQARVNUAEVXVABFUFQAAAAAAQABAAAAAQABCkVTVDVFRFQsTTMuMi4wLE0xMS4xLjAK",
    )
}

// Asia_Kathmandu: 198 bytes, sha256 fd1b1f79…16cf8e83.
function KATHMANDU() -> uint8array {
    uint8array.from_base64(
        "VFppZjIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACAAAAAwAAABCh8n2EHhgwqAECAABP/AAAAABNWAAEAABQ3AAKTE1UACswNTMwACswNTQ1AFRaaWYyAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAgAAAAMAAAAQ/////6HyfYQAAAAAHhgwqAECAABP/AAAAABNWAAEAABQ3AAKTE1UACswNTMwACswNTQ1AAo8KzA1NDU+LTU6NDUK",
    )
}

// UTC: 114 bytes, sha256 8b858467…47e3e6f2.
function UTC() -> uint8array {
    uint8array.from_base64(
        "VFppZjIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQAAAAQAAAAAAABVVEMAVFppZjIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQAAAAQAAAAAAABVVEMAClVUQzAK",
    )
}

test "a_zone_with_dst" {
    let tz = root.std.expect(root.localtime.tzif.TimeZone.parse(NEW_YORK()), "parse");
    // 2026-01-15 12:00 UTC — winter, EST.
    assert.equal(tz.offset_at(1768478400), -5 * 3600);
    // 2026-07-15 12:00 UTC — summer, EDT.
    assert.equal(tz.offset_at(1784116800), -4 * 3600)
}

test "past_the_table_the_footer_answers" {
    let tz = root.std.expect(root.localtime.tzif.TimeZone.parse(NEW_YORK()), "parse");
    // 2065-07-01, long past the tabulated transitions. Without the
    // footer this was EST and an hour wrong.
    assert.equal(tz.offset_at(3013651200), -4 * 3600);
    // 2065 winter
    assert.equal(tz.offset_at(3000000000), -5 * 3600)
}

test "a_zone_with_no_dst_and_a_45_minute_offset" {
    let tz = root.std.expect(root.localtime.tzif.TimeZone.parse(KATHMANDU()), "parse");
    assert.equal(tz.offset_at(1768478400), 5 * 3600 + 45 * 60);
    // Fixed offsets must stay fixed however far out you look.
    // 2100
    assert.equal(tz.offset_at(4102444800), 5 * 3600 + 45 * 60)
}

test "utc_is_zero_everywhere" {
    let tz = root.std.expect(root.localtime.tzif.TimeZone.parse(UTC()), "parse");
    // PORT: `i64::from(i32::MIN)` → its value.
    for (let t in [-2147483648, -1, 0, 1, 1768478400, 4102444800]) {
        // at {t}
        assert.equal(tz.offset_at(t), 0);
    }
}

test "before_the_first_transition" {
    let tz = root.std.expect(root.localtime.tzif.TimeZone.parse(NEW_YORK()), "parse");
    // 1850, before any tabulated transition: RFC 8536 says the first
    // non-DST type, which for New York is Local Mean Time.
    let off = root.std.expect(tz.offset_at(-3786825600), "an offset");
    // LMT-ish, got {off}
    assert.is_true(off >= -5 * 3600 - 300 && off <= -5 * 3600 + 300)
}

// Malformed input must come back as `None`. A build tool that panics
// while deciding what time it is has failed worse than one that prints
// no timestamp.
test "corrupt_input_never_panics" {
    // empty
    assert.is_true(root.localtime.tzif.TimeZone.parse(b"") == null);
    // bad magic
    assert.is_true(root.localtime.tzif.TimeZone.parse(b"not a tzif file at all") == null);

    // Every truncation of a real file.
    let ny = NEW_YORK();
    for (let n in baml.iter.Range.new(0, ny.length())) {
        let tz = root.localtime.tzif.TimeZone.parse(ny.slice(0, n));
        if (tz != null) {
            let _ = tz.offset_at(0);
        }
    }

    // A version 1 file: refused, not misread.
    let v1 = NEW_YORK();
    v1[4] = 49; // b'1'
    // version 1 is refused
    assert.is_true(root.localtime.tzif.TimeZone.parse(v1) == null);

    // Absurd counts, which is how a corrupt file overflows a reader that
    // multiplies before it checks.
    // PORT: `copy_from_slice(&u32::MAX.to_be_bytes())` → four 0xFF bytes.
    let huge = NEW_YORK();
    for (let k in baml.iter.Range.new(32, 36)) {
        huge[k] = 255;
    } // timecnt
    // timecnt = u32::MAX
    assert.is_true(root.localtime.tzif.TimeZone.parse(huge) == null);
    let huge = NEW_YORK();
    for (let k in baml.iter.Range.new(36, 40)) {
        huge[k] = 255;
    } // typecnt
    // typecnt = u32::MAX
    assert.is_true(root.localtime.tzif.TimeZone.parse(huge) == null);

    // Single-byte corruption anywhere in the header region.
    for (let i in baml.iter.Range.new(0, root.std.imin(64, ny.length()))) {
        let b = NEW_YORK();
        b[i] = b[i] ^ 255;
        let tz = root.localtime.tzif.TimeZone.parse(b);
        if (tz != null) {
            let _ = tz.offset_at(1768478400);
        }
    }
}

// A cheap deterministic fuzz: mutate a real file at pseudo-random and
// require only that nothing panics. No dependency — xorshift is four
// lines, and `rand` would be a dependency this crate does not take.
test "random_mutations_never_panic" {
    // PORT: the `u64` xorshift state is a bigint, masked to 64 bits after
    // each left shift (Rust's `<<` on u64 drops the high bits).
    let state: bigint = 0x2545F4914F6CDD1Dn;
    let next = () -> bigint {
        state = (state ^ (state << 13)) & root.std.U64_MASK();
        state = state ^ (state >> 7);
        state = (state ^ (state << 17)) & root.std.U64_MASK();
        state
    };
    for (let _r in baml.iter.Range.new(0, 2000)) {
        let b = NEW_YORK();
        let flips = root.std.int_of(next() % 8n) + 1;
        for (let _f in baml.iter.Range.new(0, flips)) {
            let at = root.std.int_of(next() % root.std.bigint_of(b.length()));
            b[at] = root.std.int_of(next() & 255n);
        }
        let tz = root.localtime.tzif.TimeZone.parse(b);
        if (tz != null) {
            // PORT: `(next() as i64) >> 8` — reinterpret the u64 as i64, then
            // an arithmetic shift (fits a BAML int).
            let u = next();
            let s = if (u >= (1n << 63)) {
                u - (1n << 64)
            } else {
                u
            };
            let _ = tz.offset_at(root.std.int_of(s >> 8));
        }
    }
}
