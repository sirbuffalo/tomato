#!/bin/sh
# Rebuilds compiler/bootstrap/tomatoc.ll from compiler/src/ using the compiler it already holds (no Python needed).
# the old IR builds a compiler, which compiles the current sources; repeating once more checks it is a fixed point.
set -e
root="$(cd "$(dirname "$0")/../.." && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
cd "$root"
cc() { clang -O1 -Wno-override-module -o "$1" "$2" runtime/tomato_rt.c -lm; }
# Each pass builds a compiler from the previous pass's IR and uses it to compile the sources. The first pass may still
# print text from the old sources (such as a renamed path in a comment), so repeat until two passes agree.
cc "$tmp/c0" compiler/bootstrap/tomatoc.ll
prev="$tmp/c0"; last=""; n=0
while [ $n -lt 4 ]; do
  n=$((n + 1))
  "$prev" compiler/src/ctool.tom compile > "$tmp/ir$n.ll"
  if [ -n "$last" ] && cmp -s "$last" "$tmp/ir$n.ll"; then
    cp "$tmp/ir$n.ll" compiler/bootstrap/tomatoc.ll
    echo "compiler/bootstrap/tomatoc.ll refreshed"
    exit 0
  fi
  cc "$tmp/c$n" "$tmp/ir$n.ll"
  prev="$tmp/c$n"; last="$tmp/ir$n.ll"
done
echo "the new compiler does not reproduce itself" >&2
exit 1
