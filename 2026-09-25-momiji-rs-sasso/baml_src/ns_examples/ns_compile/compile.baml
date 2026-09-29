// Ported from sasso `examples/compile.rs` (namespace `root.examples.compile`).
//
// Minimal embedding example: `cargo run --example compile`.
// PORT: run it with `RUST_MIN_STACK=1073741824 baml run examples.compile.main`.

// PORT: `use sasso::{compile, Options, OutputStyle};` → `root.compile`,
// `root.Options`, `root.OutputStyle`.

function main() -> void {
    // PORT: the Rust raw string `r#"…"#` is spelled with escapes: a BAML
    // backtick string is dedented and trimmed, which would change the source.
    let scss = "\n"
        + "        $brand: #336699;\n"
        + "        .button {\n"
        + "            color: $brand;\n"
        + "            &:hover { color: lighten($brand, 10%); }\n"
        + "        }\n"
        + "    ";

    // PORT: `.expect("compile")` → catch the `Err` and panic with the message
    // (the `Display` form stands in for the `Debug` one).
    let expanded = root.compile(scss, root.Options.default()) catch (e) {
        let e: root.error.Error => root.std.panic(`compile: ${e.to_string()}`)
    };
    baml.io.println("/* expanded */\n" + expanded);

    let compressed = root.compile(scss, root.Options.default().with_style(root.OutputStyle.Compressed)) catch (e) {
        let e: root.error.Error => root.std.panic(`compile: ${e.to_string()}`)
    };
    baml.io.println("/* compressed */\n" + compressed);
}
