// Ported from sasso `src/main.rs` (namespace `root`).
//
// `sasso` command-line interface.
//
// A small, dependency-free CLI over the `sasso` library, flag-compatible with
// the dart-sass CLI wherever the two overlap:
//
// ```text
// sasso [options] <input.scss> [<output.css>]     CSS to stdout, or to a file
// sasso [options] <in.scss>:<out.css>...          one output file per input
// sasso [options] <in-dir/>:<out-dir/>            compile a whole tree
// sasso --stdin [options] [<output.css>] < input.scss
// ```
//
// The positional grammar is dart-sass's (`<input> [output]`); several files
// are compiled through `in:out` pairs, in parallel, one worker per physical
// core where the topology is known and one per CPU where it is not
// (`-j/--jobs N` to cap it), with diagnostics still reported in command-line
// order. Exit codes follow dart-sass too: `64` for a usage error, `65` for a
// compile error, `66` when an input cannot be read.

// The library's path rules, compiled into the binary rather than exported:
// `sasso`'s public API is a documented surface and this is not part of it. Both
// relativisations — a diagnostic path in the library, a source-map URL here —
// have to agree about when two spellings name one file, which is #146. The
// binary needs only a subset, hence the `dead_code` allow.
// mod pathstyle → namespace `root.pathstyle`

// Install the scoped bump-arena allocator (perf #5). Inside each `compile`
// scope every allocation is a pointer bump from a per-thread arena that is
// freed wholesale when the scope ends; outside a scope (startup, arg parsing,
// I/O) requests forward to the system allocator. `compile` copies its result
// out to the system allocator before resetting the arena, so values that
// escape a compile never point into it.
function GLOBAL() -> root.arena.ScopedAlloc {
    // PORT: `#[global_allocator]` has no BAML counterpart (the VM owns all
    // memory); the static is kept as a plain value.
    root.arena.ScopedAlloc {  }
}

function USAGE() -> string {
    "sasso — a pure-Rust SCSS to CSS compiler\n\nUSAGE:\n    sasso [options] <input.scss> [<output.css>]     CSS to stdout, or to a file\n    sasso [options] <in.scss>:<out.css>...          one output file per input\n    sasso [options] <in-dir/>:<out-dir/>            compile a whole tree\n    sasso --stdin [options] [<output.css>] < input.scss\n\nINPUT AND OUTPUT:\n    -s, --style <expanded|compressed>   output style (default: expanded)\n    -I, --load-path <dir>               add an @import/@use search path (repeatable)\n    -o, --output <file>                 write CSS to <file> (same as a second\n                                        positional argument)\n        --stdin                         read SCSS from standard input\n        --indented                      parse the indented .sass syntax\n        --[no-]charset                  emit @charset/BOM for non-ASCII CSS\n                                        (default: on)\n        --[no-]error-css                on a compile error, write a stylesheet\n                                        describing it (default: on when\n                                        compiling to a file)\n\nSOURCE MAPS:\n        --[no-]source-map               generate source maps (default: on when\n                                        compiling to a file, off for stdout)\n        --source-map-urls <relative|absolute>\n                                        how the map references its sources\n                                        (default: relative)\n        --[no-]embed-sources            embed the source text in the map's\n                                        sourcesContent\n        --[no-]embed-source-map         inline the map into the CSS as a\n                                        data: URI instead of a .map file\n\nWARNINGS:\n    -q, --[no-]quiet                    don't print warnings\n        --[no-]quiet-deps               don't print compiler warnings from\n                                        dependencies (stylesheets reached\n                                        through load paths)\n        --silence-deprecation <IDS>     don't print these deprecations\n                                        (comma-separated; repeatable), e.g.\n                                        import,global-builtin\n\nOTHER:\n    -j, --jobs <N>                      compile at most N files at once\n                                        (default: one per core, or per CPU\n                                        where the core count is unknown)\n        --update                        skip writing an output that is already\n                                        newer than its input and every\n                                        stylesheet that input loads\n    -w, --watch                         recompile when a stylesheet changes\n        --[no-]poll                     accepted for dart-sass compatibility\n                                        (no-op: sasso always polls, because a\n                                        native watcher would be a dependency)\n        --[no-]stop-on-error            don't start more files once one fails\n    -c, --[no-]color                    accepted for dart-sass compatibility\n                                        (no-op: sasso never colors output)\n        --[no-]unicode                  Unicode box glyphs in diagnostics\n                                        (default: on)\n        --loop <N>                      recompile in-process N times and report\n                                        throughput (stdout inputs only)\n        --no-css                        compile but discard the CSS (timing or\n                                        lint runs)\n        --version                       print version and exit\n    -h, --help                          print this help and exit\n    --                                  end of options: what follows are inputs\n                                        and outputs, even if they start with -\n"
}

/// Exit codes, as dart-sass (and BSD `sysexits.h`) define them.
function EXIT_USAGE() -> int {
    64
}

function EXIT_COMPILE() -> int {
    65
}

function EXIT_IO() -> int {
    66
}

class Cli {
    /// Positional arguments in order, a `-` included; resolved into `entry` /
    /// `output` after parsing (dart's `<input> [output]`).
    positionals: string[],
    /// dart-style `source:destination` pairs (files or directories); a `-`
    /// source is standard input.
    pairs: root.std.Tuple2<string, string>[],
    /// The final value of `--[no-]stdin`.
    stdin_flag: bool,
    /// The single input of stdout / `-o` mode, once positionals are resolved.
    entry: Entry?,
    style: OutputStyle,
    load_paths: string[],
    /// `--silence-deprecation` ids. Empty means every deprecation prints.
    silenced: string[],
    /// Force the indented `.sass` syntax (otherwise inferred from the input
    /// path's extension; `--stdin` defaults to SCSS).
    indented: bool,
    /// Don't print warnings (dart-sass `--quiet`).
    quiet: bool,
    /// Don't print compiler (deprecation) warnings from dependencies —
    /// stylesheets reached through a load path (dart-sass `--quiet-deps`).
    quiet_deps: bool,
    update: bool,
    /// Keep running and recompile when anything the entry loads changes
    /// (dart-sass `-w`/`--watch`).
    watch: bool,
    /// dart's `--[no-]poll`, which chooses between a native watcher and
    /// repeated stat calls. We only have the second, so the value is recorded
    /// for its usage rule ("may not be passed without --watch") and then
    /// ignored — see `watch.rs` for why there is no other option here.
    poll: bool?,
    /// Compile but discard the CSS (timing-only runs).
    no_css: bool,
    /// Recompile the input in-process this many times and report throughput.
    loop_n: int?,
    /// Render diagnostics with the ASCII glyph set (dart-sass `--no-unicode`).
    no_unicode: bool,
    /// Write the compiled CSS to this file instead of stdout (`-o`). Requires a
    /// single input.
    output: string?,
    /// `--[no-]source-map`; `None` = dart's default (on for file output, off
    /// for stdout).
    source_map: bool?,
    /// Embed each source's full text in the map's `sourcesContent`.
    embed_sources: bool,
    /// Inline the map into the CSS as a `data:` URI instead of a sidecar.
    embed_source_map: bool,
    /// How the map's `sources[]` reference the inputs (`--source-map-urls`);
    /// `None` when not given (dart's default, `relative`).
    source_map_urls: SourceMapUrls?,
    /// `--[no-]error-css`; `None` = dart's default (on for file output).
    error_css: bool?,
    /// Don't start compiling more files once one has failed.
    stop_on_error: bool,
    /// Emit `@charset`/BOM for non-ASCII output (dart-sass `--charset`).
    charset: bool,
    /// Worker-thread cap (`-j`); `None` = `default_jobs` — one per physical
    /// core where the topology is known, one per CPU where it is not.
    jobs: int?,
}

/// The single input of stdout / `-o` mode.
interface Entry {}

/// `--stdin`, or a positional `-`.
class Entry_Stdin {
    implements Entry {}
}

class Entry_File {
    _0: string,
    implements Entry {}
}

/// How the source map's `sources[]` entries reference the input files.
enum SourceMapUrls {
    /// Path relative to the `.map` file's directory (dart-sass default).
    Relative,
    /// Absolute `file://` URL.
    Absolute,
}

/// How many files to compile at once when `-j` is not given.
///
/// `available_parallelism` counts SMT threads. A compile is pure computation,
/// so two hyperthreads on one core contend for the same execution units rather
/// than overlapping each other's stalls — past the core count, more workers is
/// slower. Measured on Linux / x86_64 with 8 cores and 16 threads, over 138
/// Lichess stylesheets: 208 ms at `-j 8` against 235 ms at `-j 16`.
///
/// Linux publishes the topology in `/proc/cpuinfo`, which is a read rather
/// than a process spawn. Apple silicon has no SMT, so the logical count is
/// already right there; other platforms keep it rather than grow a dependency
/// or an `unsafe` sysctl call for a number that is, at worst, the old default.
function default_jobs() -> int {
    // PORT: `available_parallelism().map(|n| n.get()).unwrap_or(1)` — the
    // shim already answers 1 when the count is unknown.
    let logical = root.std.available_parallelism();
    // PORT: `if !cfg!(target_os = "linux") { return logical; }` — BAML cannot
    // name the target OS. Only Linux has `/proc/cpuinfo`: elsewhere the read
    // below fails, and `jobs_from(logical, None)` is `logical`, the same answer.
    let cpuinfo = root.std.read_to_string("/proc/cpuinfo") catch (e) {
        let _e: baml.errors.Io => null
    };
    jobs_from(logical, cpuinfo)
}

/// The decision itself, separated from the two host facts it reads so a test
/// can hand it a machine this one is not.
function jobs_from(logical: int, cpuinfo: string?) -> int {
    // Never more than the kernel offers this process: a cgroup or `taskset`
    // cap shows up in `available_parallelism`, not in `/proc/cpuinfo`.
    //
    // Both kinds of cap, which is worth stating because it is easy to assume
    // otherwise — measured in one process on a 16-thread host, 2026-09-17:
    //
    //     plain host        mask 0-15      no quota            answers 16
    //     --cpus=2          mask 0-15      cpu.max 200000 …    answers 2
    //     --cpuset-cpus=…   mask 0-1,8-9   no quota            answers 4
    //
    // The middle row is the one that matters: the mask is the whole machine,
    // so the 2 can only have come from the quota. It is not an accident of
    // this machine either — `std::sys::thread::available_parallelism` reads
    // `cgroups::quota()` and returns `count.min(quota)`, and that module's own
    // header lists what it skips ("cgroup v2 in non-standard mountpoints"),
    // which is the same line `_jobs.mjs` draws. Nothing here needs to read
    // either file. The npm CLI is not so lucky: `availableParallelism()` has
    // only accounted for the quota since Node 22, and below 18.14 there is no
    // such API at all, so `_jobs.mjs` reads the mask and the quota itself.
    //
    // This is the host's core count capped by what the process may use, and
    // deliberately NOT the cores inside the mask, which measures much worse:
    // SMT only stops paying once enough cores are in play. Same corpus, best
    // of five, `taskset` masks of whole cores:
    //
    //     cores allowed   1     2     4     6     7     8
    //     SMT is worth  +55%  +50%  +33%   -2%   -6%  -11%
    //
    // Counting cores within the mask would pick 2 where 4 is 50% faster, and
    // 4 where 8 is 33% faster.
    let physical = if (cpuinfo != null) {
        physical_cores(cpuinfo)
    } else {
        null
    };
    if (physical != null) {
        root.std.iclamp(physical, 1, logical)
    } else {
        logical
    }
}

/// Physical cores in `/proc/cpuinfo` text, or `None` when it reports no
/// topology — containers and VMs often do not, and a number derived from
/// nothing is worse than the kernel's own count.
///
/// A core is a `(physical id, core id)` pair: `core id` alone repeats across
/// sockets, so deduplicating on it halves a dual-socket machine.
function physical_cores(cpuinfo: string) -> int? {
    // PORT: `BTreeSet<(String, String)>` → a set keyed `package + "\n" + core`
    // (a line cannot hold a newline); only its size is read.
    let cores: map<string, bool> = {};
    // Buffered per record rather than inserted on sight, for two reasons: a
    // file may name the socket for some processors and not others, and nothing
    // promises `physical id` is printed before `core id`. Either way, inserting
    // early files the core under a socket the kernel never gave it.
    let package: string? = null;
    let core: string? = null;
    // PORT: the closure's `&mut package, &mut core` parameters are always
    // these two locals, so it assigns them as captures instead.
    let end_of_record = () -> void {
        // `core.take()`
        let id = core;
        core = null;
        if (id != null) {
            // `package.take().unwrap_or("")`
            let pkg = package;
            package = null;
            let _ = root.std.set_insert(cores, (pkg ?? "") + "\n" + id);
        }
        package = null;
    };
    for (let line in cpuinfo.lines()) {
        let kv = root.std.split_once(line, ":");
        if (kv == null) {
            continue;
        }
        let key = kv._0;
        let value = kv._1;
        match (root.std.trim(key)) {
            "processor" => end_of_record(),
            "physical id" => {
                // Seeing a field this record already has means the previous
                // record ended, whether or not a `processor` line said so.
                if (package != null) {
                    end_of_record();
                }
                package = root.std.trim(value);
            },
            "core id" => {
                if (core != null) {
                    end_of_record();
                }
                core = root.std.trim(value);
            },
            _ => {},
        }
    }
    end_of_record();
    if (cores.length() != 0) {
        cores.length()
    } else {
        null
    }
}

/// Local wall-clock time for `--update`'s one-line report, with no
/// dependencies and no `unsafe`. Self-contained on purpose — see its module
/// docs for why it reads the tz database rather than calling libc.
// mod localtime → namespace `root.localtime`

/// `--watch` with no file-watching dependency: a poll whose interval pays for
/// itself, and the rule that turns a burst of saves into two compiles. See
/// its module docs for why polling is the only option here and what it costs.
// mod watch → namespace `root.watch`

function main() -> int {
    // Touch stdout/stderr once before any compile scope: std lazily heap-
    // allocates their lock (a boxed pthread_mutex_t on macOS) on first use,
    // and if that first use happened inside an arena scope (e.g. a deprecation
    // warning mid-compile) the allocation would be swept by the scope reset,
    // leaving the static stdio locks dangling for every later print.
    // PORT: nothing to touch — BAML's stdio has no lazily allocated lock and
    // there is no arena to sweep it.
    let argv = root.std.args();
    let args: string[] = argv.slice(1, argv.length());
    // PORT: the `Err(msg)` arm is the `catch`; the `ExitCode` `main` returns is
    // handed to `root.std.exit` (a returned value would be printed, exit 0).
    let action = parse_args(args) catch (e) {
        let msg: root.std.StrError => {
            baml.io.eprintln(`error: ${msg.message}\n`);
            baml.io.eprint(USAGE());
            root.std.exit(EXIT_USAGE())
        }
    };
    let code = match (action) {
        let run_action: Action_Run => run(run_action._0),
        Action_Help {} => {
            baml.io.print(USAGE());
            0
        },
        Action_Version {} => {
            baml.io.println(`sasso ${VERSION()}`);
            0
        },
        _ => root.std.unreachable(),
    };
    root.std.exit(code)
}

interface Action {}

class Action_Run {
    _0: Cli,
    implements Action {}
}

class Action_Help {
    implements Action {}
}

class Action_Version {
    implements Action {}
}

/// Deprecation ids `--silence-deprecation` accepts.
///
/// The full `Deprecation` enum of dart-sass 1.104.1, in its own declaration
/// order. Taken from the enum itself, not from a guess: an earlier version of
/// this list was assembled by probing candidate names one at a time, which
/// silently missed seven ids — everything dart added from 1.88.0 on, including
/// `if-function`, which sasso emits. The list ships in the npm package as
/// `sass/types/deprecations.d.ts`; that file omits the future-only ids, so the
/// enum in `sass.dart.js` is the authority the CLI actually uses.
///
/// Most name deprecations sasso does not emit; accepting them anyway is the
/// point, because a build script written for `sass` must not fail here just
/// because we have nothing to silence. `deprecation.rs` says which ones
/// actually reach a warning today, and a test there holds this list a superset
/// of those.
function DEPRECATION_IDS() -> string[] {
    [
        "call-string",
        "elseif",
        "moz-document",
        "relative-canonical",
        "new-global",
        "color-module-compat",
        "slash-div",
        "bogus-combinators",
        "strict-unary",
        "function-units",
        "duplicate-var-flags",
        "null-alpha",
        "abs-percent",
        "fs-importer-cwd",
        "css-function-mixin",
        "mixed-decls",
        "feature-exists",
        "color-4-api",
        "color-functions",
        "legacy-js-api",
        "import",
        "global-builtin",
        "type-function",
        "compile-string-relative-url",
        "misplaced-rest",
        "with-private",
        "if-function",
        "function-name",
        "adjacent-compounds",
        "user-authored",
        "calc-interp",
    ]
}

/// Split and validate one `--silence-deprecation` value. dart takes a
/// comma-separated list, accepts the flag more than once, and rejects an
/// unknown id with exit 64 — `Invalid deprecation "nope".` — rather than
/// ignoring it, so a typo is caught instead of silently keeping a warning.
function parse_silenced(value: string, into: string[]) -> void {
    if (value == "") {
        root.std.err_str("--silence-deprecation requires a value");
    }
    for (let id in value.split(",")) {
        let id = root.std.trim(id);
        if (!DEPRECATION_IDS().includes(id)) {
            root.std.err_str(`Invalid deprecation "${id}".`);
        }
        if (
            !into.some((k) -> {
                k == id
            })
        ) {
            into.push(id);
        }
    }
}

function parse_args(args: string[]) -> Action {
    let cli = Cli {
        positionals: [],
        pairs: [],
        stdin_flag: false,
        entry: null,
        style: OutputStyle.Expanded,
        load_paths: [],
        silenced: [],
        indented: false,
        quiet: false,
        quiet_deps: false,
        update: false,
        watch: false,
        poll: null,
        no_css: false,
        loop_n: null,
        no_unicode: false,
        output: null,
        source_map: null,
        embed_sources: false,
        embed_source_map: false,
        source_map_urls: null,
        error_css: null,
        stop_on_error: false,
        charset: true,
        jobs: null,
    };
    let i = 0;
    // After `--` (end of options) every argument is an operand, so an input
    // or output whose name starts with `-` can be named.
    let only_operands = false;
    while (i < args.length()) {
        let a = args[i];
        if (only_operands) {
            push_operand(cli, a);
            i += 1;
            continue;
        }
        match (a) {
            "--" => {
                only_operands = true;
            },
            "-h" | "--help" => {
                return Action_Help {  };
            },
            "--version" => {
                return Action_Version {  };
            },
            "--stdin" => {
                cli.stdin_flag = true;
            },
            "--no-stdin" => {
                cli.stdin_flag = false;
            },
            "--indented" => {
                cli.indented = true;
            },
            "--no-indented" => {
                cli.indented = false;
            },
            "--unicode" => {
                cli.no_unicode = false;
            },
            "--no-unicode" => {
                cli.no_unicode = true;
            },
            "--source-map" => {
                cli.source_map = true;
            },
            "--no-source-map" => {
                cli.source_map = false;
            },
            "--embed-sources" => {
                cli.embed_sources = true;
            },
            "--no-embed-sources" => {
                cli.embed_sources = false;
            },
            "--embed-source-map" => {
                cli.embed_source_map = true;
            },
            "--no-embed-source-map" => {
                cli.embed_source_map = false;
            },
            "--error-css" => {
                cli.error_css = true;
            },
            "--no-error-css" => {
                cli.error_css = false;
            },
            "--charset" => {
                cli.charset = true;
            },
            "--no-charset" => {
                cli.charset = false;
            },
            "-q" | "--quiet" => {
                cli.quiet = true;
            },
            "--no-quiet" => {
                cli.quiet = false;
            },
            "--update" => {
                cli.update = true;
            },
            "-w" | "--watch" => {
                cli.watch = true;
            },
            "--poll" => {
                cli.poll = true;
            },
            "--no-poll" => {
                cli.poll = false;
            },
            "--quiet-deps" => {
                cli.quiet_deps = true;
            },
            "--no-quiet-deps" => {
                cli.quiet_deps = false;
            },
            "--stop-on-error" => {
                cli.stop_on_error = true;
            },
            "--no-stop-on-error" => {
                cli.stop_on_error = false;
            },
            // sasso never emits ANSI colors; accept dart's flags so a build
            // script written for `sass` runs unchanged.
            "-c" | "--color" | "--no-color" => {},
            "--no-css" => {
                cli.no_css = true;
            },
            "-o" | "--output" => {
                i += 1;
                let v = args.at(i) ?? root.std.err_str("--output requires a value");
                cli.output = v;
            },
            "--source-map-urls" => {
                i += 1;
                let v = args.at(i) ?? root.std.err_str("--source-map-urls requires a value");
                cli.source_map_urls = parse_source_map_urls(v);
            },
            "--loop" => {
                i += 1;
                let v = args.at(i) ?? root.std.err_str("--loop requires a value");
                cli.loop_n = parse_loop(v);
            },
            "-j" | "--jobs" => {
                i += 1;
                let v = args.at(i) ?? root.std.err_str("--jobs requires a value");
                cli.jobs = parse_jobs(v);
            },
            "-s" | "--style" => {
                i += 1;
                let v = args.at(i) ?? root.std.err_str("--style requires a value");
                cli.style = parse_style(v);
            },
            "--silence-deprecation" => {
                i += 1;
                let v = args.at(i) ?? root.std.err_str("--silence-deprecation requires a value");
                parse_silenced(v, cli.silenced);
            },
            "-I" | "--load-path" => {
                i += 1;
                let v = args.at(i) ?? root.std.err_str("--load-path requires a value");
                cli.load_paths.push(v);
            },
            let other => {
                if let v: string = root.std.strip_prefix(other, "--silence-deprecation=") {
                    parse_silenced(v, cli.silenced);
                } else if let v: string = root.std.strip_prefix(other, "--style=") {
                    cli.style = parse_style(v);
                } else if let v: string = root.std.strip_prefix(other, "--load-path=") {
                    cli.load_paths.push(v);
                } else if let v: string = root.std.strip_prefix(other, "--loop=") {
                    cli.loop_n = parse_loop(v);
                } else if let v: string = root.std.strip_prefix(other, "--jobs=") {
                    cli.jobs = parse_jobs(v);
                } else if let v: string = root.std.strip_prefix(other, "--output=") {
                    cli.output = v;
                } else if let v: string = root.std.strip_prefix(other, "--source-map-urls=") {
                    cli.source_map_urls = parse_source_map_urls(v);
                } else if (other.starts_with("-") && other != "-" && !other.starts_with("-:")) {
                    root.std.err_str(`unknown option ${other}`);
                } else {
                    push_operand(cli, other);
                }
            },
        }
        i += 1;
    }
    // The same combinations dart-sass rejects, with its wording.
    if (cli.embed_source_map && cli.source_map == false) {
        root.std.err_str("--embed-source-map isn't allowed with --no-source-map.");
    }
    if (cli.embed_sources && cli.source_map == false) {
        root.std.err_str("--embed-sources isn't allowed with --no-source-map.");
    }
    if (cli.source_map_urls != null && cli.source_map == false) {
        root.std.err_str("--source-map-urls isn't allowed with --no-source-map.");
    }
    // dart: `--update is not allowed with --stdin.`, exit 64. Standard input
    // has no mtime to compare, so there is no honest answer to "is the output
    // newer than its input" — and the silent one is the dangerous one. An
    // earlier version of this let the check fall through to the dependency
    // loop, which for a stdin unit with no imports is empty and reports
    // FRESH, leaving the previous run's CSS on disk.
    if (cli.update && cli.stdin_flag) {
        root.std.err_str("--update is not allowed with --stdin.");
    }
    // The same rule for `--watch`, and for the same reason: standard input is
    // read once and cannot change, so there is nothing to watch. Measured
    // against dart-sass 1.104.1 on 2026-09-20, exit 64 and this wording.
    if (cli.watch && cli.stdin_flag) {
        root.std.err_str("--watch is not allowed with --stdin.");
    }
    // `--poll` chooses between a native watcher and repeated stats, so it
    // means nothing on its own. dart refuses it, exit 64, and we accept it
    // ONLY to refuse it the same way — sasso always polls (see `watch.rs`),
    // so neither spelling changes anything when `--watch` is there.
    if (cli.poll != null && !cli.watch) {
        root.std.err_str("--poll may not be passed without --watch.");
    }
    if (cli.pairs.length() != 0) {
        if (cli.positionals.length() != 0) {
            root.std.err_str("Positional and \":\" arguments may not both be used.");
        }
        if (cli.stdin_flag) {
            root.std.err_str("--stdin may not be used with \":\" arguments.");
        }
        if (cli.output != null) {
            root.std.err_str("--output may not be used with \":\" arguments.");
        }
        if (cli.loop_n != null) {
            root.std.err_str("--loop compiles to stdout only (no \":\" arguments or --output).");
        }
        // dart: each source appears once (`-` included) …
        // PORT: `HashSet<&Path>` hashes a path by its components, so the key
        // is the path rebuilt from them (`a//b` and `a/b` are one entry).
        let seen: map<string, bool> = {};
        for (let pair in cli.pairs) {
            let src = pair._0;
            if (
                !root.std.set_insert(
                    seen,
                    root.std.path_from_components(root.std.path_components(src)),
                )
            ) {
                root.std.err_str(`Duplicate source ${root.std.debug_str(src)}.`);
            }
        }
        // … and it keeps sources in a path-keyed map, so two spellings of one
        // file (`a.scss` and `./a.scss`, `dir/../a.scss`) coalesce into a
        // single compile whose destination is the later one.
        let cwd = root.std.current_dir() catch (e) {
            let _e: baml.errors.Io => ""
        };
        let keys: string[] = [];
        let kept: root.std.Tuple2<string, string>[] = [];
        // PORT: `std::mem::take(&mut cli.pairs)`.
        let taken = cli.pairs;
        cli.pairs = [];
        for (let pair in taken) {
            let src = pair._0;
            let dest = pair._1;
            let key = if (root.std.path_eq(src, "-")) {
                src
            } else {
                normalize_path(root.std.path_join(cwd, src))
            };
            match (
                keys.find_index((k) -> {
                    root.std.path_eq(k, key)
                })
            ) {
                let i: int => {
                    kept[i]._1 = dest;
                },
                _ => {
                    keys.push(key);
                    kept.push(root.std.Tuple2 { _0: src, _1: dest });
                },
            }
        }
        cli.pairs = kept;
    } else {
        // dart's positional grammar: `<input> [output]`, or just `[output]`
        // with `--stdin`. An INPUT of `-` is standard input, whatever the
        // final `--[no-]stdin` value; a `-` in the output position is a file
        // called `-`, as in dart.
        let max = if (cli.stdin_flag) {
            1
        } else {
            2
        };
        if (cli.positionals.length() > max) {
            root.std.err_str(
                if (cli.stdin_flag) {
                    "Only one argument is allowed with --stdin."
                } else {
                    "Only two positional args may be passed."
                },
            );
        }
        // PORT: the `positionals` iterator as an index cursor.
        let positionals = cli.positionals;
        let next = 0;
        let entry: Entry? = if (cli.stdin_flag) {
            Entry_Stdin {  }
        } else {
            let p = positionals.at(next);
            next += 1;
            if (p != null) {
                if (p == "-") {
                    Entry_Stdin {  }
                } else {
                    Entry_File { _0: p }
                }
            } else {
                null
            }
        };
        cli.entry = entry;
        if let out: string = positionals.at(next) {
            next += 1;
            if (cli.output != null) {
                root.std.err_str("--output requires a single input");
            }
            cli.output = out;
        }
        if (cli.output != null && cli.loop_n != null) {
            root.std.err_str("--loop compiles to stdout only (no \":\" arguments or --output).");
        }
    }
    // A bare directory positional compiles in place (see `run`): file output,
    // never stdout.
    let entry_is_dir = match (cli.entry) {
        Entry_File { _0: let p } if root.std.is_dir(p) => true,
        _ => false,
    };
    if (cli.loop_n != null && entry_is_dir) {
        root.std.err_str(
            "--loop compiles to stdout only (no directories, \":\" arguments or --output).",
        );
    }
    if (cli.loop_n != null && (cli.source_map == true || cli.embed_source_map || cli.embed_sources)) {
        root.std.err_str(
            "--loop does not generate source maps (drop --source-map, --embed-source-map and --embed-sources).",
        );
    }
    // dart has TWO usage errors for `--update`, not one:
    // `--update is not allowed when printing to stdout.`, also exit 64. A run
    // with no destination has nothing whose mtime could be compared, so the
    // flag would silently do nothing — dart refuses rather than pretend.
    // Measured 2026-09-19: `sass --update t.scss` exits 64, and every shape
    // that HAS a destination is accepted (`t.scss out.css`, `t.scss:out.css`,
    // several pairs, even `t.scss:-`, a file named `-`).
    //
    // `to_stdout` is the same condition this CLI already computes for source
    // maps, and it is the right one: `-o` and a bare directory positional are
    // destinations too. Neither exists in dart, so neither has a dart answer
    // to copy — but both write files, which is what the rule is about.
    let to_stdout = cli.pairs.length() == 0 && cli.output == null && !entry_is_dir;
    if (cli.update && to_stdout) {
        root.std.err_str("--update is not allowed when printing to stdout.");
    }
    // And again for `--watch`: a watch with nowhere to write would recompile
    // on every save and print the whole stylesheet to the terminal each time.
    // dart refuses it with the same wording, exit 64 (measured 2026-09-20).
    if (cli.watch && to_stdout) {
        root.std.err_str("--watch is not allowed when printing to stdout.");
    }
    if (to_stdout) {
        // A stdout map can only be embedded, and its sources are always
        // absolute `file://` URLs.
        if (cli.source_map_urls == SourceMapUrls.Relative) {
            root.std.err_str("--source-map-urls=relative isn't allowed when printing to stdout.");
        }
        if (!cli.embed_source_map) {
            if (cli.source_map == true) {
                root.std.err_str(
                    "When printing to stdout, --source-map requires --embed-source-map.",
                );
            }
            if (cli.embed_sources) {
                root.std.err_str(
                    "When printing to stdout, --embed-sources requires --embed-source-map.",
                );
            }
            if (cli.source_map_urls != null) {
                root.std.err_str(
                    "When printing to stdout, --source-map-urls requires --embed-source-map.",
                );
            }
        }
    }
    Action_Run { _0: cli }
}

/// Record an operand: a `source:destination` pair, or a positional argument.
function push_operand(cli: Cli, arg: string) -> void {
    let pair = split_pair(arg);
    if (pair != null) {
        cli.pairs.push(pair);
    } else {
        cli.positionals.push(arg);
    }
}

/// Is `s`'s colon at index 1 a Windows drive letter's, rather than the
/// separator of a `source:destination` pair?
///
/// Asked on EVERY platform, because dart asks it on every platform. Measured
/// against dart-sass 1.104.1 on macOS, where sasso gated the same rule behind
/// `cfg!(windows)` and so answered differently for the whole family (#172):
///
/// ```text
///   operand                  dart 1.104.1              sasso before
///   C:\in.scss               compiles to stdout        Error reading C:
///   C:\in.scss:C:\out.css    writes C:\out.css         may only contain one ":"
///   in.scss:C:\out.css       writes C:\out.css         may only contain one ":"
///   c:\in.scss:c:\out.css    writes c:\out.css         may only contain one ":"
///   a:b                      Error reading a:b         compiled a/ into b/
///   a:b:c                    Error reading a:b         may only contain one ":"
/// ```
///
/// The cost of parity is the `a:b` row: a POSIX directory named with one
/// letter can no longer be the source of a pair, because `a:` is read as a
/// drive. dart pays that cost too, and sasso already paid it on Windows — the
/// gate made one platform disagree with both.
///
/// A digit is not a drive letter: `1:\in.scss:out.css` splits at index 1 and
/// is the "one `:`" error in both.
function is_drive_colon(s: string, idx: int) -> bool {
    // PORT: `s.as_bytes()` read as chars — the first byte is an ASCII letter
    // exactly when the first char is, and then byte 1 is char 1.
    idx == 1 && root.std.is_ascii_alphabetic(root.std.first_char(s)) && s.at(1) == ":"
}

/// Split a dart-style `source:destination` argument at its separating colon,
/// or return `Ok(None)` for a plain path. The colon of a leading drive letter
/// (`C:\in.scss`) is part of the path, not a separator — see
/// [`is_drive_colon`].
function split_pair(arg: string) -> root.std.Tuple2<string, string>? {
    let from = 0;
    while let off: int = arg.slice(from, arg.length()).index_of(":") {
        let idx = from + off;
        if (is_drive_colon(arg, idx)) {
            from = idx + 1;
            continue;
        }
        let src = arg.slice(0, idx);
        let dest = arg.slice(idx + 1, arg.length());
        if (src == "" || dest == "") {
            root.std.err_str(`expected <source>:<destination>, got ${root.std.debug_str(arg)}`);
        }
        // dart: exactly one separator; the destination may only carry a drive
        // colon of its own (`C:\out.css`).
        let extra = if (is_drive_colon(dest, 1)) {
            dest.slice(2, dest.length()).includes(":")
        } else {
            dest.includes(":")
        };
        if (extra) {
            // `{arg}` in quotes, not `{arg:?}`: Debug escapes a backslash,
            // so the message for the operand this rule EXISTS for came out
            // as `"C:\\in.scss:out.css:x"`. dart and `cli.mjs` both print
            // the operand as the user typed it.
            root.std.err_str(`"${arg}" may only contain one ":".`);
        }
        return root.std.Tuple2 { _0: src, _1: dest };
    }
    null
}

/// Report a usage error the way `parse_args` failures are reported.
function usage_error(msg: string) -> int {
    baml.io.eprintln(`error: ${msg}\n`);
    baml.io.eprint(USAGE());
    EXIT_USAGE()
}

function parse_source_map_urls(s: string) -> SourceMapUrls {
    match (s) {
        "relative" => SourceMapUrls.Relative,
        "absolute" => SourceMapUrls.Absolute,
        let other => {
            root.std.err_str(
                `unknown --source-map-urls ${root.std.debug_str(other)} (expected relative or absolute)`,
            )
        },
    }
}

function parse_loop(s: string) -> int {
    // PORT: `s.parse::<u32>()` spelled out: Rust's grammar is an optional `+`
    // and then ASCII digits only, at most `u32::MAX` (`baml.Int.parse` is
    // looser about both).
    let digits = root.std.strip_prefix(s, "+") ?? s;
    let parsed: bigint? = null;
    if (
        digits != ""
            && root.std.all_chars(digits, (c) -> {
                root.std.is_ascii_digit(c)
            })
    ) {
        parsed
            = baml.Bigint.parse(digits) catch (e) {
                _ => null
            };
    }
    match (parsed) {
        let n: bigint if n >= 1n && n <= 4294967295n => root.std.int_of(n),
        _ => root.std.err_str(`--loop expects a positive integer (got ${root.std.debug_str(s)})`),
    }
}

function parse_jobs(s: string) -> int {
    // PORT: `s.parse::<usize>()` spelled out: Rust's grammar is an optional
    // `+` and then ASCII digits only, at most `u64::MAX` (`baml.Int.parse` is
    // looser about both). A count past BAML's 63-bit `int` saturates — as a
    // worker cap it means the same as any number above the unit count.
    let digits = root.std.strip_prefix(s, "+") ?? s;
    let parsed: bigint? = null;
    if (
        digits != ""
            && root.std.all_chars(digits, (c) -> {
                root.std.is_ascii_digit(c)
            })
    ) {
        parsed
            = baml.Bigint.parse(digits) catch (e) {
                _ => null
            };
    }
    match (parsed) {
        let n: bigint if n >= 1n && n <= 18446744073709551615n => {
            if (n > root.std.bigint_of(root.std.INT_MAX())) {
                root.std.INT_MAX()
            } else {
                root.std.int_of(n)
            }
        },
        _ => root.std.err_str(`--jobs expects a positive integer (got ${root.std.debug_str(s)})`),
    }
}

function parse_style(s: string) -> OutputStyle {
    match (s) {
        "expanded" => OutputStyle.Expanded,
        "compressed" => OutputStyle.Compressed,
        let other => {
            root.std.err_str(
                `unknown style ${root.std.debug_str(other)} (expected expanded or compressed)`,
            )
        },
    }
}

// ---------------------------------------------------------------------------
// Compile units
// ---------------------------------------------------------------------------
/// Where a unit's source text comes from.
interface Source {}

/// Already read (standard input).
class Source_Text {
    _0: string,
    implements Source {}
}

/// Read from this file when the unit is compiled.
class Source_File {
    _0: string,
    implements Source {}
}

/// Standard input was not valid UTF-8: a compile-class failure that gets
/// the same reporting (error stylesheet, stale-output cleanup) as a file's.
class Source_InvalidUtf8 {
    implements Source {}
}

/// Where a unit's CSS goes.
interface Target {}

class Target_Stdout {
    implements Target {}
}

class Target_File {
    _0: string,
    implements Target {}
}

/// One stylesheet to compile. `url` is the path as it appears in diagnostics
/// (`-` for stdin, matching dart-sass).
class Unit {
    source: Source,
    url: string,
    syntax: Syntax,
    target: Target,
    /// The entry's own file, when it has one. The importer never sees it — the
    /// entry is read directly — so `--update` stats it separately from the
    /// files the compile pulled in. A stdin unit has no path, and rather than
    /// invent an answer for it `--update` with `--stdin` is refused in
    /// `parse_args`, as dart refuses it.
    function source_path(self) -> string? {
        match (self.source) {
            Source_File { _0: let p } => p,
            Source_Text {} | Source_InvalidUtf8 {} => null,
            _ => root.std.unreachable(),
        }
    }
}

/// Settings shared by every unit (read-only across worker threads).
class Shared {
    /// `-I` directories. Each unit builds its own `FsImporter` from them: the
    /// importer's dependency record (`--quiet-deps`) is per compilation, as in
    /// dart — the same file can be a dependency of one entry and not another.
    load_paths: string[],
    style: OutputStyle,
    unicode: bool,
    charset: bool,
    quiet: bool,
    quiet_deps: bool,
    update: bool,
    /// `--silence-deprecation` ids, applied inside the compiler beside
    /// `--quiet-deps` rather than in the warn handler. Dropping the warning
    /// further out still lets it reach the per-id cap, so the run ends
    /// reporting "N repetitive deprecation warnings omitted" for exactly the
    /// ones the caller asked not to hear about; dart prints nothing there.
    silenced: string[],
    no_css: bool,
    embed_sources: bool,
    embed_source_map: bool,
    source_map_urls: SourceMapUrls,
    /// Generate a source map for file targets (dart default: yes).
    file_source_map: bool,
    /// `--watch` is running. Only the narration cares: the flag's behaviour
    /// lives in `run_watch`, but the line dart prints per written file is
    /// emitted from the unit that wrote it, like `--update`'s.
    watch: bool,
    /// This compile is the speculative one at the head of a burst (see
    /// `watch.rs`). The likeliest cause of a FAILURE here is a file still
    /// being written, so it reports nothing and leaves the output exactly as
    /// it was — no error stylesheet, no removal — and the authoritative run
    /// that always follows does both.
    ///
    /// A SUCCESS still writes, and deliberately: that write is the whole
    /// latency win, and it is what puts CSS on disk in 13 ms rather than 50.
    /// It can be wrong — the save may not have finished — which is why the
    /// authoritative run is guaranteed and why `--update`'s freshness check
    /// is off for every run after the first (see `run_watch`).
    provisional: bool,
    /// Write an error stylesheet to a file target on failure (dart default:
    /// yes). Off means the opposite side effect: a stale output is REMOVED.
    file_error_css: bool,
    /// Print an error stylesheet to stdout on failure (`--error-css`, explicit).
    stdout_error_css: bool,
}

enum Status {
    Ok,
    /// A parse/eval error (or invalid UTF-8 input): exit 65.
    CompileError,
    /// The input could not be read or the output not written: exit 66.
    IoError,
}

/// What one unit produced. Diagnostics are buffered so parallel workers can
/// still be reported in command-line order.
class Outcome {
    stderr: string,
    stdout: string,
    status: Status,
    /// Every file this compile read, the entry included, each paired with
    /// what it looked like WHEN IT WAS READ — what `--watch` follows.
    /// Collected from the same `RecordingImporter` `--update` already uses,
    /// so the two flags cannot disagree about what a stylesheet depends on.
    loaded: root.std.Tuple2<string, root.watch.Stamp>[],
    /// The `@use`/`@import` urls that resolved to nothing, so `--watch` can
    /// follow the directories they WOULD have been found in.
    unresolved: string[],
    /// Outputs this compile CREATED or REMOVED — not merely overwrote.
    ///
    /// Only those move their directory's mtime, and that is the difference
    /// `--watch` needs: a directory we disturbed has to be re-stamped or the
    /// watch answers its own write, and a directory we only wrote an
    /// existing file into must NOT be, or a dependency arriving there while
    /// the compile ran is absorbed. In the ordinary `main.scss`/`main.css`
    /// layout those are the same directory, so "did we write into it" is
    /// the wrong question and "did we change what is in it" is the right
    /// one.
    disturbed: string[],
    function failed(status: Status, stderr: string) -> Outcome {
        Outcome {
            stderr: stderr,
            stdout: "",
            status: status,
            loaded: [],
            unresolved: [],
            disturbed: [],
        }
    }
}

/// Infer a file's syntax from its extension (`--indented` forces `.sass`).
/// Exact lowercase suffixes, like dart's `Syntax.forPath`: `input.CSS` or
/// `input.SASS` is SCSS.
function syntax_for(path: string, indented: bool) -> Syntax {
    if (indented) {
        return Syntax.Sass;
    }
    match (root.std.path_extension(path)) {
        "sass" => Syntax.Sass,
        "css" => Syntax.Css,
        _ => Syntax.Scss,
    }
}

/// Whether directory mode compiles this file: a `.scss`/`.sass`/`.css` (exact
/// lowercase suffix) whose name does not start with `_` (a partial), like
/// dart-sass.
function is_compilable(path: string) -> bool {
    let name = match (root.std.path_file_name(path)) {
        let n: string => n,
        null => {
            return false;
        },
    };
    // Exact lowercase suffixes, like dart's `_isEntrypoint`: `UPPER.SCSS` is
    // skipped.
    !name.starts_with("_")
        && (
            match (root.std.path_extension(path)) {
                "scss" | "sass" | "css" => true,
                _ => false,
            }
        )
}

/// Expand a `dir:outdir` pair into one unit per compilable file under `src`
/// (recursively), mirroring the tree under `dest` with a `.css` extension.
/// Files are visited in sorted order so output is deterministic. Symlinked
/// directories are followed (as dart does), but each directory is visited once
/// by canonical identity, so a symlink cycle cannot loop or duplicate output.
function expand_dir(src: string, dest: string, indented: bool, units: Unit[]) -> void {
    // PORT: `PathBuf`'s `Ord`, which `sort()` uses below, compares component
    // by component (`a/b` sorts before `a/b-c`, where a string compare would
    // not), and orders `/` < `.` < `..` < a name.
    let path_cmp = (a: string, b: string) -> baml.ops.Ordering {
        let ca = root.std.path_components(a);
        let cb = root.std.path_components(b);
        let rank = (c: string) -> int {
            if (c == "/") {
                0
            } else if (c == ".") {
                1
            } else if (c == "..") {
                2
            } else {
                3
            }
        };
        let k = 0;
        while (k < ca.length() && k < cb.length()) {
            let ra = rank(ca[k]);
            let rb = rank(cb[k]);
            if (ra != rb) {
                return ra.cmp(rb);
            }
            if (ca[k] != cb[k]) {
                return ca[k].cmp(cb[k]);
            }
            k += 1;
        }
        ca.length().cmp(cb.length())
    };
    let files: string[] = [];
    let seen: map<string, bool> = {};
    let _ = root.std.set_insert(
        seen,
        root.std.canonicalize(src) catch (e) {
            let _e: baml.errors.Io => src
        },
    );
    let stack = [src];
    while let dir: string = stack.pop() {
        let entries = root.std.read_dir_names(dir) catch (e) {
            let _e: baml.errors.Io => root.std.err_str(`Error reading ${dir}: Cannot open file.`)
        };
        let paths: string[] = [];
        for (let entry in entries) {
            // PORT: no per-entry error — `read_dir_names` fails as a whole, above.
            paths.push(root.std.path_join(dir, entry));
        }
        // `read_dir` order is unspecified; sort so that, of two names for the
        // same directory (symlinks), the same one is mirrored every run.
        paths.sort_by(path_cmp);
        for (let path in paths) {
            if (root.std.is_dir(path)) {
                let identity = root.std.canonicalize(path) catch (e) {
                    let _e: baml.errors.Io => path
                };
                if (root.std.set_insert(seen, identity)) {
                    stack.push(path);
                }
            } else if (is_compilable(path)) {
                files.push(path);
            }
        }
    }
    files.sort_by(path_cmp);
    let cwd = root.std.current_dir() catch (e) {
        let _e: baml.errors.Io => ""
    };
    let key = (p: string) -> string {
        path_key_in(root.pathstyle.HOST(), normalize_path(root.std.path_join(cwd, p)))
    };
    // Keyed ONCE, outside the loop: `path_key_in` lower-cases and reallocates
    // on Windows, and the destination does not change between files.
    let src_key = key(src);
    let dest_key = key(dest);
    // dart-sass 1.104.1 skips every source file INSIDE the output directory
    // when that directory is nested in the source tree: `.:css` run twice
    // would otherwise mirror `css/` into `css/css/`. Nesting is strict — a
    // destination EQUAL to the source is not nested, so `sasso dir` (which is
    // `dir:dir`) still compiles every file — and it is the destination that
    // counts, not an intermediate directory: `.:css/deep` skips only what is
    // under `css/deep`, and still compiles `css/stale.scss`.
    let nested = dest_nested_in_src(src_key, dest_key);
    for (let path in files) {
        let rel = root.std.path_with_extension(root.std.path_strip_prefix(path, src) ?? path, "css");
        let out = root.std.path_join(dest, rel);
        // Two keyings per file — the file and its destination — which is what
        // this loop cost before these rules were named.
        let path_key = key(path);
        if (nested && key_inside(dest_key, path_key)) {
            continue;
        }
        // dart skips a CSS file whose destination is itself (`sasso dir`, or
        // `dir:dir`, with a `plain.css` inside): it would only be rewritten in
        // place.
        if (root.std.path_eq(key(out), path_key)) {
            continue;
        }
        units.push(
            Unit {
                url: path,
                syntax: syntax_for(path, indented),
                source: Source_File { _0: path },
                target: Target_File { _0: out },
            },
        );
    }
}

function run(cli: Cli) -> int {
    // Gather the units. `--stdin` or the positional input is a single stdout
    // unit (redirected to a file by `-o` / a second positional); every `in:out`
    // pair is a file unit (a directory pair expands to one per file). Relative
    // imports resolve against the CONTAINING file's directory (the evaluator's
    // current_file_dir), like dart — the input's directory is deliberately NOT
    // an implicit load path.
    let units: Unit[] = [];
    // Standard input is read at most once, however many units name it.
    let stdin_cache: root.std.Cell<Source?> = root.std.Cell.new(null);
    let stdin_syntax: Syntax = if (cli.indented) {
        Syntax.Sass
    } else {
        Syntax.Scss
    };
    let dir_entry = false;
    if let out: string = cli.output {
        if (root.std.is_dir(out)) {
            return usage_error(`Directory ${root.std.debug_str(out)} may not be a positional arg.`);
        }
    }
    // PORT: `stdin_source`'s `Err(ExitCode)` is thrown as the exit code (an `int`).
    match (cli.entry) {
        Entry_Stdin {} => {
            let source = stdin_source(stdin_cache) catch (e) {
                let code: int => {
                    return code;
                }
            };
            units.push(
                Unit { source: source, url: "-", syntax: stdin_syntax, target: Target_Stdout {  } },
            );
        },
        // dart: a bare directory compiles in place (`sass dir` is `dir:dir`);
        // with an output it may not be a positional argument.
        Entry_File { _0: let path } if root.std.is_dir(path) => {
            if (cli.output != null) {
                return usage_error(`Directory ${root.std.debug_str(path)} may not be a positional arg.`);
            }
            expand_dir(path, path, cli.indented, units) catch (e) {
                let msg: root.std.StrError => {
                    baml.io.eprintln(msg.message);
                    return EXIT_IO();
                }
            };
            dir_entry = true;
        },
        Entry_File { _0: let path } => {
            units.push(
                Unit {
                    url: path,
                    syntax: syntax_for(path, cli.indented),
                    source: Source_File { _0: path },
                    target: Target_Stdout {  },
                },
            );
        },
        _ => {},
    }
    for (let pair in cli.pairs) {
        let src = pair._0;
        let dest = pair._1;
        if (root.std.path_eq(src, "-")) {
            // `-:out.css`: standard input to a file, alongside other pairs.
            let source = stdin_source(stdin_cache) catch (e) {
                let code: int => {
                    return code;
                }
            };
            units.push(
                Unit {
                    source: source,
                    url: "-",
                    syntax: stdin_syntax,
                    target: Target_File { _0: dest },
                },
            );
        } else if (root.std.is_dir(src)) {
            expand_dir(src, dest, cli.indented, units) catch (e) {
                let msg: root.std.StrError => {
                    baml.io.eprintln(msg.message);
                    return EXIT_IO();
                }
            };
        } else {
            units.push(
                Unit {
                    url: src,
                    syntax: syntax_for(src, cli.indented),
                    source: Source_File { _0: src },
                    target: Target_File { _0: dest },
                },
            );
        }
    }
    // dart keeps every source — explicit pairs and directory-expanded files
    // alike — in one path-keyed map, so a file named twice (`src:out` plus
    // `src/a.scss:a.css`) compiles once, to the destination named last.
    let units = {
        let cwd = root.std.current_dir() catch (e) {
            let _e: baml.errors.Io => ""
        };
        let keys: string[] = [];
        let kept: Unit[] = [];
        for (let unit in units) {
            let key = match (unit.source) {
                Source_File { _0: let path } => {
                    path_key(normalize_path(root.std.path_join(cwd, path)))
                },
                Source_Text {} | Source_InvalidUtf8 {} => "-",
                _ => root.std.unreachable(),
            };
            // A stdin unit's `-` is not a path and is left alone; every other
            // unit's display path is decided here rather than taken from the
            // command line (#151).
            if let path: string = unit.source_path() {
                let url = entry_display_url(cwd, path);
                unit.url = url;
            }
            match (
                keys.find_index((k) -> {
                    root.std.path_eq(k, key)
                })
            ) {
                let i: int => {
                    kept[i].target = unit.target;
                },
                _ => {
                    keys.push(key);
                    kept.push(unit);
                },
            }
        }
        kept
    };
    if let output: string = cli.output {
        // `parse_args` guarantees a single stdout unit here; redirect it.
        if let unit: Unit = units.at(0) {
            unit.target = Target_File { _0: output };
        }
    }
    if (units.length() == 0) {
        if (cli.pairs.length() == 0 && !dir_entry) {
            return usage_error("no input file (pass a path, an <in>:<out> pair, or --stdin)");
        }
        return 0;
    }

    let shared = Shared {
        load_paths: root.std.clone_vec(cli.load_paths),
        style: cli.style,
        unicode: !cli.no_unicode,
        charset: cli.charset,
        quiet: cli.quiet,
        quiet_deps: cli.quiet_deps,
        update: cli.update,
        silenced: root.std.clone_vec(cli.silenced),
        no_css: cli.no_css,
        embed_sources: cli.embed_sources,
        embed_source_map: cli.embed_source_map,
        source_map_urls: cli.source_map_urls ?? SourceMapUrls.Relative,
        // dart: source maps default ON when writing to a file; an explicit
        // `--embed-source-map` implies one.
        file_source_map: (cli.source_map ?? true) || cli.embed_source_map,
        watch: cli.watch,
        provisional: false,
        file_error_css: cli.error_css ?? true,
        stdout_error_css: cli.error_css == true,
    };

    // Throughput mode: recompile the whole input set in-process N times, timing
    // only the compile calls (sources are read once), and report ms/compile +
    // compiles/sec to stderr. The CSS is still emitted once unless `--no-css`.
    if let n: int = cli.loop_n {
        return run_loop(units, shared, n);
    }

    let jobs = cli.jobs ?? default_jobs();
    if (cli.watch) {
        return run_watch(units, shared, jobs, cli.stop_on_error);
    }
    let outcomes = compile_all(units, shared, jobs, cli.stop_on_error);

    // Report in command-line order: each unit's diagnostics, then its CSS.
    let worst: Status = Status.Ok;
    {
        // PORT: the locked `stdout`/`stderr` handles are `baml.io.print` and
        // `baml.io.eprint`. Neither returns an error: a failed write panics
        // with `baml.panics.HostUnavailable`, caught where Rust looks at the
        // `io::Error` (and read as `BrokenPipe` when its message says so).
        // dart separates one unit's diagnostics from the next with a blank
        // line; a warning block already ends in one, an error does not.
        let stderr_ends_blank = true;
        // A consumer that closed the pipe early is not an error (dart exits 0
        // too, as does every Unix filter); any other stdout failure is.
        let stdout_ok = true;
        for (let slot in outcomes) {
            // `.flatten()`: a `None` slot is a unit `--stop-on-error` skipped.
            if (slot == null) {
                continue;
            }
            let outcome = slot;
            worst = worse(worst, outcome.status);
            if (outcome.stderr != "") {
                if (!stderr_ends_blank) {
                    baml.io.eprint("\n") catch (e) {
                        baml.panics.HostUnavailable => null
                    };
                }
                baml.io.eprint(outcome.stderr) catch (e) {
                    baml.panics.HostUnavailable => null
                };
                stderr_ends_blank = outcome.stderr.ends_with("\n\n");
            }
            if (stdout_ok && outcome.stdout != "") {
                baml.io.print(outcome.stdout) catch (e) {
                    let err: baml.panics.HostUnavailable => {
                        stdout_ok = false;
                        if (!err.message.includes("Broken pipe")) {
                            baml.io.eprintln(`error: cannot write to stdout: ${err.message}`) catch (e2) {
                                baml.panics.HostUnavailable => null
                            };
                            worst = Status.IoError;
                        }
                    }
                };
            }
        }
        // PORT: `stdout.flush()` — `baml.io.print` flushes every write itself,
        // so there is nothing left to flush and no error to report here.
    };
    match (worst) {
        Status.Ok => 0,
        Status.CompileError => EXIT_COMPILE(),
        Status.IoError => EXIT_IO(),
    }
}

/// The more severe of two statuses (I/O error > compile error > ok).
function worse(a: Status, b: Status) -> Status {
    // PORT: the match on `(a, b)` as an `if` chain.
    if (a == Status.IoError || b == Status.IoError) {
        Status.IoError
    } else if (a == Status.CompileError || b == Status.CompileError) {
        Status.CompileError
    } else {
        Status.Ok
    }
}

/// Compile every unit, up to `jobs` at a time, returning one slot per unit in
/// input order. A slot is `None` when `stop_on_error` skipped the unit.
function compile_all(
    units: Unit[],
    shared: Shared,
    jobs: int,
    stop_on_error: bool,
) -> (Outcome?)[] {
    let n = units.length();
    // PORT: BAML `spawn` tasks run truly in parallel, but the Rust per-thread
    // compiler state (`thread_local!` extend budget and pseudo depth in
    // `selector`) is process-wide in the port (`client` cells), and the claim
    // counter below cannot be atomic. Compiles therefore run one at a time —
    // the same path Rust takes for `--jobs 1`; output is identical.
    jobs = 1;
    if (jobs <= 1 || n <= 1) {
        let results: (Outcome?)[] = [];
        for (let unit in units) {
            let outcome = compile_unit(unit, shared);
            let failed = outcome.status != Status.Ok;
            results.push(outcome);
            if (failed && stop_on_error) {
                break;
            }
        }
        // `results.resize_with(n, || None)`.
        while (results.length() < n) {
            results.push(null);
        }
        return results;
    }
    // A shared counter hands out the next unit; each worker stores its result
    // in that unit's slot, so ordering is recovered without a channel.
    // PORT: the scoped threads are green threads (`spawn`, joined by
    // `await`), the atomics `Cell`s and each `Mutex` slot a plain array slot.
    let next = root.std.Cell.new(0);
    let failed = root.std.Cell.new(false);
    let slots: (Outcome?)[] = baml.Array.filled(n, null);
    let workers = [];
    for (let _w in baml.iter.Range.new(0, root.std.imin(jobs, n))) {
        workers.push(spawn {
            while (true) {
                if (stop_on_error && failed.get()) {
                    break;
                }
                // `next.fetch_add(1, Ordering::Relaxed)`.
                let i = next.get();
                next.set(i + 1);
                if (i >= n) {
                    break;
                }
                // Re-check after claiming: a failure another worker reported
                // between the check above and the claim must not start this
                // unit either (its slot stays `None`, "not run").
                if (stop_on_error && failed.get()) {
                    break;
                }
                let outcome = compile_unit(units[i], shared);
                if (outcome.status != Status.Ok) {
                    failed.set(true);
                }
                slots[i] = outcome;
            }
        });
    }
    let _ = await baml.future.all(workers);
    slots
}

/// Read a unit's source text, or the outcome that reports why it could not be.
// Boxed: `Outcome` grew past clippy's `result_large_err` threshold when it
// started carrying what a compile loaded and disturbed for `--watch`. One
// allocation per FAILED read, which is a path that is already doing I/O.
function read_source(unit: Unit) -> string {
    // PORT: `Err(Box<Outcome>)` is thrown as the `Outcome` itself (catch it
    // with `let o: Outcome`); the `Cow` is a plain string.
    match (unit.source) {
        Source_Text { _0: let s } => s,
        Source_InvalidUtf8 {} => {
            throw Outcome.failed(Status.CompileError, "Error: Invalid UTF-8.\n");
        },
        Source_File { _0: let path } => {
            root.std.read_to_string(path) catch (e) {
                let io: baml.errors.Io => {
                    if (is_invalid_utf8(io)) {
                        throw Outcome.failed(Status.CompileError, "Error: Invalid UTF-8.\n");
                    }
                    throw Outcome.failed(Status.IoError, `Error reading ${path}: Cannot open file.\n`);
                }
            }
        },
        _ => root.std.unreachable(),
    }
}

/// An [`Importer`] that delegates to [`FsImporter`] and remembers every file
/// it loaded.
///
/// `--update` has to compare the output against the entry AND everything the
/// entry pulls in; editing a partial with the entry untouched is the common
/// case on an `@import`-heavy tree, and comparing the entry alone leaves stale
/// CSS on disk saying nothing (#133, fixed the same way in the npm CLI).
///
/// The list cannot come from `FsImporter::dependencies`: that set exists for
/// `--quiet-deps` and deliberately holds only files reached THROUGH A LOAD
/// PATH, so a tree with no `-I` — Lichess's, for one — records nothing at all.
/// Nor from the source map's `sources`, which would mean generating a map
/// under `--no-source-map` just to learn the file list.
///
/// `RefCell`, not a lock: each unit builds its own importer, so nothing here
/// is shared between the pool's threads.
class RecordingImporter {
    inner: root.importer.FsImporter,
    loaded: string[],
    /// Urls that resolved to nothing. `--watch` needs them: a dependency
    /// that does not exist YET has no path to follow, and the directory it
    /// would live in is not in `loaded` either — so without this, creating
    /// `sub/_new.scss` for an `@use "sub/new"` that has been failing since
    /// startup changes nothing anybody is looking at.
    unresolved: string[],
    /// What each loaded file looked like at the moment it was read — see
    /// [`RecordingImporter::loaded_stamps`].
    read_stamps: root.std.Tuple2<string, root.watch.Stamp>[],
    function new(load_paths: string[]) -> RecordingImporter {
        RecordingImporter {
            inner: root.importer.FsImporter.new(load_paths),
            loaded: [],
            unresolved: [],
            read_stamps: [],
        }
    }

    /// The wrapped importer's `--quiet-deps` provenance set. Different thing
    /// from `loaded_paths`: this one holds only what came through a load path,
    /// which is what dart's rule is about.
    function dependencies(self) -> root.importer.DependencySet {
        // PORT: `FsImporter::dependencies` is `dependencies_` (its field shares the name).
        self.inner.dependencies_()
    }

    /// The files loaded so far, as filesystem paths. A canonical URL that is
    /// not a `file:` URL has no path to stat and is dropped by the caller's
    /// freshness test, which treats an unknowable input as "not fresh".
    function loaded_paths(self) -> string[] {
        self.loaded.filter_map((u) -> {
            url_to_path(u)
        })
    }

    /// The same files, each paired with what it looked like WHEN IT WAS
    /// READ. `--watch` needs that rather than the state afterwards: a file
    /// this compile is meeting for the first time has no earlier stamp to
    /// keep, so taking one after the compile records a save that landed
    /// during it as the baseline and nothing ever compiles it. Measured
    /// before this, saving 300 ms into a 680 ms first compile: 3 of 5 lost.
    function loaded_stamps(self) -> root.std.Tuple2<string, root.watch.Stamp>[] {
        root.std.clone_vec(self.read_stamps)
    }

    /// Every file this compile ATTEMPTED to load, read or not.
    ///
    /// `loaded_paths` is the successful half and is what `--update`
    /// compares mtimes against. This is the half `--watch` needs when it
    /// asks "would writing here destroy something we touched": a
    /// dependency that exists and failed to load — bad permissions,
    /// invalid UTF-8 — is not a dependency, and overwriting it with error
    /// CSS is still destroying the user's file.
    function attempted_paths(self) -> string[] {
        self.read_stamps.map((pair) -> {
            pair._0
        })
    }

    /// The urls this compile could not resolve, as written in the `@use` or
    /// `@import`. Relative, so the caller pairs them with the directories
    /// they were searched for in.
    function unresolved_urls(self) -> string[] {
        root.std.clone_vec(self.unresolved)
    }

    implements root.importer.Importer {
        function canonicalize(
            self,
            url: string,
            ctx: root.importer.CanonicalizeContext,
        ) -> root.importer.CanonicalUrl? {
            let out = self.inner.canonicalize(url, ctx);
            if (out == null) {
                self.unresolved.push(url);
            }
            out
        }
        function load(
            self,
            canonical: root.importer.CanonicalUrl,
        ) -> root.importer.ImporterResult? {
            // BEFORE the read, not after: a save that lands while the file is
            // being read then differs from this stamp and is seen. The other
            // order would absorb it.
            let before: root.std.Tuple2<string, root.watch.Stamp>? = match (url_to_path(canonical.as_str())) {
                let p: string => {
                    let stamp = root.watch.Stamp.of(p);
                    root.std.Tuple2 { _0: p, _1: stamp }
                },
                _ => null,
            };
            // Recorded BEFORE the load is even attempted, and whatever it
            // answers. Three outcomes, and only one of them is a dependency:
            //
            //   Ok(Some) the file was read — a dependency, and followed
            //   Ok(None) it vanished between `canonicalize` and here. The
            //            importer's own comment calls that a miss, and the url
            //            never reaches `unresolved` either, because
            //            canonicalizing it SUCCEEDED
            //   Err      it is there and cannot be read: permissions, or
            //            invalid UTF-8
            //
            // The last two are not dependencies and must still be FOLLOWED, or
            // the file and its directory are watched by nobody and the fix
            // reaches nothing. Measured for the third: `chmod 000` a dependency,
            // and `chmod 644` afterwards was NEVER SEEN — the `?` returned
            // before the stamp was taken.
            if (before != null) {
                self.read_stamps.push(before);
            }
            let out = self.inner.load(canonical);
            if (out != null) {
                self.loaded.push(canonical.as_str());
            }
            out
        }
    }
}

/// One spelling for a watched directory, whatever it was written as.
///
/// The paths reaching the snapshot come from two places with different
/// habits — the command line, which says `out.css`, and the importer, which
/// says `/work/out.css` — and a set that holds both thinks they are two
/// directories.
function dirs_key(p: string) -> string {
    let cwd = root.std.current_dir() catch (e) {
        let _e: baml.errors.Io => ""
    };
    // `path_key` too, not just `normalize_path`. The importer lowercases a
    // canonical path on Windows and the command line says whatever the user
    // typed, so without the fold the same directory enters the snapshot
    // under two keys — and the one that is not in the `minus` set watches
    // the mtime our own output moves, which is the self-recompile loop this
    // whole mechanism exists to avoid. #146 was the same mistake one layer
    // down.
    path_key(normalize_path(root.std.path_join(cwd, p)))
}

/// Would writing `output` replace a file this compile read — the entry
/// itself, or one of its dependencies?
///
/// `path_key` rather than `==`, so the answer does not depend on the case a
/// path was typed in on Windows, where two spellings are one file.
function aliases_a_source(output: string, unit: Unit, deps: string[]) -> bool {
    // `dirs_key`, the same one the snapshot uses: the output is whatever was
    // typed on the command line and a dependency is the absolute path the
    // importer resolved, so `_v.scss` and `/…/_v.scss` are the same file
    // only once both are keyed — and the two places that ask this question
    // must not answer it differently.
    let cwd = root.std.current_dir() catch (e) {
        let _e: baml.errors.Io => ""
    };
    let key = dirs_key;
    // …and through any symlink, because two names for one file is the other
    // way to reach it. `out.css -> main.scss` passes a lexical comparison and
    // then overwrites the stylesheet. `canonicalize` answers only for a path
    // that EXISTS, which is why it is a second opinion rather than the rule:
    // an output that is not there yet cannot alias anything.
    let real = (p: string) -> string? {
        let c = root.std.canonicalize(root.std.path_join(cwd, p)) catch (e) {
            let _e: baml.errors.Io => null
        };
        if (c != null) {
            path_key(c)
        } else {
            null
        }
    };
    let dest = key(output);
    let dest_real = real(output);
    let same = (p: string) -> bool {
        if (root.std.path_eq(key(p), dest)) {
            return true;
        }
        // PORT: `dest_real.is_some() && real(p).is_some() && real(p) == dest_real`,
        // with `real(p)` asked once.
        let dr = dest_real;
        if (dr == null) {
            return false;
        }
        let rp = real(p);
        if (rp == null) {
            return false;
        }
        root.std.path_eq(rp, dr)
    };
    let source = unit.source_path();
    if (source != null) {
        if (same(source)) {
            return true;
        }
    }
    deps.some((d) -> {
        same(d)
    })
}

/// `--update`: is `output` at least as new as `input` and every file in
/// `deps`? A missing output, or an input that cannot be stat'd, is not fresh.
function output_is_fresh(output: string, input: string?, deps: string[]) -> bool {
    // PORT: `metadata(p).and_then(|m| m.modified())` is `root.std.mtime_nanos(p)`,
    // `None` where Rust has an `Err`.
    let out = root.std.mtime_nanos(output);
    if (out == null) {
        return false;
    }
    // A `None` input is an entry with no file behind it. `parse_args` refuses
    // the one way that can happen with `--update`, and this stays defensive
    // anyway: `into_iter()` on `None` yields nothing, so a missing input would
    // otherwise leave a no-import unit with an EMPTY loop, which reports fresh.
    if (input == null) {
        return false;
    }
    for (let src in [input].concat(deps)) {
        match (root.std.mtime_nanos(src)) {
            let t: bigint if t <= out => {},
            // Newer than the output, or gone: rebuild.
            _ => {
                return false;
            },
        }
    }
    true
}

/// Build the per-unit options. A helper fn (not a closure) so the returned
/// `Options` can borrow `unit`/`shared` for the caller's lifetime.
function options_for(
    unit: Unit,
    shared: Shared,
    importer: root.importer.Importer,
    deps: root.importer.DependencySet,
    unicode: bool,
    warn: WarnHandler,
) -> Options {
    let opts = Options.default()
        .with_style(shared.style)
        .with_syntax(unit.syntax)
        .with_importer(importer)
        .with_url(unit.url)
        .with_unicode(unicode)
        .with_charset(shared.charset)
        .with_source_map_include_sources(shared.embed_sources)
        .with_warn_handler(warn);
    let opts = if (shared.silenced.length() == 0) {
        opts
    } else {
        // Not filtered in the warn handler: silenced deprecations must not
        // reach the per-id cap, or the run ends with "N repetitive deprecation
        // warnings omitted" counting warnings the caller silenced. Measured
        // against dart-sass 1.104.1, which prints nothing at all there.
        opts.with_silenced_deprecations(shared.silenced)
    };
    if (shared.quiet_deps) {
        // dart's `--quiet-deps`: compiler warnings from dependencies —
        // stylesheets the importer reached through a load path, and whatever
        // those load relatively — are dropped inside the compiler, ahead of its
        // repetition cap. A dependency's own `@warn` still prints.
        opts.with_quiet_deps(deps)
    } else {
        opts
    }
}

/// A warning handler that appends each diagnostic to `buf` exactly as the
/// library's default logger would print it (the block plus a blank line),
/// honouring `--quiet` and `--quiet-deps`.
// PORT: `Rc<RefCell<String>>` → a shared `root.std.StrBuf`.
function buffered_warn_handler(shared: Shared, buf: root.std.StrBuf) -> WarnHandler {
    let quiet = shared.quiet;
    (ev: WarnEvent) -> void {
        // `--quiet` drops everything (`--quiet-deps` is applied inside the
        // compiler, see `options_for`).
        if (quiet) {
            return;
        }
        let b = buf;
        b.push_str(ev.formatted);
        b.push("\n");
    }
}

function silent_warn_handler() -> WarnHandler {
    (_ev: WarnEvent) -> void {}
}

/// Compile one unit end to end: read, compile (with a map when wanted), write
/// or buffer the CSS, and on failure render the diagnostic (plus dart's error
/// stylesheet where it applies).
function compile_unit(unit: Unit, shared: Shared) -> Outcome {
    // BEFORE the read, like every imported file's stamp (see
    // `RecordingImporter::load`). Taking it after the compile instead —
    // which is what `run_watch` used to do — absorbs a save that lands while
    // a slow compile is reading the entry: the stamp records the new bytes,
    // the CSS was built from the old ones, and the next sweep sees nothing
    // to do. Measured, saving the entry 200 ms into a 680 ms compile: 5 of 5
    // lost.
    let entry_path = unit.source_path();
    let entry_at_read: root.std.Tuple2<string, root.watch.Stamp>? = if (entry_path != null) {
        root.std.Tuple2 { _0: entry_path, _1: root.watch.Stamp.of(entry_path) }
    } else {
        null
    };
    // PORT: `match read_source(unit) { Ok(source) => …, Err(outcome) => … }`
    // — the `Err` is the `Outcome` that `read_source` throws.
    let outcome = {
        let source = read_source(unit);
        compile_source(unit, source, shared)
    } catch (e) {
        let outcome: Outcome => {
            // A read failure never reaches the compiler, but dart treats
            // invalid UTF-8 as a compile error all the same: the file target
            // gets the error stylesheet (or, with `--no-error-css`, loses any
            // stale CSS). There is no source span to render here.
            if (outcome.status == Status.CompileError) {
                let message = root.std.trim_end_matches(outcome.stderr, "\n");
                // Nothing was read, so there are no dependencies to alias.
                finish_compile_error(unit, shared, [], message, message, outcome);
            }
            outcome
        }
    };
    // Recorded even when the read FAILED: a watch whose entry cannot be read
    // has to notice it coming back, and in that state it is the only file
    // there is to follow.
    if (entry_at_read != null) {
        outcome.loaded.push(entry_at_read);
    }
    outcome
}

/// Wrap up a compile error for `unit`: write dart's error stylesheet where it
/// applies — or, with error CSS off, remove a stale output file so nothing
/// consumes the CSS of an earlier successful build (dart deletes it too; the
/// `.map`, if any, is left alone). `rendered` is the diagnostic as printed to
/// the terminal, `ascii` the same rendered with the ASCII glyph set.
function finish_compile_error(
    unit: Unit,
    shared: Shared,
    deps: string[],
    rendered: string,
    ascii: string,
    outcome: Outcome,
) -> void {
    // `--no-css` means no output-side effects at all: no error stylesheet, and
    // an existing output is left exactly as it was.
    //
    // A provisional run under `--watch` wants exactly that too, and for a
    // different reason: it compiles the instant a change is seen, which for a
    // slow save is a half-written file. Writing an error stylesheet for that,
    // or deleting the last good CSS, would make an editor's own write
    // sequence look like the user breaking their stylesheet.
    if (shared.no_css || shared.provisional) {
        return;
    }
    // …and the same for an output that IS one of this compile's sources.
    // The success arm declines to write there; this one used to write the
    // error stylesheet, or delete the file outright under `--no-error-css`.
    // Measured before this: `--watch main.scss main.scss`, then break a
    // dependency, and the entry is gone. Skipping a successful write and
    // then destroying the file on the next typo is worse than either.
    if (shared.watch) {
        if let file: Target_File = unit.target {
            let output = file._0;
            if (aliases_a_source(output, unit, deps)) {
                return;
            }
        }
    }
    match (unit.target) {
        Target_Stdout {} => {
            if (shared.stdout_error_css) {
                outcome.stdout = error_css(rendered, ascii);
            }
        },
        let file: Target_File => {
            let output = file._0;
            if (shared.file_error_css) {
                let existed = root.std.exists(output);
                // PORT: `if let Err(msg) = write_file(…)` — the `Err` is the
                // thrown `StrError`.
                let failed: string? = {
                    write_file(output, error_css(rendered, ascii).to_utf8());
                    null
                } catch (e) {
                    let msg: root.std.StrError => msg.message
                };
                if (failed != null) {
                    outcome.stderr = outcome.stderr + failed;
                    outcome.stderr = outcome.stderr + "\n";
                    outcome.status = Status.IoError;
                } else if (!existed) {
                    outcome.disturbed.push(output);
                }
            } else {
                // PORT: `if let Err(e) = std::fs::remove_file(output)` — the
                // `Err` is the thrown `Io`.
                let removal_error: baml.errors.Io? = {
                    root.std.remove_file(output);
                    null
                } catch (e) {
                    let io: baml.errors.Io => io
                };
                if (removal_error != null) {
                    // PORT: BAML's `Io` carries no `ErrorKind`; `NotFound` is
                    // "the path is not there".
                    if (root.std.exists(output)) {
                        // Said, but not made the verdict. `--no-error-css`
                        // means there is no output to produce, so a cleanup
                        // that fails does not change what went wrong with the
                        // stylesheet — and the run is still worth 65.
                        //
                        // Measured 2026-09-23 against dart 1.104.1, a stale
                        // output whose holding directory is read-only:
                        //
                        //   dart     65   says nothing about the removal
                        //   binary   66   says it                 (before)
                        //   npm      65   says it                 (#181)
                        //
                        // dart does ATTEMPT it — with a writable directory
                        // all three remove the stale file and all three exit
                        // 65 — so this is dart swallowing the failure rather
                        // than never trying. Telling someone their stale
                        // output could not be removed is useful and stays;
                        // making it the run's answer is what diverged.
                        outcome.stderr
                            = outcome.stderr
                                + `error: cannot remove ${output}: ${removal_error.message}\n`;
                    }
                } else {
                    // A removal moves the directory's mtime exactly as a
                    // creation does, and `--no-error-css` does one on every
                    // failed save.
                    outcome.disturbed.push(output);
                }
            }
        },
        _ => root.std.unreachable(),
    }
}

/// [`compile_unit`] for an already-read `source`.
function compile_source(unit: Unit, source: string, shared: Shared) -> Outcome {
    let importer = RecordingImporter.new(root.std.clone_vec(shared.load_paths));
    let warnings = root.std.StrBuf.new();
    let opts = options_for(
        unit,
        shared,
        importer,
        importer.dependencies(),
        shared.unicode,
        buffered_warn_handler(shared, warnings),
    );

    // No map when nothing will be written (`--no-css`): mapping is not free.
    let want_map = !shared.no_css
        && match (unit.target) {
            Target_File {} => shared.file_source_map,
            Target_Stdout {} => shared.embed_source_map,
            _ => root.std.unreachable(),
        };
    // `(css, map)`: the map is `Some` only when one was requested.
    let compiled: root.std.Ok<root.std.Tuple2<string, root.sourcemap.SourceMap?>> | root.std.Err<root.error.Error> = if (want_map) {
        {
            let r = compile_with_source_map(source, opts);
            let pair: root.std.Tuple2<string, root.sourcemap.SourceMap?> = root.std.Tuple2 { _0: r.css, _1: r.source_map };
            root.std.Ok { value: pair }
        } catch (e) {
            let err: root.error.Error => root.std.Err { error: err }
        }
    } else {
        {
            let css = compile(source, opts);
            let pair: root.std.Tuple2<string, root.sourcemap.SourceMap?> = root.std.Tuple2 { _0: css, _1: null };
            root.std.Ok { value: pair }
        } catch (e) {
            let err: root.error.Error => root.std.Err { error: err }
        }
    };
    // A stdin unit's text: dart records it in the map as a `data:` URI.
    let stdin_text: string? = match (unit.source) {
        let text: Source_Text => text._0,
        // `Source::File(_) | Source::InvalidUtf8`
        _ => null,
    };

    let outcome = Outcome {
        stderr: warnings.take(),
        stdout: "",
        status: Status.Ok,
        // Taken whether or not this is a watch: the compile has already
        // resolved the graph, and a second walk to learn it would be the
        // cost `--update`'s comment explains away.
        loaded: importer.loaded_stamps(),
        unresolved: importer.unresolved_urls(),
        disturbed: [],
    };
    match (compiled) {
        // `--no-css`: the compile (and its diagnostics) was all that was wanted.
        let _ok: root.std.Ok<root.std.Tuple2<string, root.sourcemap.SourceMap?>> if shared.no_css => {},
        let ok: root.std.Ok<root.std.Tuple2<string, root.sourcemap.SourceMap?>> => {
            let css = ok.value._0;
            let map = ok.value._1;
            match (unit.target) {
                Target_Stdout {} => {
                    outcome.stdout
                        = match (map) {
                            let map: root.sourcemap.SourceMap => {
                                // dart embeds a stdout map with absolute `file://` sources and
                                // no `file` field.
                                let sources = adjust_sources(map.sources, unit.url, stdin_text, "", SourceMapUrls.Absolute);
                                let json = dart_map_json(null, sources, map.sources_content, map.mappings);
                                append_source_map_footer(css, data_uri(json), shared.style)
                            },
                            // The library API omits the trailing newline dart-sass's CLI
                            // writes to non-empty output (empty output stays empty).
                            null if css == "" => css,
                            _ => `${css}\n`,
                        };
                },
                // `--update`: the compile has run, so the importer knows every
                // file that fed it. If the output on disk is at least as new as
                // all of them, leave it alone — including its mtime, which is
                // what downstream watchers key on and the point of the flag.
                //
                // Compiling first looks like the wrong order for a flag whose job
                // is to avoid compiling, and is the right one here: `[measured]`
                // on Lichess's 147 entry points, dart's `--update` takes 1.19s to
                // decide nothing changed where sasso compiles the whole tree in
                // 0.48s. Learning the graph any earlier would mean resolving
                // `@use`/`@import` a second time, outside the compiler that
                // already does it.
                // Never write over a file this compile READ. `sasso main.scss
                // main.scss` and `sasso main.scss _v.scss` both replace a
                // stylesheet with its own CSS — dart does that too for a
                // one-shot compile, so it is not ours to change there. Under
                // `--watch` dart declines, and the reason is visible the moment
                // you try it: the write is a change, the change is a compile,
                // and the compile writes again. Measured before this,
                // `--watch main.scss main.scss` for 2.5 seconds:
                //
                //   dart     Compiled x0   source untouched
                //   npm      Compiled x0   source untouched
                //   binary   Compiled x24  source DESTROYED
                //
                // Silent, because dart is silent.
                let file: Target_File => {
                    let output = file._0;
                    if (shared.watch && aliases_a_source(output, unit, importer.attempted_paths())) {} else if (
                        shared.update
                            && output_is_fresh(output, unit.source_path(), importer.loaded_paths())
                    ) {} else {
                        // Both files this write can CREATE. The sidecar is the one
                        // that is easy to forget: it is written by the same call and
                        // lands in the same directory, so a compile that recreates a
                        // deleted `.map` disturbs that directory just as a new CSS
                        // file would.
                        let existed = root.std.exists(output);
                        let map_path = append_ext(output, "map");
                        let map_existed = root.std.exists(map_path);
                        // PORT: `wrote` is the `Result` kept as a value: the
                        // thrown `StrError`'s message, or `null` for `Ok`.
                        let wrote: string? = {
                            write_css_file(output, css, map, unit.url, stdin_text, shared);
                            null
                        } catch (e) {
                            let msg: root.std.StrError => msg.message
                        };
                        // Asked of the filesystem, and asked whether or not the write
                        // returned `Ok`: a failure is not a write that did nothing.
                        // The map goes first and the CSS second, `write_file` creates
                        // the parent chain before either, and `std::fs::write` creates
                        // a file before it fills it — so a failed write can leave a
                        // map with no CSS beside it, or an empty CSS file, and an
                        // unrecorded creation is a directory change nobody owns. The
                        // rule this list states is "what this compile CREATED", not
                        // "what it finished".
                        if (!existed && root.std.exists(output)) {
                            outcome.disturbed.push(output);
                        }
                        if (!map_existed && root.std.exists(map_path)) {
                            outcome.disturbed.push(map_path);
                        }
                        if (wrote != null) {
                            outcome.stderr = outcome.stderr + wrote;
                            outcome.stderr = outcome.stderr + "\n";
                            outcome.status = Status.IoError;
                        } else if ((shared.update || shared.watch) && !shared.quiet) {
                            // dart narrates `--update` and `--watch`, and only those
                            // two: one line per file actually WRITTEN, on stdout,
                            // timestamped to the minute in local time (measured
                            // 2026-09-19 and 2026-09-20). A skipped output and a
                            // failed compile are both silent, which is why this sits
                            // on the success arm after the write rather than beside
                            // the freshness check.
                            //
                            // Under `--watch` a provisional run reaches here too, and
                            // its whole `stdout` is dropped by `run_watch` — so one
                            // save is one line, from the authoritative run, rather
                            // than the two the npm CLI prints for a `@warn`.
                            //
                            // `outcome.stdout` is flushed in command-line order, so a
                            // parallel build reports in argument order like dart's.
                            // Nothing else can be in it here: `--update` with a stdout
                            // destination is a usage error.
                            let stamp = root.localtime.local_stamp(root.localtime.now());
                            let source_path = unit.source_path();
                            let source = if (source_path == null) {
                                "stdin"
                            } else {
                                source_path
                            };
                            if (stamp != null) {
                                outcome.stdout = outcome.stdout + stamp;
                                outcome.stdout = outcome.stdout + " ";
                            }
                            outcome.stdout = outcome.stdout + `Compiled ${source} to ${output}.\n`;
                        }
                    }
                },
                _ => root.std.unreachable(),
            }
        },
        let failure: root.std.Err<root.error.Error> => {
            let err = failure.error;
            let rendered = err.to_string();
            outcome.stderr = outcome.stderr + rendered;
            outcome.stderr = outcome.stderr + "\n";
            outcome.status = Status.CompileError;
            let want_error_css = match (unit.target) {
                Target_File {} => shared.file_error_css,
                Target_Stdout {} => shared.stdout_error_css,
                _ => root.std.unreachable(),
            };
            // The comment block always uses the ASCII glyph set (dart avoids
            // non-ASCII there so the file needs no @charset); re-render the
            // error that way when the terminal rendering was Unicode.
            let ascii = if (want_error_css && shared.unicode) {
                let ascii_opts = options_for(unit, shared, importer, importer.dependencies(), false, silent_warn_handler());
                // PORT: `compile(…).err().map(|e| e.to_string())`.
                let reason: string? = {
                    let _css = compile(source, ascii_opts);
                    null
                } catch (e) {
                    let e: root.error.Error => e.to_string()
                };
                reason ?? rendered
            } else {
                rendered
            };
            finish_compile_error(
                unit,
                shared,
                // Every attempted load, not just the successful ones: a
                // dependency that is there and unreadable must not be
                // overwritten by the error stylesheet describing why.
                importer.attempted_paths(),
                rendered,
                ascii,
                outcome,
            );
        },
    }
    outcome
}

/// Throughput mode (`--loop N`): a warm/correctness pass reports diagnostics
/// once, then the whole set is recompiled N times with a silent logger.
/// `--watch`: compile, then keep compiling whenever anything the entry loaded
/// changes.
///
/// The watcher itself is in `watch.rs` — what to poll, how often, and how a
/// burst of saves becomes two compiles. This is the part that knows about
/// units: which files to follow, what to print, and what a provisional run is
/// allowed to do.
///
/// It never returns. dart's `--watch` exits only on a signal, and so does
/// this: a compile error is reported and waited on, not fatal.
function run_watch(units: Unit[], shared: Shared, jobs: int, stop_on_error: bool) -> int {
    // dart prints this before the first compile and `--quiet` does not
    // suppress it — measured 2026-09-20, and the npm CLI already matches.
    {
        // PORT: a locked `stdout` + `write_all` + `flush`; `baml.io.print`
        // flushes on every call.
        baml.io.print("Sass is watching for changes. Press Ctrl-C to stop.\n\n");
    };

    // A provisional run differs from an authoritative one in what it is
    // ALLOWED to do, not in how it compiles, so these are the same `Shared`
    // with a flag flipped rather than a second code path. (`..*shared` moves
    // only `Copy` fields — the two `Vec`s are listed above it — so the
    // borrow is never moved out of.)
    //
    // `--update` is honoured for the FIRST compile and never again, and that
    // is a correctness fix rather than an optimisation. Its freshness check
    // asks whether the output is newer than every input, and after the first
    // compile the output is one THIS SESSION wrote — so a provisional run
    // that caught a save half-written, succeeded, and wrote the wrong CSS
    // makes its own output look up to date, and the authoritative run behind
    // it skips the write that would have corrected it. Measured, writing
    // `$c: bl` and finishing `ue;` 400 ms into a 680 ms compile: 6 of 6 runs
    // stuck on `color: bl` forever. dart's own `--watch --update` is worse
    // here — it left the first change uncompiled entirely — so there is no
    // behaviour of its to copy.
    let live = Shared {
        ...shared,
        update: false,
        provisional: false,
        load_paths: root.std.clone_vec(shared.load_paths),
        silenced: root.std.clone_vec(shared.silenced),
    };
    let live_provisional = Shared {
        ...shared,
        update: false,
        provisional: true,
        load_paths: root.std.clone_vec(shared.load_paths),
        silenced: root.std.clone_vec(shared.silenced),
    };

    let snapshot = root.watch.Snapshot.default();
    let coalesce = root.watch.Coalesce.new(root.watch.WINDOW());
    let started = baml.time.Instant.now();
    let interval = root.watch.MIN_INTERVAL();
    // The first compile is authoritative: nothing is half-written yet, and a
    // watch that started against a broken stylesheet has to say so.
    let step: root.watch.Step = root.watch.Step_Run { provisional: false };
    let started_once = false;

    while (true) {
        if let run: root.watch.Step_Run = step {
            let provisional = run.provisional;
            // Before the compile, for the units it may never reach.
            // `--stop-on-error` can stop before a later unit is even read,
            // and that unit's entry still has to be followed — from BEFORE
            // the run, or an edit made while the failing compile was
            // running is adopted as the baseline and no later poll can see
            // it. A unit that does compile brings its own read-time stamp
            // back and that one wins.
            let before_run: root.std.Tuple2<string, root.watch.Stamp>[] = units.filter_map((u: Unit) -> root.std.Tuple2<string, root.watch.Stamp>? {
                let p = u.source_path();
                if (p != null) {
                    root.std.Tuple2 { _0: p, _1: root.watch.Stamp.of(p) }
                } else {
                    null
                }
            });
            let run_shared = if (!started_once) {
                // The very first compile is the only one `--update` applies
                // to; it is also never provisional.
                shared
            } else if (provisional) {
                live_provisional
            } else {
                live
            };
            started_once = true;
            let outcomes = compile_all(units, run_shared, jobs, stop_on_error);
            let ok = true;
            let followed: root.std.Tuple2<string, root.watch.Stamp>[] = [];
            let unresolved: string[] = [];
            let disturbed: string[] = [];
            {
                // PORT: locked `stdout`/`stderr` handles → `baml.io.print` /
                // `baml.io.eprint`, which write (and flush) immediately.
                let stderr_ends_blank = true;
                for (let slot in outcomes) {
                    // `.flatten()`: a skipped unit has no outcome.
                    if (slot == null) {
                        continue;
                    }
                    let outcome = slot;
                    if (outcome.status != Status.Ok) {
                        ok = false;
                    }
                    root.std.extend(followed, outcome.loaded);
                    root.std.extend(unresolved, outcome.unresolved);
                    root.std.extend(disturbed, outcome.disturbed);
                    // A provisional run reports NOTHING. Its diagnostics are
                    // about a file that may still be being written, and the
                    // authoritative run 50 ms behind it will print whatever
                    // is really wrong. Measured on the npm CLI, which does
                    // report from both: one save with a `@warn` prints the
                    // warning TWICE there and once in dart.
                    if (provisional) {
                        continue;
                    }
                    if (outcome.stderr != "") {
                        if (!stderr_ends_blank) {
                            baml.io.eprint("\n");
                        }
                        baml.io.eprint(outcome.stderr);
                        stderr_ends_blank = outcome.stderr.ends_with("\n\n");
                    }
                    baml.io.print(outcome.stdout);
                }
            };
            // Follow the ENTRY too. A compile that failed before reading
            // anything — a parse error in the entry, an unreadable file —
            // records no loads at all, and without this the watch would sit
            // there forever with nothing to notice.
            // Every entry that COMPILED brought its own read-time stamp
            // back. What is left is a unit that produced no outcome at all,
            // and its pre-run stamp is the one to use — `Snapshot::follow`
            // keeps the earliest observation of a path, so adding both is
            // safe and the older wins.
            root.std.extend(followed, before_run);
            // …and the directories they live in, so a dependency that does
            // not exist YET can arrive. A missing `@use` target has no path
            // to stat; its directory does, and its mtime moves when the file
            // is created.
            let dirs: string[] = followed.filter_map((pair: root.std.Tuple2<string, root.watch.Stamp>) -> string? {
                root.std.path_parent(pair._0)
            });
            root.std.extend(dirs, shared.load_paths);
            // A url that resolved to NOTHING names a directory none of those
            // cover as soon as it has a segment of its own: `@use "sub/new"`
            // would be found in `<base>/sub`, and `sub/` is in no compile's
            // dependency list because nothing in it was ever read. Following
            // a directory that does not exist yet costs nothing here —
            // `Stamp::MISSING` compares equal to itself and becomes a change
            // the moment the directory appears.
            let bases: string[] = root.std.clone_vec(dirs);
            for (let url in unresolved) {
                // PORT: `let Some(within) = parent.filter(non-empty) else { continue }`.
                let within = root.std.path_parent(url) ?? "";
                if (within == "") {
                    continue;
                }
                for (let base in bases) {
                    dirs.push(root.std.path_join(base, within));
                }
            }
            // The directories this compile actually DISTURBED — where it
            // created or removed a file, which is what moves a directory's
            // mtime. Only those are re-stamped; every other directory keeps
            // what it had, or a dependency created while the compile was
            // running would become the baseline.
            //
            // From what was written rather than from the targets: in the
            // ordinary `main.scss` / `main.css` layout the output's
            // directory IS the sources' directory, so "we have a target
            // there" would re-stamp it on every compile and absorb an
            // arrival. Overwriting an existing file disturbs nothing.
            //
            // Keyed through `dirs_key`, like `dirs` itself: the outputs are
            // spelled as they were typed and the dependencies as the
            // importer resolved them, so `out.css` and `/work/out.css` are
            // one directory only once both are.
            // The FILES this compile created or removed, keyed like the
            // directories they live in. `follow` turns them into "what in
            // this directory is ours", so our own output is neither an
            // arrival nor a mask for one.
            let ours: string[] = disturbed.map((f: string) -> string {
                dirs_key(f)
            });
            let dirs: string[] = dirs.map((d: string) -> string {
                dirs_key(d)
            });
            snapshot.follow(followed, dirs, ours, (p: string) -> root.watch.Stamp {
                root.watch.Stamp.of(p)
            });
            coalesce.finished(provisional, ok);
        }

        // PORT: `std::thread::sleep(interval)`.
        let _slept = baml.sys.sleep(interval) catch (e) {
            let _io: baml.errors.Io => null
        };
        let swept = baml.time.Instant.now();
        let changed = snapshot.changed((p: string) -> root.watch.Stamp {
            root.watch.Stamp.of(p)
        });
        interval = root.watch.next_interval(swept.elapsed(), root.watch.SWEEP_BUDGET());

        let now_ms = root.std.int_of(started.elapsed().to_milliseconds());
        // A change is told to the coalescer FIRST and always, even when a
        // catch-up is already due this tick. The old order asked the tick
        // first and took its run, dropping `changed` on the floor — and
        // `Snapshot::changed` has already advanced the stamp by then, so the
        // next sweep sees nothing and a save can be lost.
        //
        // Ordering it this way costs nothing: `on_change` while cooling only
        // sets the dirty bit, and having set it, `on_tick` cannot answer
        // `Run` in the same breath — it starts the cool-down. So the two
        // cannot both fire, and the catch-up still wins when it is due.
        let from_change: root.watch.Step = if (changed) {
            coalesce.on_change(now_ms)
        } else {
            root.watch.Step_Wait {  }
        };
        // PORT: `match (coalesce.on_tick(now_ms), from_change) { (run @ Run { .. }, _) => run, (_, from_change) => from_change }`.
        let tick = coalesce.on_tick(now_ms);
        step
            = match (tick) {
                let run: root.watch.Step_Run => run,
                _ => from_change,
            };
    }
}

function run_loop(units: Unit[], shared: Shared, n: int) -> int {
    let sources: string[] = [];
    for (let unit in units) {
        // Read once; the warm pass and the timed loop share the text.
        // PORT: `match read_source(unit) { Ok(s) => …, Err(outcome) => … }`
        // — the `Err` is the `Outcome` that `read_source` throws.
        let source = read_source(unit) catch (e) {
            let outcome: Outcome => {
                baml.io.eprint(outcome.stderr);
                return if (outcome.status == Status.IoError) {
                    EXIT_IO()
                } else {
                    EXIT_COMPILE()
                };
            }
        };
        let outcome = compile_source(unit, source, shared);
        baml.io.eprint(outcome.stderr);
        if (outcome.status != Status.Ok) {
            return if (outcome.status == Status.IoError) {
                EXIT_IO()
            } else {
                EXIT_COMPILE()
            };
        }
        sources.push(source);
    }
    let importer = root.importer.FsImporter.new(root.std.clone_vec(shared.load_paths));
    let last = "";
    let start = baml.time.Instant.now();
    let round = 0;
    while (round < n) {
        // PORT: `units.iter().zip(&sources)` → an index loop.
        let i = 0;
        while (i < units.length() && i < sources.length()) {
            let unit = units[i];
            let source = sources[i];
            let opts = options_for(
                unit,
                shared,
                importer,
                importer.dependencies_(),
                shared.unicode,
                silent_warn_handler(),
            );
            let css = compile(source, opts) catch (e) {
                let e: root.error.Error => {
                    baml.io.eprintln(e.to_string());
                    return EXIT_COMPILE();
                }
            };
            last = css;
            i += 1;
        }
        round += 1;
    }
    let elapsed = start.elapsed();
    let per = run_loop__as_secs_f64(elapsed) * 1000.0 / (n * 1.0);
    let per_sec = if (per > 0.0) {
        1000.0 / per
    } else {
        root.std.F64_INFINITY()
    };
    baml.io.eprintln(
        `sasso: ${n} compiles in ${run_loop__fmt_duration_prec3(elapsed)} => ${root.std.fmt_f64_prec(per, 3)} ms/compile, ${root.std.fmt_f64_prec(per_sec, 1)} compiles/sec`,
    );
    if (!shared.no_css && last != "") {
        // Match the CLI's single trailing newline (the library API omits it;
        // dart-sass emits nothing at all for empty output).
        baml.io.println(last);
    }
    0
}

/// PORT: `Duration::as_secs_f64` (`secs as f64 + nanos as f64 / 1e9`).
function run_loop__as_secs_f64(d: baml.time.Duration) -> float {
    let ns = d.to_nanoseconds();
    let secs = root.std.int_of(ns / 1000000000n);
    let nanos = root.std.int_of(ns % 1000000000n);
    secs * 1.0 + nanos * 1.0 / 1000000000.0
}

/// PORT: `format!("{:.3?}", duration)` — Rust's `Debug` for `Duration` at
/// precision 3: the largest unit of `s`/`ms`/`µs`/`ns` with a non-zero
/// integer part, three decimals, rounded half up (a carry may leave e.g.
/// `1000.000ms`).
function run_loop__fmt_duration_prec3(d: baml.time.Duration) -> string {
    let ns = d.to_nanoseconds();
    let secs = root.std.int_of(ns / 1000000000n);
    let nanos = root.std.int_of(ns % 1000000000n);
    if (secs > 0) {
        run_loop__fmt_decimal(secs, nanos, 100000000, "s")
    } else if (nanos >= 1000000) {
        run_loop__fmt_decimal(nanos / 1000000, nanos % 1000000, 100000, "ms")
    } else if (nanos >= 1000) {
        run_loop__fmt_decimal(nanos / 1000, nanos % 1000, 100, "µs")
    } else {
        run_loop__fmt_decimal(nanos, 0, 1, "ns")
    }
}

/// PORT: core's `fmt_decimal` for `Duration`'s `Debug`, fixed at precision 3.
function run_loop__fmt_decimal(
    integer_part: int,
    fractional_part: int,
    divisor: int,
    postfix: string,
) -> string {
    let buf = [0, 0, 0];
    let end = 3;
    let pos = 0;
    let frac = fractional_part;
    let div = divisor;
    while (frac > 0 && pos < end) {
        buf[pos] = frac / div;
        frac = frac % div;
        div = div / 10;
        pos += 1;
    }
    let int_part = integer_part;
    if (frac > 0 && frac >= div * 5) {
        let rev_pos = pos;
        let carry = true;
        while (carry && rev_pos > 0) {
            rev_pos -= 1;
            if (buf[rev_pos] < 9) {
                buf[rev_pos] += 1;
                carry = false;
            } else {
                buf[rev_pos] = 0;
            }
        }
        if (carry) {
            int_part += 1;
        }
    }
    `${int_part}.${buf[0]}${buf[1]}${buf[2]}${postfix}`
}

/// Standard input as a unit source, read on first use and handed out again
/// afterwards (a `-` entry and a `-:out` pair may both name it). Invalid
/// UTF-8 becomes [`Source::InvalidUtf8`] so the unit fails like a file would
/// (dart itself crashes on this); an I/O failure is reported here and mapped
/// to the exit code the caller should return with.
function stdin_source(cache: root.std.Cell<Source?>) -> Source {
    // PORT: `Result<Source, ExitCode>` — the `Err` exit code is thrown as an
    // `int`; `Source` values are immutable, so `.clone()` is an alias.
    let cached = cache.value;
    if (cached != null) {
        return cached;
    }
    let source: Source = {
        let text = read_stdin();
        Source_Text { _0: text }
    } catch (e) {
        let e: baml.errors.Io => {
            if (is_invalid_utf8(e)) {
                Source_InvalidUtf8 {  }
            } else {
                baml.io.eprintln(`error: failed to read stdin: ${e.message}`);
                throw EXIT_IO();
            }
        }
    };
    cache.value = source;
    source
}

function read_stdin() -> string {
    // PORT: `std::io::stdin().read_to_string(&mut s)?`.
    let s = root.std.read_stdin();
    s
}

function is_invalid_utf8(e: baml.errors.Io) -> bool {
    // PORT: `e.kind() == ErrorKind::InvalidData` — BAML's `Io` has no kind;
    // `root.std.read_stdin` reports invalid UTF-8 with Rust's own
    // `InvalidData` message, and `root.std.read_to_string` passes on the
    // runtime's `Failed to read file '<path>': stream did not contain valid
    // UTF-8` (an `Io`, not the `ParseError` `baml.fs.read` documents).
    e.message.starts_with("stream did not contain valid UTF-8")
        || e.message.ends_with("': stream did not contain valid UTF-8")
}

// ---------------------------------------------------------------------------
// File output
// ---------------------------------------------------------------------------
/// Write `bytes` to `path`, creating missing parent directories like dart-sass.
function write_file(path: string, bytes: uint8array) -> void {
    let parent = root.std.path_parent(path);
    if (parent != null) {
        if (parent != "") {
            root.std.create_dir_all(parent) catch (e) {
                let e: baml.errors.Io => {
                    root.std.err_str(`error: cannot create ${parent}: ${e.message}`)
                }
            };
        }
    }
    root.std.write_file_bytes(path, bytes) catch (e) {
        let e: baml.errors.Io => root.std.err_str(`error: cannot write ${path}: ${e.message}`)
    };
}

/// Write compiled CSS to `output`. With a map: either a `<output>.map` sidecar
/// plus a `sourceMappingURL` footer, or (`--embed-source-map`) the map inlined
/// as a `data:` URI in the footer — byte-for-byte what dart-sass writes.
/// `input_url` is the input path as given on the command line.
function write_css_file(
    output: string,
    css: string,
    map: root.sourcemap.SourceMap?,
    input_url: string,
    stdin_text: string?,
    shared: Shared,
) -> void {
    match (map) {
        let map: root.sourcemap.SourceMap => {
            // The sidecar lives next to the CSS as `<output>.map`; the footer URL
            // is its basename (dart writes e.g. `out.css.map` and footers
            // `out.css.map`). An embedded map keeps the same relative sources.
            let map_path = append_ext(output, "map");
            // Both the map's `file` and the footer's URL are URLs, not paths:
            // dart percent-encodes the basename (`out%20file%231.css`).
            let file = encode_url_segment(path_basename(output));
            let sources = adjust_sources(map.sources, input_url, stdin_text, map_path, shared.source_map_urls);
            let map_json = dart_map_json(file, sources, map.sources_content, map.mappings);
            if (shared.embed_source_map) {
                let css = append_source_map_footer(css, data_uri(map_json), shared.style);
                write_file(output, css.to_utf8())
            } else {
                // The map goes first (dart's order too): if it cannot be
                // written, no CSS pointing at a missing map gets published.
                let map_url = encode_url_segment(path_basename(map_path));
                let css = append_source_map_footer(css, map_url, shared.style);
                write_file(map_path, map_json.to_utf8());
                write_file(output, css.to_utf8())
            }
        },
        _ => {
            // dart terminates a CSS FILE with exactly one newline, an empty
            // stylesheet included (`\n` alone); only stdout gets nothing for
            // empty output. The library API omits the newline.
            let css = `${css}\n`;
            write_file(output, css.to_utf8())
        },
    }
}

/// dart's `sourceMappingURL` footer. The library CSS has no trailing newline,
/// so EXPANDED appends `\n\n/*# … */\n` (the line terminator plus dart's blank
/// separator line, yielding `…}\n\n/*# … */\n`); COMPRESSED appends
/// `/*# … */\n` with no leading newline. Any `*/` in the URL is escaped as
/// `%2A/` so it cannot terminate the comment early.
function append_source_map_footer(css: string, url: string, style: OutputStyle) -> string {
    let url = url.replace_all("*/", "%2A/");
    let out = root.std.StrBuf.with_capacity(css.length() + url.length() + 32);
    out.push_str(css);
    match (style) {
        OutputStyle.Expanded => out.push_str(`\n\n/*# sourceMappingURL=${url} */\n`),
        OutputStyle.Compressed => out.push_str(`/*# sourceMappingURL=${url} */\n`),
    }
    out.as_str()
}

/// dart's error stylesheet (`--error-css`): the ASCII-rendered diagnostic as a
/// leading comment, then a `body::before` whose `content` shows the full
/// diagnostic in the browser. `rendered` is the error as printed to the
/// terminal (Unicode glyphs unless `--no-unicode`); `ascii` the same error
/// rendered with the ASCII glyph set.
function error_css(rendered: string, ascii: string) -> string {
    let ascii = root.std.trim_end_matches(ascii, "\n");
    let rendered = root.std.trim_end_matches(rendered, "\n");
    // `*/` inside the message would close the comment; dart swaps the slash
    // for U+2215 DIVISION SLASH.
    let comment = ascii.replace_all("*/", "*" + root.std.chr_unchecked(0x2215)).replace_all("\n", "\n * ");
    let content = root.std.StrBuf.with_capacity(rendered.length() + 32);
    for (let c in rendered.chars()) {
        match (c) {
            "\"" => content.push_str("\\\""),
            "\\" => content.push_str("\\\\"),
            "\n" => content.push_str("\\a "),
            let c if !c.is_ascii() => {
                content.push_str("\\" + root.std.hex_lower(root.std.ord(c)) + " ")
            },
            let c => content.push(c),
        }
    }
    let content = content.as_str();
    "/* "
        + comment
        + " */\n\n"
        + "body::before {\n  "
        + "font-family: \"Source Code Pro\", \"SF Mono\", Monaco, Inconsolata, \"Fira Mono\",\n      "
        + "\"Droid Sans Mono\", monospace, monospace;\n  "
        + "white-space: pre;\n  "
        + "display: block;\n  "
        + "padding: 1em;\n  "
        + "margin-bottom: 1em;\n  "
        + "border-bottom: 2px solid black;\n  "
        + "content: \""
        + content
        + "\";\n"
        + "}\n"
}

/// The inline form of a source map (`--embed-source-map`): dart's
/// `Uri.dataFromString` output, i.e. `data:application/json;charset=utf-8,`
/// followed by the JSON with every byte outside the URI "uric" set
/// (unreserved + sub-delims + `;/?:@&=+$,`) percent-encoded as uppercase `%XX`.
function data_uri(json: string) -> string {
    `data:application/json;charset=utf-8,${uric_encode(json)}`
}

/// Percent-encode `s` the way dart's `Uri.dataFromString` does: every byte
/// outside the URI "uric" set (unreserved + sub-delims + `;/?:@&=+$,`) becomes
/// uppercase `%XX`.
function uric_encode(s: string) -> string {
    let out = root.std.StrBuf.with_capacity(s.length());
    // PORT: `s.bytes()` → an index loop over the UTF-8 bytes; each byte is
    // compared as the one-character string of its value.
    let bytes = s.to_utf8();
    let i = 0;
    while (i < bytes.length()) {
        let b = bytes[i];
        let c = root.std.chr_unchecked(b);
        let keep = (b < 128 && c.is_ascii_alphanumeric())
            || match (c) {
                "-"
                    | "."
                    | "_"
                    | "~"
                    | "!"
                    | "*"
                    | "'"
                    | "("
                    | ")"
                    | ";"
                    | "/"
                    | "?"
                    | ":"
                    | "@"
                    | "&"
                    | "="
                    | "+"
                    | "$"
                    | "," =>
                {
                    true
                },
                _ => false,
            };
        if (keep) {
            out.push(c);
        } else {
            out.push("%");
            out.push(hex_upper(b >> 4));
            out.push(hex_upper(b & 0xf));
        }
        i += 1;
    }
    out.as_str()
}

/// Serialize the map JSON in dart-sass's exact field order:
/// `version, sourceRoot:"", sources, names:[], mappings[, file][, sourcesContent]`.
/// Hand-built (zero-dep) with the same string escaping dart uses. `file` is
/// omitted for a map embedded in stdout output, as dart does.
function dart_map_json(
    file: string?,
    sources: string[],
    contents: string[]?,
    mappings: string,
) -> string {
    let s = root.std.StrBuf.from("{\"version\":3,\"sourceRoot\":\"\",\"sources\":[");
    let i = 0;
    for (let src in sources) {
        if (i > 0) {
            s.push(",");
        }
        json_str(src, s);
        i += 1;
    }
    s.push_str("],\"names\":[],\"mappings\":");
    json_str(mappings, s);
    if (file != null) {
        s.push_str(",\"file\":");
        json_str(file, s);
    }
    if (contents != null) {
        s.push_str(",\"sourcesContent\":[");
        let i = 0;
        for (let c in contents) {
            if (i > 0) {
                s.push(",");
            }
            json_str(c, s);
            i += 1;
        }
        s.push("]");
    }
    s.push("}");
    s.as_str()
}

/// Append a JSON string literal (quotes + escaping) to `out`, matching the
/// library's `sourcemap::json_str` so map fields are byte-identical to dart.
function json_str(value: string, out: root.std.StrBuf) -> void {
    out.push("\"");
    for (let c in value.chars()) {
        match (c) {
            "\"" => out.push_str("\\\""),
            "\\" => out.push_str("\\\\"),
            "\n" => out.push_str("\\n"),
            "\r" => out.push_str("\\r"),
            "\t" => out.push_str("\\t"),
            "\b" => out.push_str("\\b"),
            "\f" => out.push_str("\\f"),
            let c if root.std.ord(c) < 0x20 => {
                // `format!("\\u{:04x}", c as u32)`
                let hex = root.std.hex_lower(root.std.ord(c));
                out.push_str("\\u" + "0".repeat(4 - hex.length()) + hex);
            },
            let c => out.push(c),
        }
    }
    out.push("\"");
}

/// The basename (last path component) of `p` as a lossy string.
function path_basename(p: string) -> string {
    root.std.path_file_name(p) ?? p
}

/// `<p>.<ext>` — append a new extension component (e.g. `out.css` -> `out.css.map`).
function append_ext(p: string, ext: string) -> string {
    let s = p;
    s = s + ".";
    s = s + ext;
    s
}

/// Rewrite each source URL to dart's form for the chosen `--source-map-urls`:
/// `relative` = the lexically-normalized path from the `.map` file's directory
/// to the source (URL-encoded); `absolute` = a canonicalized `file://` URL.
/// The library hands us the input path(s) as stamped during eval (the entry is
/// `input_url`); we adjust each one the same way dart does. A stdin entry has
/// no path: dart records its text as a `data:;charset=utf-8,…` URI.
function adjust_sources(
    sources: string[],
    input_url: string,
    stdin_text: string?,
    map_path: string,
    mode: SourceMapUrls,
) -> string[] {
    let cwd = root.std.current_dir() catch (e) {
        let _io: baml.errors.Io => ""
    };
    sources.map((src: string) -> string {
        // The entry source equals `input_url`; imports carry their own paths.
        let is_entry = src == "stdin" || src == input_url;
        if (is_entry) {
            if let text: string = stdin_text {
                return `data:;charset=utf-8,${uric_encode(text)}`;
            }
        }
        // Treat each as a filesystem path relative to cwd.
        let raw = if (src == "stdin") {
            input_url
        } else {
            src
        };
        let abs = normalize_path(root.std.path_join(cwd, raw));
        match (mode) {
            SourceMapUrls.Absolute => file_url(abs),
            SourceMapUrls.Relative => {
                let map_dir = normalize_path(root.std.path_join(cwd, root.std.path_parent(map_path) ?? ""));
                let rel = relative_path(map_dir, abs);
                match (rel) {
                    let rel: string => encode_url_path(rel),
                    // A source on another drive or share: dart's `p.relative`
                    // returns the absolute path there and `p.toUri` spells it
                    // as a `file:` URL. A `..` chain across roots would name
                    // nothing at all.
                    _ => file_url(abs),
                }
            },
        }
    })
}

/// A path reduced to the key the two directory-relationship tests compare —
/// "is this file inside the destination" and "is its destination itself".
///
/// On Windows the filesystem is case-insensitive and dart canonicalizes each
/// part to lowercase (see `importer::absolute_normalized`), so `Src:src/css`
/// names one directory two ways and the tests have to see that. Everywhere
/// else the path is compared as written, again like dart — which case-folds
/// for no other style, not even on a case-insensitive macOS volume. The key
/// is lexical either way: no `realpath`, so a symlink is not resolved.
function path_key_in(style: root.pathstyle.Style, p: string) -> string {
    match (style) {
        root.pathstyle.Style.Windows => p.to_lower_case(),
        root.pathstyle.Style.Posix => p,
    }
}

/// [`path_key_in`] under this platform's rules.
function path_key(p: string) -> string {
    path_key_in(root.pathstyle.HOST(), p)
}

/// Is the key `p_key` the key `dir_key` itself, or one inside it?
///
/// `starts_with` compares whole COMPONENTS, so `src2` is not inside `src` —
/// a string prefix would make `.:cssx` skip a tree it never writes to.
///
/// Both arguments are [`path_key_in`] output, not raw paths. Keeping the
/// keying out of here is what lets `expand_dir` key the destination once
/// instead of once per file; the style question lives in `path_key_in`, and
/// these two rules are then pure comparisons.
function key_inside(dir_key: string, p_key: string) -> bool {
    root.std.path_starts_with(p_key, dir_key)
}

/// Is the destination nested STRICTLY inside the source tree — the case where
/// a second run would mirror the output directory into itself?
///
/// Equal is not nested: `sasso dir` is `dir:dir`, and it still compiles every
/// file. Both arguments are [`path_key_in`] output.
function dest_nested_in_src(src_key: string, dest_key: string) -> bool {
    // PORT: `PathBuf` `!=` compares components.
    !root.std.path_eq(dest_key, src_key) && key_inside(src_key, dest_key)
}

/// Lexically normalize a path: resolve `.`/`..` components without touching the
/// filesystem (so it works for paths that may not exist yet), like dart's URL
/// normalization. Keeps it absolute if it started absolute.
function normalize_path(p: string) -> string {
    // PORT: `std::path::Component`s are the strings `root.std.path_components`
    // yields: "/" (RootDir), "." (CurDir), ".." (ParentDir), else Normal.
    // A Unix host has no `Prefix`.
    let out: string[] = [];
    for (let comp in root.std.path_components(p)) {
        match (comp) {
            "." => {},
            ".." => {
                let last = root.std.last(out);
                if (last != null && last != "/" && last != "." && last != "..") {
                    let _ = out.pop();
                } else if (last != "/") {
                    out.push(comp);
                }
            },
            let c => out.push(c),
        }
    }
    root.std.path_from_components(out)
}

/// The relative path from directory `base` to `target`, as forward-slash
/// segments (dart emits `/`-separated source URLs on every platform). Both must
/// be normalized absolute paths.
///
/// `None` when the two have no relative spelling: different Windows drives or
/// shares. The comparison is the platform's, not the string's — a canonical key
/// is lowercased on Windows while the working directory is not, and comparing
/// those literally is #146.
/// The entry stylesheet's path as dart spells it in a stack frame: lexically
/// normalized, then relative to the working directory in the platform's
/// separator — `p.prettyUri`, the same rule every LOADED file's frame goes
/// through.
///
/// dart makes no exception for the entry, so the spelling on the command line
/// does not survive into a diagnostic: `./src/a.scss`, `src/../src/a.scss`,
/// `src//a.scss` and an absolute path all report `src/a.scss` from that
/// directory. We used to echo the argument verbatim (#151), which on Windows
/// also left the entry `/`-separated while every loaded file beside it was
/// `\`-separated — one warning block, two spellings.
///
/// The value also reaches `adjust_sources` as the source map's entry, which is
/// safe in both of its uses: it re-derives each url from `cwd.join(src)`, so a
/// respelling normalizes to the same absolute path, and its stdin test compares
/// against `-`, which never gets here.
function entry_display_url(cwd: string, path: string) -> string {
    let abs = normalize_path(root.std.path_join(cwd, path));
    root.pathstyle.pretty(root.pathstyle.HOST(), abs, cwd)
}

function relative_path(base: string, target: string) -> string? {
    let parts = root.pathstyle.relative_parts(root.pathstyle.HOST(), base, target);
    if (parts != null) {
        root.std.join(parts, "/")
    } else {
        null
    }
}

/// A `file://` URL for an absolute path, percent-encoding each segment the way
/// dart's `Uri` does (and forward-slash separated).
function file_url(abs: string) -> string {
    let s = root.std.StrBuf.from("file://");
    for (let comp in root.std.path_components(abs)) {
        match (comp) {
            "/" => {},
            // PORT: `Component::Prefix` (a Windows drive or UNC share) cannot
            // occur on a Unix host, so its arms are not ported.
            let c => {
                s.push("/");
                s.push_str(encode_url_segment(c));
            },
        }
    }
    s.as_str()
}

/// The local path a canonical URL names, or `None` when this cannot say.
///
/// The inverse of [`file_url`], deliberately partial: a non-`file:` URL from a
/// custom importer has no path, and neither does a relative one.
///
/// # What `None` means, per caller
///
/// It is read in opposite directions, which the doc here used to get wrong by
/// naming only the first:
///
/// | caller | `None` means | direction |
/// |---|---|---|
/// | [`RecordingImporter::loaded_paths`] — `--update` freshness | "unknowable input, rebuild" | safe: costs one extra write |
/// | [`RecordingImporter::load`] — the watch's pre-read stamp | no stamp is recorded for that file | NOT safe: a save landing mid-read is not seen |
///
/// Latent rather than live, because the `file:` arm below is unreachable
/// today: `FsImporter`'s canonical form IS the absolute filesystem path, so
/// every canonical the binary sees takes the first arm. Measured by
/// instrumenting both arms and running the CLI suite — 11 hits on the path
/// arm, 0 on the `file:` one — so the second column is a warning about a
/// future importer, not a bug anyone can reach now.
///
/// Reading the canonical as a URL was this function's FIRST bug: every
/// dependency parsed as `None`, the list came back empty, and `--update`
/// reported a stale output as fresh — passing the "nothing changed" test while
/// failing the one the flag exists for. Hence the arm order.
function url_to_path(url: string) -> string? {
    if (!url.starts_with("file:")) {
        let p = url;
        return if (root.std.path_is_absolute(p)) {
            p
        } else {
            null
        };
    }
    // One line, because the decoder lives in the `sasso` crate. This file had
    // the third copy of it (#188, after #163 unified the other two), with its
    // own `percent_decode` beside it, and it had drifted the same way the
    // others had: it declined a `localhost` authority, and it declined a UNC
    // form that `pathstyle` resolves on Windows and correctly refuses on
    // POSIX. The strict reading is the right one here — this path is about to
    // be `stat`ed.
    file_url_to_path(url)
}

/// Percent-encode a forward-slash-separated relative URL path (keeping the `/`).
function encode_url_path(path: string) -> string {
    path.split("/")
        .map((seg: string) -> string {
            encode_url_segment(seg)
        })
        .join("/")
}

/// Percent-encode one URL path segment exactly like dart's `Uri`: keep the
/// unreserved set (`A-Za-z0-9-._~`), the sub-delims (`!$&'()*+,;=`) and `@`;
/// percent-encode every other byte (UTF-8) as uppercase `%XX`.
function encode_url_segment(seg: string) -> string {
    let out = root.std.StrBuf.with_capacity(seg.length());
    // PORT: `seg.bytes()` → an index loop over the UTF-8 bytes; each byte is
    // compared as the one-character string of its value.
    let bytes = seg.to_utf8();
    let i = 0;
    while (i < bytes.length()) {
        let b = bytes[i];
        let c = root.std.chr_unchecked(b);
        let keep = (b < 128 && c.is_ascii_alphanumeric())
            || match (c) {
                "-"
                    | "."
                    | "_"
                    | "~"
                    | "!"
                    | "$"
                    | "&"
                    | "'"
                    | "("
                    | ")"
                    | "*"
                    | "+"
                    | ","
                    | ";"
                    | "="
                    | "@" =>
                {
                    true
                },
                _ => false,
            };
        if (keep) {
            out.push(c);
        } else {
            out.push("%");
            out.push(hex_upper(b >> 4));
            out.push(hex_upper(b & 0xf));
        }
        i += 1;
    }
    out.as_str()
}

function hex_upper(nibble: int) -> string {
    match (nibble) {
        let n if n >= 0 && n <= 9 => root.std.chr_unchecked(0x30 + n),
        _ => root.std.chr_unchecked(0x41 + (nibble - 10)),
    }
}
