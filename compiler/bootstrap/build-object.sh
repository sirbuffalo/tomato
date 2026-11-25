#!/bin/sh
# Compile the canonical bootstrap IR to one object file: in parallel parts, then combined for the native link.
# Needs only POSIX tools and clang; the IR itself remains the fixed-point artifact. If the split build fails for any
# reason (an awk or linker that behaves differently, an IR shape split.awk does not know), the IR is compiled whole,
# as a single clang process, which is slower but is the build the split must be equivalent to.
set -u
root=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
out=$1
ir=${2:-$root/compiler/bootstrap/tomatoc.ll}
# Test-only: tests/run.sh hands the installers the object it has already built from this IR, so the 13 MB is not
# compiled several times. It is named TEST so a stray variable in a user's environment cannot select another object.
if [ -n "${TOMATO_TEST_BOOTSTRAP_OBJECT:-}" ]; then
  cp "$TOMATO_TEST_BOOTSTRAP_OBJECT" "$out"
  exit $?
fi
tmp=$(mktemp -d) || exit 1
pids=""
# A signal must end the script (a trap that returns would continue into the slow fallback), stopping the part compiles first.
trap 'rm -rf "$tmp"' EXIT
trap 'kill $pids 2>/dev/null; exit 1' HUP INT TERM
build_split() {
  awk -v parts=8 -v dir="$tmp" -f "$root/compiler/bootstrap/split.awk" "$ir" "$ir" || return 1
  for n in 0 1 2 3 4 5 6 7; do
    clang -O1 -w -c "$tmp/part$n.ll" -o "$tmp/part$n.o" &
    pids="$pids $!"
  done
  failed=0
  for pid in $pids; do wait "$pid" || failed=1; done
  [ "$failed" = 0 ] || return 1
  clang -r -nostdlib -o "$out" "$tmp"/part*.o
}
if build_split; then exit 0; fi
echo "build-object.sh: the split build failed; compiling the IR as one module" >&2
clang -O1 -w -c "$ir" -o "$out"
