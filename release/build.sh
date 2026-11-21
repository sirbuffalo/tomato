#!/bin/sh
# Builds the release files in release/out/: tomato-VERSION.tar.gz (everything `install-native.sh` needs, with no Python)
# and latest.json (what `tomato update` reads). Upload the archive to a GitHub release tagged vVERSION and attach
# latest.json to the release too (tomato update falls back to it); site/build.sh copies it into site/. Usage: release/build.sh [ARCHIVE_URL]
set -e
root="$(cd "$(dirname "$0")/.." && pwd)"
version="$(cat "$root/VERSION")"
repo="${TOMATO_REPO:-sirbuffalo/tomato}"
url="${1:-https://github.com/$repo/releases/download/v$version/tomato-$version.tar.gz}"
out="${TOMATO_RELEASE_OUT:-$root/release/out}"; stage="$out/tomato-$version"
rm -rf "$out"; mkdir -p "$stage/native" "$stage/runtime" "$stage/std" "$stage/compiler/bootstrap"
cp "$root/VERSION" "$root/install-native.sh" "$stage/"
cp "$root/native/tomato" "$root/native/tomato-repl" "$root/native/tomato-jsc.js" "$stage/native/"
mkdir -p "$stage/site/wasm"
cp "$root/site/wasm/tomatoc.wasm" "$root/site/wasm/runtime.wasm" "$root/site/wasm/wasi.js" "$root/site/wasm/llvm.js" "$root/site/wasm/tomato.js" "$stage/site/wasm/"
cp "$root/runtime/tomato_rt.c" "$stage/runtime/"
cp "$root/std/"*.tom "$stage/std/"
cp "$root/compiler/bootstrap/tomatoc.ll" "$stage/compiler/bootstrap/"
cp -R "$root/examples" "$stage/examples"
tar -czf "$out/tomato-$version.tar.gz" -C "$out" "tomato-$version"
rm -rf "$stage"
sum="$(shasum -a 256 "$out/tomato-$version.tar.gz" | cut -d' ' -f1)"
printf '{\n  "version": "%s",\n  "url": "%s",\n  "sha256": "%s"\n}\n' "$version" "$url" "$sum" > "$out/latest.json"
echo "built $out/tomato-$version.tar.gz and $out/latest.json"
