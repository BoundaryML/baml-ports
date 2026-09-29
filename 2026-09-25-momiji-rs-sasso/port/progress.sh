#!/bin/sh
# Stubs left per BAML file, plus the project's compile error count.
cd "$(dirname "$0")/.."
total=0
for f in $(find baml_src -name '*.baml' | grep -v ns_std | sort); do
  n=$(grep -c 'root.std.todo' "$f")
  total=$((total + n))
  [ "$1" = "-v" ] && [ "$n" -gt 0 ] && printf '%5d  %s\n' "$n" "$f"
done
errs=$(RUST_MIN_STACK=1073741824 baml check --no-progress --diagnostic-format concise 2>&1 | grep -c ': \[E')
lines=$(find baml_src -name '*.baml' | grep -v ns_std | xargs cat | wc -l)
echo "stubs left: $total   compile errors: $errs   baml lines: $lines"
