#!/bin/sh
# Installs the `tomato` command that is built on the Tomato compiler written in Tomato. Needs only clang.
#   ./install-native.sh             build tomatoc from compiler/bootstrap/tomatoc.ll into ~/.tomato/native, link ~/.local/bin/tomato
# Override the locations with TOMATO_HOME and TOMATO_BIN. The Python version stays available as `tomato-py`.
set -e
home="${TOMATO_HOME:-$HOME/.tomato}/native"
bindir="${TOMATO_BIN:-$HOME/.local/bin}"
root="$(cd "$(dirname "$0")" && pwd)"
command -v clang >/dev/null || { echo "clang is required (on a Mac: xcode-select --install)" >&2; exit 1; }
mkdir -p "$home/bin" "$home/runtime" "$home/std" "$bindir"
echo "building the Tomato compiler from compiler/bootstrap/tomatoc.ll ..."
clang -O1 -Wno-override-module -o "$home/bin/tomatoc" "$root/compiler/bootstrap/tomatoc.ll" "$root/python/tomato/runtime/tomato_rt.c" -lm
cp "$root/python/tomato/runtime/tomato_rt.c" "$home/runtime/"
rm -rf "$home/std"; mkdir -p "$home/std"; cp "$root/python/tomato/std/"*.tom "$home/std/"
rm -rf "$home/examples"; cp -R "$root/examples" "$home/examples"
cp "$root/VERSION" "$home/VERSION"
cp "$root/native/tomato" "$root/native/tomato-repl" "$home/bin/"
chmod +x "$home/bin/tomato"
# keep an existing Python command reachable as tomato-py
old="$bindir/tomato"
if [ -L "$old" ]; then
  target="$(readlink "$old")"
  case "$target" in /*) ;; *) target="$(cd "$bindir" && cd "$(dirname "$target")" && pwd)/$(basename "$target")" ;; esac
  case "$target" in */native/bin/tomato) ;; *) ln -sf "$target" "$bindir/tomato-py" ;; esac
elif [ -e "$old" ]; then
  mv "$old" "$bindir/tomato.old" && echo "kept the existing $old as $bindir/tomato.old"
fi
ln -sf "$home/bin/tomato" "$bindir/tomato"
echo "installed to $home"
echo "linked $bindir/tomato"
case ":$PATH:" in *":$bindir:"*) ;; *) echo "add $bindir to your PATH to run 'tomato'" ;; esac
echo "try: tomato run $home/examples/compiled.tom main 12"
