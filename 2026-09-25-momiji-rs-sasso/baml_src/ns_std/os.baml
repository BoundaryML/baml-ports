// `std::fs`, `std::env`, `std::io::stdin`, `std::process` and `std::time`
// shims. Filesystem errors surface as `baml.errors.Io` (Rust `io::Error`).

/// `std::env::args()` as Rust sees it: `[program, arg1, ...]`. BAML puts the
/// entry function's name in `argv[1]` both under `baml run <target> -- args`
/// (`[baml-cli, <target>, args...]`) and in a `baml pack`ed executable
/// (`[exe, <target>, args...]`), so that slot is dropped.
function args() -> string[] {
    let argv = baml.sys.argv();
    if (argv.length() == 0) {
        return ["sasso"];
    }
    let exe = argv[0];
    let base = path_file_name(exe) ?? exe;
    let program = if (base == "baml-cli" || base == "baml") {
        "sasso"
    } else {
        exe
    };
    let out = [program];
    if (argv.length() >= 2) {
        extend(out, argv.slice(2, argv.length()));
    }
    out
}

/// `std::env::var(name).ok()`.
function env_var(name: string) -> string? {
    baml.env.get(name) catch (e) {
        _ => null
    }
}

/// `std::env::current_dir()` — the physical working directory (`getcwd`).
function current_dir() -> string throws baml.errors.Io {
    let out = baml.sys.exec("/bin/pwd", ["-P"], null) catch (e) {
        _ => throw baml.errors.Io { message: "current_dir: cannot run pwd" }
    };
    let s = string.from_utf8(out.stdout) catch (e) {
        _ => throw baml.errors.Io { message: "current_dir: non-UTF-8 path" }
    };
    trim_end_matches(s, "\n")
}

/// `std::fs::read_to_string(p)`.
function read_to_string(p: string) -> string throws baml.errors.Io {
    baml.fs.read(p) catch (e) {
        let io: baml.errors.Io => throw io,
        let pe: baml.errors.ParseError => {
            throw baml.errors.Io { message: `stream did not contain valid UTF-8: ${pe.message}` }
        }
    }
}

/// `std::fs::read(p)` — the raw bytes.
function read_bytes(p: string) -> uint8array throws baml.errors.Io {
    let f = baml.fs.open(p, "r") catch (e) {
        let io: baml.errors.Io => throw io,
        _ => throw baml.errors.Io { message: `cannot open ${p}` }
    };
    let bytes = f.bytes();
    let _ = f.close();
    bytes
}

/// `std::fs::write(p, contents)`.
function write_file(p: string, contents: string) -> void throws baml.errors.Io {
    let _ = baml.fs.write(p, contents);
}

/// `std::fs::write(p, bytes)`.
function write_file_bytes(p: string, bytes: uint8array) -> void throws baml.errors.Io {
    let _ = baml.fs.write_bytes(p, bytes);
}

/// `Path::exists()`.
function exists(p: string) -> bool {
    baml.fs.exists(p) catch (e) {
        _ => false
    }
}

/// `Path::is_dir()`.
function is_dir(p: string) -> bool {
    if (!exists(p)) {
        return false;
    }
    let _ = baml.fs.read_dir(p) catch (e) {
        _ => {
            return false;
        }
    };
    true
}

/// `Path::is_file()`.
function is_file(p: string) -> bool {
    exists(p) && !is_dir(p)
}

/// `std::fs::read_dir(p)` — entry names.
function read_dir_names(p: string) -> string[] throws baml.errors.Io {
    baml.fs.read_dir(p).map((e) -> {
        e.name
    })
}

/// `std::fs::create_dir_all(p)`.
function create_dir_all(p: string) -> void throws baml.errors.Io {
    let _ = baml.fs.mkdir(p, baml.fs.MkdirOptions { recursive: true });
}

/// `std::fs::remove_file(p)`.
function remove_file(p: string) -> void throws baml.errors.Io {
    let _ = baml.fs.remove(p);
}

/// `std::fs::canonicalize(p)`.
function canonicalize(p: string) -> string throws baml.errors.Io {
    let out = baml.sys.exec("/bin/realpath", [p], null) catch (e) {
        _ => throw baml.errors.Io { message: `canonicalize: cannot resolve ${p}` }
    };
    if (out.exit_code != 0) {
        throw baml.errors.Io { message: "No such file or directory (os error 2)" };
    }
    let s = string.from_utf8(out.stdout) catch (e) {
        _ => throw baml.errors.Io { message: "canonicalize: non-UTF-8 path" }
    };
    trim_end_matches(s, "\n")
}

/// `metadata(p).modified()` as nanoseconds since the Unix epoch (a bigint);
/// `null` when the file does not exist.
function mtime_nanos(p: string) -> bigint? {
    if (!exists(p)) {
        return null;
    }
    // BSD/macOS stat first, then GNU stat.
    let bsd = baml.sys.exec("stat", ["-f", "%Fm", p], null) catch (e) {
        _ => null
    };
    let text: string? = null;
    if (bsd != null) {
        if (bsd.exit_code == 0) {
            text
                = string.from_utf8(bsd.stdout) catch (e) {
                    _ => null
                };
        }
    }
    if (text == null) {
        let gnu = baml.sys.exec("stat", ["-c", "%.9Y", p], null) catch (e) {
            _ => null
        };
        if (gnu != null) {
            if (gnu.exit_code == 0) {
                text
                    = string.from_utf8(gnu.stdout) catch (e) {
                        _ => null
                    };
            }
        }
    }
    if (text == null) {
        return null;
    }
    let t = trim_end_matches(text, "\n");
    let dot = t.index_of(".");
    let secs_s = if (dot == null) {
        t
    } else {
        t.slice(0, dot)
    };
    let frac_s = if (dot == null) {
        ""
    } else {
        t.slice(dot + 1, t.length())
    };
    frac_s = (frac_s + "000000000").slice(0, 9);
    let secs = baml.Bigint.parse(secs_s) catch (e) {
        _ => 0n
    };
    let frac = baml.Bigint.parse(frac_s) catch (e) {
        _ => 0n
    };
    secs * 1000000000n + frac
}

/// Read all of standard input (`io::stdin().read_to_string(&mut s)`).
function read_stdin() -> string throws baml.errors.Io {
    let f = baml.fs.open("/dev/stdin", "r") catch (e) {
        let io: baml.errors.Io => throw io,
        _ => throw baml.errors.Io { message: "cannot open stdin" }
    };
    f.text() catch (e) {
        let io: baml.errors.Io => throw io,
        let pe: baml.errors.ParseError => {
            throw baml.errors.Io { message: "stream did not contain valid UTF-8" }
        }
    }
}

/// `print!`.
function print(s: string) -> void {
    baml.io.print(s);
}

/// `eprint!`.
function eprint(s: string) -> void {
    baml.io.eprint(s);
}

/// `std::process::exit(code)`.
function exit(code: int) -> never {
    baml.sys.exit(code)
}

/// `Instant::now()`, as nanoseconds on the wall clock.
function now_nanos() -> bigint {
    baml.time.Instant.now().to_timestamp_nanoseconds()
}

/// `std::thread::sleep(Duration::from_millis(ms))`.
function sleep_ms(ms: int) -> void {
    let _ = baml.sys.sleep(baml.time.Duration.from_milliseconds(ms)) catch (e) {
        _ => null
    };
}

/// `std::thread::available_parallelism()`.
function available_parallelism() -> int {
    let out = baml.sys.exec("/usr/sbin/sysctl", ["-n", "hw.logicalcpu"], null) catch (e) {
        _ => null
    };
    if (out != null) {
        if (out.exit_code == 0) {
            let s = string.from_utf8(out.stdout) catch (e) {
                _ => "1"
            };
            return baml.Int.parse(trim_end_matches(s, "\n")) catch (e) {
                _ => 1
            };
        }
    }
    // Linux / other POSIX: `getconf _NPROCESSORS_ONLN`.
    let gc = baml.sys.exec("getconf", ["_NPROCESSORS_ONLN"], null) catch (e) {
        _ => null
    };
    if (gc != null) {
        if (gc.exit_code == 0) {
            let s = string.from_utf8(gc.stdout) catch (e) {
                _ => "1"
            };
            return baml.Int.parse(trim_end_matches(s, "\n")) catch (e) {
                _ => 1
            };
        }
    }
    1
}
