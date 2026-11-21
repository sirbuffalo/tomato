#!/bin/sh
# Builds the release files in release/out/: tomato-VERSION.tar.gz (everything `install-native.sh` needs, with no Python)
# and latest.json (what `tomato update` reads). Upload the archive to a GitHub release tagged vVERSION and publish
# latest.json with the site (www/latest.json). Usage: release/build.sh [ARCHIVE_URL]
set -e
root="$(cd "$(dirname "$0")/.." && pwd)"
version="$(cat "$root/VERSION")"
repo="${TOMATO_REPO:-sirbuffalo/tomato}"
url="${1:-https://github.com/$repo/releases/download/v$version/tomato-$version.tar.gz}"
out="$root/release/out"; stage="$out/tomato-$version"
rm -rf "$out"; mkdir -p "$stage/native" "$stage/python/tomato/runtime" "$stage/python/tomato/std" "$stage/compiler/bootstrap"
cp "$root/VERSION" "$root/install-native.sh" "$stage/"
cp "$root/native/tomato" "$root/native/tomato-repl" "$stage/native/"
cp "$root/python/tomato/runtime/tomato_rt.c" "$stage/python/tomato/runtime/"
cp "$root/python/tomato/std/"*.tom "$stage/python/tomato/std/"
cp "$root/compiler/bootstrap/tomatoc.ll" "$stage/compiler/bootstrap/"
cp -R "$root/examples" "$stage/examples"
tar -czf "$out/tomato-$version.tar.gz" -C "$out" "tomato-$version"
rm -rf "$stage"
sum="$(shasum -a 256 "$out/tomato-$version.tar.gz" | cut -d' ' -f1)"
printf '{\n  "version": "%s",\n  "url": "%s",\n  "sha256": "%s"\n}\n' "$version" "$url" "$sum" > "$out/latest.json"
echo "built $out/tomato-$version.tar.gz and $out/latest.json"
