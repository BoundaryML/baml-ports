// Port of cmd/tomlv/main.go (namespace root.cmd).
//
// Command tomlv validates TOML documents and prints each key's type.
//
// Run with: baml run tomlv -- cmd.tomlv --files a.toml --types true
//
// Go's flag package maps to the function's parameters: `baml run` builds a
// CLI from the signature. Positional file arguments become a `files` list.

function tomlv(files: string[], types: bool, time: bool, json: bool) -> null {
    if (files.length() < 1 || files[0] == "-") {
        read("-", read_stdin(), types, time, json);
        return null;
    }

    for (let f in files) {
        let fp = baml.fs.open(f, "r") catch (err) {
            _ => log_fatal(`reading ${root.go.quote(f)}: open ${f}: no such file or directory`),
        };
        let d = fp.bytes() catch (err) {
            _ => log_fatal(`Error in '${f}': read error`),
        };
        let _ = fp.close() catch (err) {
            _ => null
        };
        read(f, d.to_array(), types, time, json);
    }
    null
}

function read(f: string, d: int[], flag_types: bool, flag_time: bool, flag_json: bool) -> null {
    // Read data first so -time doesn't include the time it took to read.
    let start = baml.time.Instant.now();
    let dec = root.new_decoder(root.go.new_bytes_reader(d)).decode<root.Any>(null) catch (err) {
        let perr: root.ParseError => log_fatal(`Error in '${f}': ${perr.error_with_position()}`),
        let e: root.TomlError => log_fatal(`Error in '${f}': ${e.error()}`),
    };
    if (flag_time) {
        let ns = start.elapsed().to_nanoseconds();
        let secs = float.parse(ns.to_string()) catch (e) {
            _ => 0.0
        };
        baml.io.println(root.go.format_float_f6(secs / 1000000000.0));
    }
    if (flag_types) {
        print_types(dec.meta);
    }
    if (flag_json) {
        baml.io.print(baml.json.stringify_pretty(any_to_plain_json(dec.value)) + "\n");
    }
    null
}

// text/tabwriter.NewWriter(os.Stdout, 0, 0, 2, ' ', 0): every line has one
// tab, so the first column is padded to its widest cell plus 2.
function print_types(md: root.MetaData) -> null {
    let firsts: string[] = [];
    let seconds: string[] = [];
    for (let key in md.keys()) {
        firsts.push("    ".repeat(key.len() - 1) + key.to_string());
        seconds.push(md.type(key.parts));
    }
    let width = 0;
    for (let c in firsts) {
        if (c.length() > width) {
            width = c.length();
        }
    }
    let i = 0;
    while (i < firsts.length()) {
        baml.io.println(firsts[i] + " ".repeat(width + 2 - firsts[i].length()) + seconds[i]);
        i += 1;
    }
    null
}
