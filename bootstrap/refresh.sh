#!/bin/sh
# Rebuilds bootstrap/tomatoc.ll from selfhost/ using the compiler it already holds (no Python needed):
# the old IR builds a compiler, which compiles the current sources; repeating once more checks it is a fixed point.
set -e
root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
cd "$root"
cc() { clang -O1 -Wno-override-module -o "$1" "$2" tomato/runtime/tomato_rt.c -lm; }
cc "$tmp/c0" bootstrap/tomatoc.ll
"$tmp/c0" selfhost/ctool.tom compile > "$tmp/c1.ll"
cc "$tmp/c1" "$tmp/c1.ll"
"$tmp/c1" selfhost/ctool.tom compile > "$tmp/c2.ll"
cmp "$tmp/c1.ll" "$tmp/c2.ll" || { echo "the new compiler does not reproduce itself" >&2; exit 1; }
cp "$tmp/c2.ll" bootstrap/tomatoc.ll
rm -rf "$tmp"
echo "bootstrap/tomatoc.ll refreshed"
