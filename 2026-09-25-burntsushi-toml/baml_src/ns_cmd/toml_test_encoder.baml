// Port of cmd/toml-test-encoder/main.go (namespace root.cmd).
//
// Command toml-test-encoder satisfies the toml-test interface for testing TOML
// encoders. Namely, it accepts JSON on stdin and outputs TOML on stdout.
//
// Run with: baml run toml-test-encoder < file.json   (see [scripts] in baml.toml)

function toml_test_encoder() -> null {
    let tmp = baml.json.parse(root.go.string_of(read_stdin())) catch (err) {
        let e: baml.json.ParseError => log_fatal(`Error decoding JSON: ${e.message}`),
    };

    let rm = root.tag.remove(tmp) catch (err) {
        let e: root.GoError => log_fatal(`Error decoding JSON: ${e.msg}`),
    };

    let buf = root.go.new_buffer();
    root.new_encoder(buf).encode(rm) catch (err) {
        let e: root.TomlError => log_fatal(`Error encoding TOML: ${e.error()}`),
    };
    baml.io.print(buf.string());
    null
}
