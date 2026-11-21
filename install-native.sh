#!/bin/sh
# Installs the `tomato` command that is built on the Tomato compiler written in Tomato. Needs only clang.
#   ./install-native.sh             build tomatoc from compiler/bootstrap/tomatoc.ll into ~/.tomato/native, link ~/.local/bin/tomato
# Override the locations with TOMATO_HOME and TOMATO_BIN.
set -e
home="${TOMATO_HOME:-$HOME/.tomato}/native"
bindir="${TOMATO_BIN:-$HOME/.local/bin}"
root="$(cd "$(dirname "$0")" && pwd)"
command -v clang >/dev/null || { echo "clang is required (on a Mac: xcode-select --install)" >&2; exit 1; }
mkdir -p "$home/bin" "$home/runtime" "$home/std" "$bindir"
echo "building the Tomato compiler from compiler/bootstrap/tomatoc.ll ..."
clang -O1 -Wno-override-module -o "$home/bin/tomatoc" "$root/compiler/bootstrap/tomatoc.ll" "$root/runtime/tomato_rt.c" -lm
cp "$root/runtime/tomato_rt.c" "$home/runtime/"
rm -rf "$home/std"; mkdir -p "$home/std"; cp "$root/std/"*.tom "$home/std/"
rm -rf "$home/examples"; cp -R "$root/examples" "$home/examples"
cp "$root/VERSION" "$home/VERSION"
cp "$root/native/tomato" "$root/native/tomato-repl" "$home/bin/"
mkdir -p "$home/wasm/std"
cp "$root/site/wasm/tomatoc.wasm" "$root/site/wasm/runtime.wasm" "$root/site/wasm/wasi.js" "$root/site/wasm/llvm.js" "$root/site/wasm/tomato.js" "$root/native/tomato-jsc.js" "$home/wasm/"
cp "$root/std/"*.tom "$home/wasm/std/"
chmod +x "$home/bin/tomato"
# an existing `tomato` that is not ours is kept as tomato.old rather than overwritten
old="$bindir/tomato"
if [ -e "$old" ] && [ ! -L "$old" ]; then
  mv "$old" "$bindir/tomato.old" && echo "kept the existing $old as $bindir/tomato.old"
fi
ln -sf "$home/bin/tomato" "$bindir/tomato"
echo "installed to $home"
echo "linked $bindir/tomato"
case ":$PATH:" in *":$bindir:"*) ;; *) echo "add $bindir to your PATH to run 'tomato'" ;; esac
echo "try: tomato run $home/examples/compiled.tom main 12"
