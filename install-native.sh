#!/bin/sh
# Installs the `tomato` command that is built on the Tomato compiler written in Tomato. Needs only clang.
#   ./install-native.sh             build tomatoc from compiler/bootstrap/tomatoc.ll into ~/.tomato/native, link ~/.local/bin/tomato
# Override the locations with TOMATO_HOME and TOMATO_BIN.
set -e
th="${TOMATO_HOME:-$HOME/.tomato}"
home="$th/native"
bindir="${TOMATO_BIN:-$HOME/.local/bin}"
root="$(cd "$(dirname "$0")" && pwd)"
sha256() { if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$@"; else sha256sum "$@"; fi; }   # macOS has shasum, some Linux systems only sha256sum
command -v clang >/dev/null || { echo "clang is required (on a Mac: xcode-select --install)" >&2; exit 1; }
mkdir -p "$th" "$bindir"
# The install is never changed in place. The new one is built complete in a folder beside it ($th/.native.new.PID, the same
# file system), and only when everything is there does one rename put it where `native` is (see the swap below): a failure or an
# interrupt at any earlier point leaves the old install exactly as it was, and a `tomato run` at any moment sees one whole
# install, never a half-written compiler or a new compiler with the old std. Nothing in the old folder is written, so a running
# `tomatoc` (and a `tomato update` that is reading this install's own script) is not disturbed; its files are removed after the swap.
stage="$th/.native.new.$$"; old="$th/.native.old.$$"; ir_pid=""; job=""
# on any exit, error or signal: stop the compiles still running, remove the staged folder (and the old install, once swapped out),
# and put the old install back if a swap was cut short
cleanup() {
  trap '' INT TERM HUP
  kill $ir_pid $job 2>/dev/null || true
  wait 2>/dev/null || true
  if [ -e "$old" ] && [ ! -e "$home" ]; then mv "$old" "$home" 2>/dev/null || true; fi
  rm -rf "$stage" "$old"
}
trap cleanup EXIT
# (a background job of a script ignores SIGINT, so the compiles below are stopped with SIGTERM from cleanup; each runs through
# `run`, which waits for it, so that a signal ends this script at once instead of after the current compile)
trap 'exit 130' INT; trap 'exit 143' TERM; trap 'exit 129' HUP
run() { "$@" & job=$!; if wait "$job"; then job=""; else rc=$?; job=""; return $rc; fi; }
# leftovers of an installer that could not clean up (SIGKILL, a power cut): a folder of a process that is gone is removed, and an old
# install that was moved aside but never replaced (killed between the two renames of the fallback swap) is put back
for d in "$th"/.native.new.* "$th"/.native.old.*; do
  [ -d "$d" ] || continue
  kill -0 "${d##*.}" 2>/dev/null && continue
  case "$d" in */.native.old.*) [ -e "$home" ] || mv "$d" "$home" 2>/dev/null || true ;; esac
  rm -rf "$d"
done
mkdir "$stage" 2>/dev/null || { echo "error: cannot write to $th: the install is replaced as a whole, so the folder needs to be writable" >&2; exit 1; }
mkdir -p "$stage/bin" "$stage/runtime" "$stage/std" "$stage/wasm/std" "$stage/.build"
echo "building the Tomato compiler from compiler/bootstrap/tomatoc.ll ..."
# The compiler (13 MB of LLVM IR, most of the time) and the runtime are compiled at the same time and then linked: the same program as
# one clang command, built in less time.
objs="$stage/.build"
"$root/compiler/bootstrap/build-object.sh" "$objs/tomatoc.o" & ir_pid=$!
run clang -O1 -pthread -Wno-override-module -c -o "$objs/rt.o" "$root/runtime/tomato_rt.c"
wait "$ir_pid" || { ir_pid=""; exit 1; }
ir_pid=""
run clang -O1 -Wno-override-module -o "$stage/bin/tomatoc" "$objs/tomatoc.o" "$objs/rt.o" -pthread -lm $([ "$(uname)" = Linux ] && echo -ldl)
rm -rf "$objs"
cp "$root/runtime/tomato_rt.c" "$root/runtime/tomato_inline.ll" "$stage/runtime/"
cp "$root/std/"*.tom "$root/std/errors.txt" "$stage/std/"; cp -R "$root/std/builtin" "$stage/std/"
cp -R "$root/examples" "$stage/examples"
cp "$root/VERSION" "$stage/VERSION"
for f in tomato tomato-repl rtcache.sh; do cp "$root/native/$f" "$stage/bin/$f" && chmod +x "$stage/bin/$f"; done
cp "$root/site/wasm/tomatoc.wasm" "$root/site/wasm/runtime.wasm" "$root/site/wasm/wasi.js" "$root/site/wasm/llvm.js" "$root/site/wasm/tomato.js" "$root/native/tomato-jsc.js" "$stage/wasm/"
cp "$root/std/"*.tom "$root/std/errors.txt" "$stage/wasm/std/"; cp -R "$root/std/builtin" "$stage/wasm/std/"
# the website's WebAssembly build is only used by the repl while it matches this compiler (it cannot be rebuilt without the WASI SDK)
if [ -f "$root/site/wasm/SOURCE.sha256" ] && [ "$(cat "$root/compiler/bootstrap/tomatoc.ll" "$root/runtime/tomato_rt.c" | sha256 | cut -d' ' -f1)" = "$(sed -n 1p "$root/site/wasm/SOURCE.sha256")" ]; then touch "$stage/wasm/current"; fi
# The repl's line editor (compiler/src/repledit.tom, with the lexer beside it), built with the staged tomato. It is optional: when it
# cannot be built the install goes on and the repl uses plain input, with a warning here that keeps the reason.
build_repl_edit() {
  ed="$stage/.edit"; mkdir -p "$ed" || return 1
  cp "$root/compiler/src/repledit.tom" "$root/compiler/src/lexer.tom" "$ed/" &&
    "$stage/bin/tomato" build "$ed/repledit.tom" -o "$stage/bin/tomato-repl-edit" --mode release > "$ed/log" 2>&1
  rc=$?; [ $rc = 0 ] || { tail -5 "$ed/log" >&2; rm -f "$stage/bin/tomato-repl-edit"; }
  rm -rf "$ed"; return $rc
}
echo "building the repl line editor ..."
run build_repl_edit || echo "warning: the repl line editor could not be built (the reason is above); the repl will use plain input" >&2
# the staged install must be whole and run before it replaces anything
[ -x "$stage/bin/tomatoc" ] && [ -x "$stage/bin/tomato" ] && "$stage/bin/tomato" version >/dev/null 2>&1 || { echo "error: the new install is incomplete: leaving the old one alone" >&2; exit 1; }
# The swap. With `mv --exchange` (GNU mv on Linux, renameat2) the two folders trade names in one step, so there is no moment without
# an install. Elsewhere (macOS) the old install is renamed away and the new one renamed into place: two renames in a row, during which
# `native` does not exist for a moment. Either way each rename is atomic, signals are ignored while it runs, and if the second rename
# fails the first is undone. A first install has nothing to swap.
trap '' INT TERM HUP
if [ ! -e "$home" ] && [ ! -L "$home" ]; then mv "$stage" "$home"
elif mv --exchange "$stage" "$home" 2>/dev/null; then :       # the staged folder now holds the old install: cleanup removes it
else
  mv "$home" "$old"
  mv "$stage" "$home" || { mv "$old" "$home"; echo "error: cannot put the new install in place: the old one is kept" >&2; exit 1; }
fi
trap 'exit 130' INT; trap 'exit 143' TERM; trap 'exit 129' HUP
rm -rf "$stage" "$old"
# an existing `tomato` that is not ours is kept as tomato.old rather than overwritten
cmd="$bindir/tomato"
if [ -e "$cmd" ] && [ ! -L "$cmd" ]; then
  mv "$cmd" "$bindir/tomato.old" && echo "kept the existing $cmd as $bindir/tomato.old"
fi
# a link that already resolves to this install is left alone: the package install keeps /usr/local/bin root-owned, so `tomato update` must not need to write there
if [ -L "$cmd" ] && [ "$cmd" -ef "$home/bin/tomato" ]; then :; else ln -sf "$home/bin/tomato" "$bindir/tomato"; fi
echo "installed to $home"
echo "linked $bindir/tomato"
case ":$PATH:" in *":$bindir:"*) ;; *) echo "add $bindir to your PATH to run 'tomato'" ;; esac
echo "try: tomato run $home/examples/compiled.tom main 12"
