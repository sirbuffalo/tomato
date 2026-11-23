#!/bin/sh
# Installs the `tomato` command that is built on the Tomato compiler written in Tomato. Needs only clang.
#   ./install-native.sh             build tomatoc from compiler/bootstrap/tomatoc.ll into ~/.tomato/native, link ~/.local/bin/tomato
# Override the locations with TOMATO_HOME and TOMATO_BIN.
set -e
home="${TOMATO_HOME:-$HOME/.tomato}/native"
bindir="${TOMATO_BIN:-$HOME/.local/bin}"
root="$(cd "$(dirname "$0")" && pwd)"
sha256() { if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$@"; else sha256sum "$@"; fi; }   # macOS has shasum, some Linux systems only sha256sum
command -v clang >/dev/null || { echo "clang is required (on a Mac: xcode-select --install)" >&2; exit 1; }
mkdir -p "$home/bin" "$home/runtime" "$home/std" "$bindir"
echo "building the Tomato compiler from compiler/bootstrap/tomatoc.ll ..."
clang -O1 -Wno-override-module -o "$home/bin/tomatoc" "$root/compiler/bootstrap/tomatoc.ll" "$root/runtime/tomato_rt.c" -lm $([ "$(uname)" = Linux ] && echo -ldl)
cp "$root/runtime/tomato_rt.c" "$home/runtime/"
rm -rf "$home/std"; mkdir -p "$home/std"; cp "$root/std/"*.tom "$root/std/errors.txt" "$home/std/"
rm -rf "$home/examples"; cp -R "$root/examples" "$home/examples"
cp "$root/VERSION" "$home/VERSION"
# copy over a temporary name and rename, so a running `tomato update` (a shell script reading this very file) is never
# rewritten in place
for f in tomato tomato-repl; do cp "$root/native/$f" "$home/bin/.$f.new" && chmod +x "$home/bin/.$f.new" && mv -f "$home/bin/.$f.new" "$home/bin/$f"; done
rm -rf "$home/wasm/std"; mkdir -p "$home/wasm/std"
cp "$root/site/wasm/tomatoc.wasm" "$root/site/wasm/runtime.wasm" "$root/site/wasm/wasi.js" "$root/site/wasm/llvm.js" "$root/site/wasm/tomato.js" "$root/native/tomato-jsc.js" "$home/wasm/"
cp "$root/std/"*.tom "$root/std/errors.txt" "$home/wasm/std/"
# the website's WebAssembly build is only used by the repl while it matches this compiler (it cannot be rebuilt without the WASI SDK)
rm -f "$home/wasm/current"
if [ -f "$root/site/wasm/SOURCE.sha256" ] && [ "$(cat "$root/compiler/bootstrap/tomatoc.ll" "$root/runtime/tomato_rt.c" | sha256 | cut -d' ' -f1)" = "$(sed -n 1p "$root/site/wasm/SOURCE.sha256")" ]; then touch "$home/wasm/current"; fi
chmod +x "$home/bin/tomato"
# an existing `tomato` that is not ours is kept as tomato.old rather than overwritten
old="$bindir/tomato"
if [ -e "$old" ] && [ ! -L "$old" ]; then
  mv "$old" "$bindir/tomato.old" && echo "kept the existing $old as $bindir/tomato.old"
fi
# a link that already resolves to this install is left alone: the package install keeps /usr/local/bin root-owned, so `tomato update` must not need to write there
if [ -L "$old" ] && [ "$old" -ef "$home/bin/tomato" ]; then :; else ln -sf "$home/bin/tomato" "$bindir/tomato"; fi
echo "installed to $home"
echo "linked $bindir/tomato"
case ":$PATH:" in *":$bindir:"*) ;; *) echo "add $bindir to your PATH to run 'tomato'" ;; esac
echo "try: tomato run $home/examples/compiled.tom main 12"
