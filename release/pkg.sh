#!/bin/sh
# Builds release/out/tomato-VERSION.pkg: a macOS installer that needs no build step at install time. It ships a universal
# (arm64 + x86_64) tomatoc, installs into /usr/local/lib/tomato/native (the same layout install-native.sh makes, so
# `tomato update` keeps working) and links /usr/local/bin/tomato. Programs still need clang to compile (Xcode command line tools).
# The package is always unsigned here; release/sign-pkg.sh signs and notarizes it (see docs/releasing.md).
# Usage: release/pkg.sh   (macOS only; needs clang, lipo, pkgbuild, productbuild; run release/build.sh first so latest.json lists the package)
set -e
root="$(cd "$(dirname "$0")/.." && pwd)"
version="$(cat "$root/VERSION")"
out="${TOMATO_RELEASE_OUT:-$root/release/out}"
[ "$(uname)" = Darwin ] || { echo "error: the .pkg is built on a Mac" >&2; exit 1; }
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
trap 'exit 130' INT; trap 'exit 143' TERM; trap 'exit 129' HUP      # (dash skips an EXIT trap on a signal)
payload="$work/payload"; mkdir -p "$payload/usr/local/bin" "$out"
# the usual install layout, into the payload
TOMATO_HOME="$payload/usr/local/lib/tomato" TOMATO_BIN="$work/unused" sh "$root/install-native.sh" >/dev/null
rm -rf "$work/unused" "$payload/usr/local/lib/tomato/native/bin/tomatoc"
# universal compiler, built from the checked-in IR
for arch in arm64 x86_64; do
  clang -arch "$arch" -O1 -Wno-override-module -o "$work/tomatoc.$arch" "$root/compiler/bootstrap/tomatoc.ll" "$root/runtime/tomato_rt.c" -pthread -lm
done
lipo -create "$work/tomatoc.arm64" "$work/tomatoc.x86_64" -output "$payload/usr/local/lib/tomato/native/bin/tomatoc"
ln -s ../lib/tomato/native/bin/tomato "$payload/usr/local/bin/tomato"
# scripts: keep a foreign `tomato`, and hand the folder to the person installing so `tomato update` needs no sudo
mkdir -p "$work/scripts"
cat > "$work/scripts/preinstall" <<'PRE'
#!/bin/sh
t="$3/usr/local/bin/tomato"
if [ -e "$t" ] && [ ! -L "$t" ]; then mv "$t" "$t.old"; fi
exit 0
PRE
cat > "$work/scripts/postinstall" <<'POST'
#!/bin/sh
u="$(stat -f %Su /dev/console 2>/dev/null || true)"
case "$u" in ""|root) ;; *) chown -R "$u" "$3/usr/local/lib/tomato" 2>/dev/null || true ;; esac
exit 0
POST
chmod +x "$work/scripts/preinstall" "$work/scripts/postinstall"
pkgbuild --root "$payload" --identifier com.davismcd.tomato --version "$version" --install-location / --scripts "$work/scripts" "$work/component.pkg" >/dev/null
cat > "$work/dist.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="1">
  <title>Tomato $version</title>
  <options customize="never" require-scripts="false" hostArchitectures="arm64,x86_64"/>
  <domains enable_anywhere="false" enable_localSystem="true"/>
  <choices-outline><line choice="default"/></choices-outline>
  <choice id="default" title="Tomato"><pkg-ref id="com.davismcd.tomato"/></choice>
  <pkg-ref id="com.davismcd.tomato" version="$version">component.pkg</pkg-ref>
</installer-gui-script>
XML
productbuild --distribution "$work/dist.xml" --package-path "$work" "$out/tomato-$version.pkg" >/dev/null
echo "built $out/tomato-$version.pkg ($(shasum -a 256 "$out/tomato-$version.pkg" | cut -d' ' -f1))"
# record the package in latest.json (run release/build.sh first): the download page reads pkg_url and pkg_sha256
if [ -f "$out/latest.json" ]; then
  psum="$(shasum -a 256 "$out/tomato-$version.pkg" | cut -d' ' -f1)"; purl="$(sed -n 's/.*"url" *: *"\([^"]*\)\.tar\.gz".*/\1/p' "$out/latest.json").pkg"
  grep -v '"pkg_' "$out/latest.json" | sed '$d' | sed '$s/$/,/' > "$work/latest.json"
  printf '  "pkg_url": "%s",\n  "pkg_sha256": "%s"\n}\n' "$purl" "$psum" >> "$work/latest.json"
  cp "$work/latest.json" "$out/latest.json"
fi
