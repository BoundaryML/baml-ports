// Port of fuzz_test.go (and a driver for ossfuzz/fuzz.go).
//
// BAML has no fuzzing engine. FuzzDecode's body is kept as a function; the
// test runs it over the seed corpus (f.Add) plus deterministic mutations of
// the seed (byte flips/deletions/insertions from a seeded PRNG), which
// exercises the "must not panic" property the Go fuzz target checks.

function fuzz_seed() -> string {
    "
# This is an example TOML document which shows most of its features.

# Simple key/value with a string.
title = \"TOML example \\U0001F60A\"

desc = \"\"\"
An example TOML document. \\
\"\"\"

# Array with integers and floats in the various allowed formats.
integers = [42, 0x42, 0o42, 0b0110]
floats   = [1.42, 1e-02]

# Array with supported datetime formats.
times = [
	2021-11-09T15:16:17+01:00,  # datetime with timezone.
	2021-11-09T15:16:17Z,       # UTC datetime.
	2021-11-09T15:16:17,        # local datetime.
	2021-11-09,                 # local date.
	15:16:17,                   # local time.
]

# Durations.
duration = [\"4m49s\", \"8m03s\", \"1231h15m55s\"]

# Table with inline tables.
distros = [
	{name = \"Arch Linux\", packages = \"pacman\"},
	{name = \"Void Linux\", packages = \"xbps\"},
	{name = \"Debian\",     packages = \"apt\"},
]

# Create new table; note the \"servers\" table is created implicitly.
[servers.alpha]
	# You can indent as you please, tabs or spaces.
	ip        = '10.0.0.1'
	hostname  = 'server1'
	enabled   = false
[servers.beta]
	ip        = '10.0.0.2'
	hostname  = 'server2'
	enabled   = true

# Start a new table array; note that the \"characters\" table is created implicitly.
[[characters.star-trek]]
	name = \"James Kirk\"
	rank = \"Captain\\u0012 \\t\"
[[characters.star-trek]]
	name = \"Spock\"
	rank = \"Science officer\"

[undecoded] # To show the MetaData.Undecoded() feature.
	key = \"This table intentionally left undecoded\"
"
}

// The f.Fuzz body.
function fuzz_decode_one(file: int[]) -> null {
    let d = new_decoder(go.new_bytes_reader(file)).decode<map<string, Any>>(null) catch (err) {
        // Make sure ErrorWithPosition doesn't panic.
        let p_err: ParseError => {
            let _ = p_err.error_with_position();
            return null;
        },
        let e: TomlError => {
            return null;
        },
    };

    new_encoder(go.new_buffer()).encode(d.value) catch (err) {
        _ => null,
    };

    // TODO: should check if the output is equal to the input, too, but some
    // information is lost when encoding.
    null
}

function mutate(seed: int[], rng: baml.random.Xoshiro256PlusPlus) -> int[] {
    let out = seed.slice(0, seed.length());
    let edits = 1 + (rng.random_int().abs() % 4);
    let i = 0;
    while (i < edits) {
        let pos = rng.random_int().abs() % (out.length() + 1);
        let op = rng.random_int().abs() % 3;
        let b = rng.random_int().abs() % 256;
        if (op == 0 && pos < out.length()) {
            out[pos] = b;
        } else if (op == 1 && pos < out.length()) {
            out = out.slice(0, pos).concat(out.slice(pos + 1, out.length()));
        } else {
            out = out.slice(0, pos).concat([b]).concat(out.slice(pos, out.length()));
        }
        i += 1;
    }
    out
}

test "FuzzDecode_seed" {
    fuzz_decode_one(go.bytes_of(fuzz_seed()))
}

testset "FuzzDecode_mutations" {
    let rng = baml.random.Xoshiro256PlusPlus.new(seed = b"toml-baml-fuzz-seed-0123456789ab");
    let seed = go.bytes_of(fuzz_seed());
    let i = 0;
    while (i < 40) {
        let input = mutate(seed, rng);
        test `#${i}` {
            fuzz_decode_one(input)
        }
        i += 1;
    }
}

test "FuzzToml_ossfuzz_seed" {
    assert.equal(ossfuzz.fuzz_toml(go.bytes_of("a = 1\n[t]\nb = [1, 2]\n")), 1);
    assert.equal(ossfuzz.fuzz_toml(go.bytes_of("a = ")), 0)
}

testset "FuzzToml_ossfuzz_mutations" {
    let rng = baml.random.Xoshiro256PlusPlus.new(seed = b"toml-baml-ossfuzz-seed-012345678");
    let all = go.bytes_of(fuzz_seed());
    let seed = all.slice(0, go.min(all.length(), 1500));
    let i = 0;
    while (i < 20) {
        let input = mutate(seed, rng);
        test `#${i}` {
            let _ = ossfuzz.fuzz_toml(input);
        }
        i += 1;
    }
}
