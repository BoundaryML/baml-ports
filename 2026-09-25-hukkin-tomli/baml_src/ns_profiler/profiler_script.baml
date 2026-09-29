// BAML port of `profiler/profiler_script.py`.
//
// A script for profiling.
//
// The original is driven by `tox -e profile` (cProfile + a flame graph).
// BAML has no user-facing profiler hook, so this is just the workload:
// run it with `baml run profiler.main` under an external (sampling) profiler.
// The loop count is lowered from 1000 because the BAML port is much slower
// than CPython; pass `--times N` via `baml run --function profiler.run`.
// `Path(__file__).parent.parent / "benchmark" / "data.toml"` is resolved
// relative to the working directory (no `__file__` in BAML).

function run(times: int) -> null {
    let benchmark_toml = baml.fs.read("benchmark/data.toml");

    // Run this a few times to emphasize over imports and other overhead above.
    for (let i = 0; i < times; i += 1) {
        root.tomli.loads(benchmark_toml);
    }
    null
}

function main() -> null {
    run(20)
}
