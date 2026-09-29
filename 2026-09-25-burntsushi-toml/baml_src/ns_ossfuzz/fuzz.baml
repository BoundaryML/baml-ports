// Port of ossfuzz/fuzz.go (namespace root.ossfuzz).
//
// OSS-Fuzz calls FuzzToml with arbitrary bytes. BAML has no fuzzing harness;
// fuzz_test.baml drives this function with a seed corpus and deterministic
// mutations instead.

function fuzz_toml(data: int[]) -> int {
    if (data.length() >= 2048) {
        return 0;
    }

    let d = root.new_decoder(root.go.new_bytes_reader(data)).decode<root.Any>(null) catch (err) {
        let e: root.TomlError => {
            return 0;
        },
    };

    let buf = root.go.new_buffer();
    root.new_encoder(buf).encode(d.value) catch (err) {
        let e: root.TomlError => root.go_panic(`failed to encode decoded document: ${e.error()}`),
    };

    let _ = root.decode<root.Any>(buf.string()) catch (err) {
        let e: root.TomlError => root.go_panic(`failed round trip: ${e.error()}`),
    };

    1
}
