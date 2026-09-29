// BAML port of `benchmark/run.py`.
//
// Differences from the original:
// * The competitor parsers (`rtoml`, `pytomlpp`, `toml`, `tomlkit`) are Python
//   packages and cannot be called from BAML. The baseline is BAML's own
//   built-in (Rust-backed) TOML parser, `baml.toml.Table.parse`, which plays
//   the role `rtoml` (also Rust-backed) plays in the original.
// * `timeit.repeat` has no counterpart; `_timeit_repeat` reimplements it with
//   `baml.time.Instant`.
// * `print(..., end="", flush=True)` + `"\b"` backspacing is replaced by
//   printing each result line once it is known (`baml.io.print` has no flush
//   control).
// * The `if __name__ == "__main__": run(5000)` entry point is
//   `baml run benchmark.main`. 5000 runs of the tree-walking BAML port take
//   far too long, so `main` defaults to 20; pass another count with
//   `baml run --function benchmark.run -- benchmark.run --run-count N`.
// * `Path(__file__).parent / "data.toml"` is resolved relative to the working
//   directory (BAML has no `__file__`).

/// Python: `min(timeit.repeat(func, number=run_count, repeat=repeat))`, in
/// seconds.
function _timeit_repeat(func: () -> void, run_count: int, repeat: int) -> float {
    let best: float? = null;
    for (let r = 0; r < repeat; r += 1) {
        let start = baml.time.Instant.now();
        for (let i = 0; i < run_count; i += 1) {
            func();
        }
        let ns = start.elapsed().to_nanoseconds();
        let secs = (
            baml.Float.parse(ns.to_string()) catch (e) {
                _ => 0.0
            }
        )
            / 1000000000.0;
        // NOTE: `best == null || secs < best` does not narrow `best` on the
        // right-hand side of `||` (E0004), hence the nested form.
        if (best == null) {
            best = secs;
        } else if (secs < best) {
            best = secs;
        }
    }
    best ?? 0.0
}

function _rjust(s: string, width: int) -> string {
    let out = s;
    while (out.length() < width) {
        out = " " + out;
    }
    out
}

/// Python's `f"{x:.3g}"` (approximately: 3 significant digits).
function _fmt_3g(x: float) -> string {
    if (x == 0.0) {
        return "0";
    }
    let magnitude = x.abs().log10().floor();
    let scale = (10.0).pow(2.0 - magnitude);
    let rounded = (x * scale).round() / scale;
    rounded.to_string()
}

/// Python's `f"{x:.2%}"`.
function _fmt_percent(x: float) -> string {
    let hundredths = (x * 10000.0).round();
    let whole = (hundredths / 100.0).trunc();
    let frac = (hundredths - whole * 100.0).abs();
    let frac_s = frac.iround() catch (e) {
        _ => 0
    };
    let whole_s = whole.itrunc() catch (e) {
        _ => 0
    };
    whole_s.to_string()
        + "."
        + (
            if (frac_s < 10) {
                "0"
            } else {
                ""
            }
        )
        + frac_s.to_string()
        + "%"
}

function benchmark(
    name: string,
    run_count: int,
    func: () -> void,
    col_width: int[],
    compare_to: float? = null,
) -> float {
    let time_taken = _timeit_repeat(func, run_count, 5);
    let time_suffix = " s";
    let line = _rjust(name, col_width[0])
        + " | "
        + _rjust(_fmt_3g(time_taken), col_width[1] - time_suffix.length())
        + time_suffix;
    if (compare_to == null) {
        line = line + " | baseline (100%)";
    } else {
        let delta = compare_to / time_taken;
        line = line + " | " + _fmt_percent(delta);
    }
    baml.io.println(line);
    time_taken
}

function run(run_count: int) -> null {
    let data_path = "benchmark/data.toml";
    let test_data = baml.fs.read(data_path);

    let col_width = [10, 10, 28];
    let col_head = ["parser", "exec time", "performance (more is better)"];
    baml.io.println("Parsing data.toml " + run_count.to_string() + " times:");
    baml.io.println(
        "-".repeat(col_width[0])
            + "---"
            + "-".repeat(col_width[1])
            + "---"
            + "-".repeat(col_width[2]),
    );
    baml.io.println(
        _rjust(col_head[0], col_width[0])
            + " | "
            + _rjust(col_head[1], col_width[1])
            + " | "
            + col_head[2],
    );
    baml.io.println(
        "-".repeat(col_width[0])
            + "-+-"
            + "-".repeat(col_width[1])
            + "-+-"
            + "-".repeat(col_width[2]),
    );
    let baseline = benchmark(
        "baml.toml",
        run_count,
        () -> void {
            let _ = baml.toml.Table.parse(test_data);
        },
        col_width,
    );
    benchmark(
        "tomli",
        run_count,
        () -> void {
            let _ = root.tomli.loads(test_data);
        },
        col_width,
        compare_to = baseline,
    );
    null
}

function main() -> null {
    run(20)
}
