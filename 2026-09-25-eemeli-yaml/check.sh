#!/bin/bash
# Compile-check the project, showing only diagnostics from this project's files.
cd "$(dirname "$0")"; source env.sh
$B check 2>&1 | grep -v "^warning: using" | grep -E "error|^ " | grep -v -E "^(csv|iter|stream|ns_internal|ns_mcp)" | head -${1:-60}
