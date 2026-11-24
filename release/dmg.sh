#!/bin/sh
# Wraps the final (signed, notarized, stapled) installer package in a disk image, then signs, notarizes and staples the image
# itself. Run it ON a Mac that holds the Developer ID Application identity and the stored notarytool login, after
# release/sign-pkg.sh. The image holds exactly one file, tomato-VERSION.pkg, byte-identical to PKG.
# Usage: release/dmg.sh PKG OUT.dmg
#   TOMATO_APP_SIGN        identity that signs the image (default: Developer ID Application: Davis McDowell (39BK8TGQ26));
#                          a disk image is signed with codesign and the Application certificate, not the Installer one
#   TOMATO_NOTARY_PROFILE  notarytool keychain profile (default: tomato-notary)
#   TOMATO_SKIP_NOTARIZE   testing only: sign but do not notarize or staple (release.sh allows it only with --dry-run)
#   TOMATO_NO_SIGN         testing only: neither sign nor notarize (release.sh --dry-run --no-sign)
#   TOMATO_LATEST_JSON     optional: a latest.json that gets dmg_url and dmg_sha256 for the finished image
# Checks the result: hdiutil verify, codesign --verify --strict, stapler validate, spctl (open, primary signature), and
# mounts it read-only to compare the package inside with PKG and check that package's signature. Prints the SHA-256.
set -e
[ "$(uname)" = Darwin ] || { echo "error: the disk image is built on a Mac" >&2; exit 1; }
[ $# -eq 2 ] || { echo "usage: $0 PKG OUT.dmg" >&2; exit 2; }
pkg="$1"; out="$2"
[ -f "$pkg" ] || { echo "error: no package at $pkg" >&2; exit 1; }
case "$out" in *.dmg) ;; *) echo "error: OUT must end in .dmg" >&2; exit 2 ;; esac
appsign="${TOMATO_APP_SIGN:-Developer ID Application: Davis McDowell (39BK8TGQ26)}"
profile="${TOMATO_NOTARY_PROFILE:-tomato-notary}"
ver="$(basename "$pkg" .pkg)"; ver="${ver#tomato-}"; ver="${ver%.signed}"
printf %s "$ver" | grep -Eq '^[0-9]+(\.[0-9]+)+$' || { echo "error: cannot read the version from the package name $pkg (want tomato-VERSION.pkg)" >&2; exit 1; }
name="tomato-$ver.pkg"
rm -f "$out"
work="$(mktemp -d)"; mnt=""
cleanup() { [ -z "$mnt" ] || hdiutil detach -quiet "$mnt" 2>/dev/null || hdiutil detach -force -quiet "$mnt" 2>/dev/null || true; rm -rf "$work"; }
trap cleanup EXIT
# hdiutil sometimes fails with "Resource busy" or a timeout (often on a busy CI runner) and works a moment later
retry() { try=1; until "$@"; do [ "$try" -ge 3 ] && return 1; try=$((try + 1)); sleep 3; done; }
mkdir "$work/stage"; cp "$pkg" "$work/stage/$name"
tmp="$work/tomato-$ver.dmg"   # OUT appears only once signed, notarized, stapled and checked
retry hdiutil create -quiet -volname "Tomato $ver" -srcfolder "$work/stage" -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$tmp"
retry hdiutil verify -quiet "$tmp"
if [ -z "$TOMATO_NO_SIGN" ]; then
  codesign --force --timestamp --sign "$appsign" "$tmp"
  codesign --verify --strict -vv "$tmp"
  codesign -dv --verbose=4 "$tmp" 2>&1 | grep -q "Authority=$appsign" || { echo "error: the image is not signed by $appsign" >&2; exit 1; }
fi
status=skipped
if [ -z "$TOMATO_NO_SIGN" ] && [ -z "$TOMATO_SKIP_NOTARIZE" ]; then
  log="$work/notary.plist"
  if ! xcrun notarytool submit "$tmp" --keychain-profile "$profile" --wait --output-format plist >"$log" 2>&1; then cat "$log" >&2; echo "error: notarytool submit failed" >&2; exit 1; fi
  status="$(/usr/libexec/PlistBuddy -c 'Print :status' "$log" 2>/dev/null || true)"
  id="$(/usr/libexec/PlistBuddy -c 'Print :id' "$log" 2>/dev/null || true)"
  if [ "$status" != "Accepted" ]; then
    echo "error: notarization ${status:-failed} (submission $id)" >&2
    [ -n "$id" ] && xcrun notarytool log "$id" --keychain-profile "$profile" >&2 || cat "$log" >&2
    exit 1
  fi
  echo "notarized dmg (submission $id)"
  xcrun stapler staple "$tmp"
  xcrun stapler validate "$tmp"
  codesign --verify --strict "$tmp"
  spctl --assess --type open --context context:primary-signature -vv "$tmp"
fi
# the contents: exactly the package we were given, still signed (and, when notarized, still stapled)
mkdir "$work/mnt"; retry hdiutil attach -quiet -readonly -nobrowse -noautoopen -mountpoint "$work/mnt" "$tmp"; mnt="$work/mnt"
listing="$(ls "$mnt")"   # dot entries (.fseventsd and the like) are the file system's own
[ "$listing" = "$name" ] || { echo "error: the image should hold only $name, it holds: $(echo "$listing" | tr '\n' ' ')" >&2; exit 1; }
cmp -s "$mnt/$name" "$pkg" || { echo "error: the package in the image differs from $pkg" >&2; exit 1; }
if [ -z "$TOMATO_NO_SIGN" ]; then
  pkgutil --check-signature "$mnt/$name" > "$work/pkgsig.txt" || { cat "$work/pkgsig.txt" >&2; echo "error: the package in the image is not validly signed" >&2; exit 1; }
  if [ -z "$TOMATO_SKIP_NOTARIZE" ]; then xcrun stapler validate "$mnt/$name" > /dev/null || { echo "error: the package in the image is not stapled" >&2; exit 1; }; fi
fi
hdiutil detach -quiet "$mnt"; mnt=""
mv "$tmp" "$out"
sum="$(shasum -a 256 "$out" | cut -d' ' -f1)"
if [ -n "$TOMATO_LATEST_JSON" ] && [ -f "$TOMATO_LATEST_JSON" ]; then   # dmg_url sits next to url (the tarball), dmg_sha256 is this image's hash
  durl="$(sed -n 's/.*"url" *: *"\([^"]*\)\.tar\.gz".*/\1/p' "$TOMATO_LATEST_JSON").dmg"
  grep -v '"dmg_' "$TOMATO_LATEST_JSON" | sed '$d' | sed '$s/,*$/,/' > "$work/latest.json"
  printf '  "dmg_url": "%s",\n  "dmg_sha256": "%s"\n}\n' "$durl" "$sum" >> "$work/latest.json"
  cp "$work/latest.json" "$TOMATO_LATEST_JSON"
fi
case "$TOMATO_NO_SIGN$TOMATO_SKIP_NOTARIZE" in
  "") echo "signed, notarized and stapled $out ($sum)" ;;
  *) echo "built $out, NOT notarized ($sum)" ;;
esac
