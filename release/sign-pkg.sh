#!/bin/sh
# Signs, notarizes and staples a tomato installer package. Run it ON a Mac that holds the Developer ID Installer identity
# and a stored notarytool login (the build Mac has neither; see docs/releasing.md for the copy-to-a-signing-Mac procedure).
# Usage: release/sign-pkg.sh IN.pkg OUT.pkg
#   TOMATO_PKG_SIGN        installer identity   (default: Developer ID Installer: Davis McDowell (39BK8TGQ26))
#   TOMATO_NOTARY_PROFILE  notarytool keychain profile (default: tomato-notary; created once with
#                          `xcrun notarytool store-credentials tomato-notary`, so no password is ever written down)
#   TOMATO_APP_SIGN        code-signing identity for the binaries inside the package (default: Developer ID Application: Davis McDowell (39BK8TGQ26)).
#                          Apple notarization rejects unsigned Mach-O files, so every one in the payload (tomatoc) is re-signed with the
#                          hardened runtime and a secure timestamp before the package itself is signed. This needs a Developer ID *Application*
#                          certificate, a different certificate from the Installer one.
#   TOMATO_SKIP_NOTARIZE   testing only: sign but do not notarize or staple (the result is not distributable; release.sh allows it only with --dry-run)
#   TOMATO_LATEST_JSON     optional: a latest.json whose pkg_sha256 is rewritten to the signed package's hash
# Prints the SHA-256 of OUT.pkg. On a notarization rejection it prints Apple's log and exits non-zero.
set -e
[ "$(uname)" = Darwin ] || { echo "error: signing needs a Mac" >&2; exit 1; }
[ $# -eq 2 ] || { echo "usage: $0 IN.pkg OUT.pkg" >&2; exit 2; }
in="$1"; out="$2"
sign="${TOMATO_PKG_SIGN:-Developer ID Installer: Davis McDowell (39BK8TGQ26)}"
profile="${TOMATO_NOTARY_PROFILE:-tomato-notary}"
[ "$in" != "$out" ] || { echo "error: IN and OUT must differ" >&2; exit 2; }
appsign="${TOMATO_APP_SIGN:-Developer ID Application: Davis McDowell (39BK8TGQ26)}"
rm -f "$out"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
pkgutil --expand-full "$in" "$work/x"
find "$work/x" -type f -exec file {} + | grep -v '(for architecture' | sed -n 's/: *Mach-O.*//p' | sort -u > "$work/bins"
[ -s "$work/bins" ] || { echo "error: no Mach-O binary found in the package to sign" >&2; exit 1; }
while IFS= read -r bin; do
  codesign --force --options runtime --timestamp --sign "$appsign" "$bin"
  codesign --verify --strict "$bin"
done < "$work/bins"
# Rebuild with pkgbuild, not --flatten-full: flatten-full records the signer's own owner (davis:staff), pkgbuild forces root:wheel.
ver="$(sed -n 's/.*<pkg-ref id="com.davismcd.tomato" version="\([^"]*\)".*/\1/p' "$work/x/Distribution")"
[ -n "$ver" ] || { echo "error: cannot read the package version from Distribution" >&2; exit 1; }
mkdir "$work/parts"
pkgbuild --root "$work/x/component.pkg/Payload" --scripts "$work/x/component.pkg/Scripts" --identifier com.davismcd.tomato --version "$ver" --install-location / --ownership recommended "$work/parts/component.pkg" >/dev/null
productbuild --distribution "$work/x/Distribution" --package-path "$work/parts" "$work/app-signed.pkg" >/dev/null
# the result installs with these owners; they must be root:wheel
pkgutil --expand "$work/app-signed.pkg" "$work/chk"
listing="$(lsbom -p MUGsf "$work"/chk/*.pkg/Bom 2>/dev/null)"
[ -n "$listing" ] || { echo "error: cannot list the repacked payload" >&2; exit 1; }
bad="$(printf '%s\n' "$listing" | awk -F'\t' '$2 != "root" || $3 != "wheel" {print $NF}' | head -3)"
[ -z "$bad" ] || { echo "error: repacked payload is not owned by root:wheel, e.g. $bad" >&2; exit 1; }
tmp="$work/final.pkg"   # OUT appears only once notarized, stapled and validated
productsign --sign "$sign" "$work/app-signed.pkg" "$tmp"
pkgutil --check-signature "$tmp"
if [ -n "$TOMATO_SKIP_NOTARIZE" ]; then   # testing only (release/release.sh --dry-run --skip-notarize): signed but NOT notarized, so not distributable
  mv "$tmp" "$out"; echo "signed $out, NOT notarized ($(shasum -a 256 "$out" | cut -d' ' -f1))"; exit 0
fi
log="$work/notary.plist"
if ! xcrun notarytool submit "$tmp" --keychain-profile "$profile" --wait --output-format plist >"$log" 2>&1; then cat "$log" >&2; echo "error: notarytool submit failed" >&2; exit 1; fi
status="$(/usr/libexec/PlistBuddy -c 'Print :status' "$log" 2>/dev/null || true)"
id="$(/usr/libexec/PlistBuddy -c 'Print :id' "$log" 2>/dev/null || true)"
if [ "$status" != "Accepted" ]; then
  echo "error: notarization ${status:-failed} (submission $id)" >&2
  [ -n "$id" ] && xcrun notarytool log "$id" --keychain-profile "$profile" >&2 || cat "$log" >&2
  exit 1
fi
echo "notarized (submission $id)"
xcrun stapler staple "$tmp"
xcrun stapler validate "$tmp"
spctl --assess --type install -vv "$tmp"
mv "$tmp" "$out"
sum="$(shasum -a 256 "$out" | cut -d' ' -f1)"
if [ -n "$TOMATO_LATEST_JSON" ] && [ -f "$TOMATO_LATEST_JSON" ]; then
  sed "s/\"pkg_sha256\": *\"[0-9a-f]*\"/\"pkg_sha256\": \"$sum\"/" "$TOMATO_LATEST_JSON" > "$TOMATO_LATEST_JSON.tmp" && mv "$TOMATO_LATEST_JSON.tmp" "$TOMATO_LATEST_JSON"
fi
echo "signed $out ($sum)"
