#!/bin/sh
# Rebuilds compiler/bootstrap/tomatoc.ll from compiler/src/ using the compiler it already holds (no Python needed).
# the old IR builds a compiler, which compiles the current sources; repeating once more checks it is a fixed point.
# An already-current file is detected after one compiler build (see below).
set -e
root="$(cd "$(dirname "$0")/../.." && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
cd "$root"
# Each pass builds a compiler from a pass's IR (the IR is compiled in parallel parts by build-object.sh, the runtime is
# compiled once, alongside it) and uses it to compile the sources. The first pass may still print text from the old
# sources (such as a renamed path in a comment), so repeat until two consecutive IRs agree. The starting IR counts as the
# first of those: when the sources compile to exactly the file it already holds, that file is a fixed point and no
# second compiler is built.
cc() {  # cc <out> <ir>
  compiler/bootstrap/build-object.sh "$1.o" "$2" || return 1
  if [ -n "$rt_pid" ]; then wait "$rt_pid"; rt_pid=""; fi
  clang -O1 -Wno-override-module -o "$1" "$1.o" "$tmp/rt.o" -pthread -lm
}
clang -O1 -pthread -Wno-override-module -c -o "$tmp/rt.o" runtime/tomato_rt.c & rt_pid=$!
cc "$tmp/c0" compiler/bootstrap/tomatoc.ll
prev="$tmp/c0"; last="compiler/bootstrap/tomatoc.ll"; n=0
while [ $n -lt 4 ]; do
  n=$((n + 1))
  "$prev" compiler/src/ctool.tom compile > "$tmp/ir$n.ll"
  if cmp -s "$last" "$tmp/ir$n.ll"; then
    if [ "$n" = 1 ]; then
      echo "compiler/bootstrap/tomatoc.ll is up to date"
    else
      cp "$tmp/ir$n.ll" compiler/bootstrap/tomatoc.ll
      echo "compiler/bootstrap/tomatoc.ll refreshed"
    fi
    exit 0
  fi
  cc "$tmp/c$n" "$tmp/ir$n.ll"
  prev="$tmp/c$n"; last="$tmp/ir$n.ll"
done
echo "the new compiler does not reproduce itself" >&2
exit 1
