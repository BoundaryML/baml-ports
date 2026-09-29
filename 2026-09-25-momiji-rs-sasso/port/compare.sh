#!/bin/sh
# Run the Rust sasso and the BAML port on the same arguments, from the same
# working directory, and compare stdout, stderr and exit status.
#   port/compare.sh <dir> [sasso args...]
PROJ="$(cd "$(dirname "$0")/.." && pwd)"
RUST="$PROJ/port/upstream/sasso/target/release/sasso"
dir="$1"; shift
cd "$dir" || exit 2
"$RUST" "$@" > .rust.out 2> .rust.err < "${STDIN:-/dev/null}"; rc=$?
RUST_MIN_STACK=1073741824 baml run --project "$PROJ" main -- "$@" > .baml.out 2> .baml.err.raw < "${STDIN:-/dev/null}"; bc=$?
grep -v 'code is unformatted' .baml.err.raw > .baml.err
ok=1
[ "$rc" = "$bc" ] || { echo "exit: rust=$rc baml=$bc"; ok=0; }
cmp -s .rust.out .baml.out || { echo "stdout differs:"; diff .rust.out .baml.out | head -${LINES_SHOWN:-15}; ok=0; }
cmp -s .rust.err .baml.err || { echo "stderr differs:"; diff .rust.err .baml.err | head -${LINES_SHOWN:-15}; ok=0; }
[ $ok = 1 ] && echo "IDENTICAL (exit $rc, $(wc -c < .rust.out | tr -d ' ') bytes out, $(wc -c < .rust.err | tr -d ' ') bytes err)"
exit $((1 - ok))
