// Port of cmd/toml-test-decoder/main.go (namespace root.cmd).
//
// Command toml-test-decoder satisfies the toml-test interface for testing TOML
// decoders. Namely, it accepts TOML on stdin and outputs JSON on stdout.
//
// Run with: baml run toml-test-decoder < file.toml   (see [scripts] in baml.toml)
//
// Go's flag package rejects positional arguments; `baml run` builds the CLI
// from the function signature, and this function takes none.

function toml_test_decoder() -> null {
    let input = read_stdin();
    let d = root.new_decoder(root.go.new_bytes_reader(input)).decode<root.Any>(null) catch (err) {
        let e: root.TomlError => log_fatal(`Error decoding TOML: ${e.error()}`),
    };

    baml.io.print(baml.json.stringify_pretty(sorted_json(root.tag.add("", d.value))) + "\n");
    null
}
