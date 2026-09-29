#!/bin/sh
# Runs each minimal repro in its own throwaway BAML project and prints the
# compiler / runtime output. Usage: repros/run.sh [path-to-baml-cli]
BAML="${1:-$(cd "$(dirname "$0")/.." && pwd)/.tools/baml-cli}"
export BAML_AGENT_SKILL_CHECK=off
for f in "$(cd "$(dirname "$0")" && pwd)"/r*.baml; do
  tmp=$(mktemp -d)
  mkdir -p "$tmp/baml_src"
  printf '[package]\nname = "repro"\n' > "$tmp/baml.toml"
  cp "$f" "$tmp/baml_src/"
  echo "=== $(basename "$f")"
  (cd "$tmp" && "$BAML" check 2>&1 | grep -v "E0146\|^ *Finished\|internal BAML toolchain")
  entry=$(grep -o '^// run: .*' "$f" | sed 's|^// run: ||')
  if [ -n "$entry" ]; then
    (cd "$tmp" && "$BAML" run -e "$entry" 2>&1 | grep -v "internal BAML toolchain\|^  File" | tail -2)
  fi
  rm -rf "$tmp"
done
