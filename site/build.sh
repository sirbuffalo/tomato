#!/bin/sh
# Assembles the files GitHub Pages serves for tomato.davismcd.com into site/ (docs copied in, latest.json added).
# Run release/build.sh first so latest.json exists. Publish the site/ folder.
set -e
root="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$root/site/docs"
for f in specification decisions decision-inventory open-questions; do cp "$root/docs/$f.md" "$root/site/docs/$f.md"; done
sh "$root/site/examples.sh"
cp "$root/python/tomato/PROVISIONAL.md" "$root/site/docs/PROVISIONAL.md"
if [ -f "$root/release/out/latest.json" ]; then cp "$root/release/out/latest.json" "$root/site/latest.json"; fi
sed -i.bak "s/window.TOMATO_VERSION = \".*\"/window.TOMATO_VERSION = \"$(cat "$root/VERSION")\"/" "$root/site/config.js" && rm -f "$root/site/config.js.bak"
echo "site/ is ready to publish"
