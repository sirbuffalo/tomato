# Releasing

1. `release/build.sh` builds `release/out/tomato-VERSION.tar.gz` and `latest.json`; `release/pkg.sh` (a Mac) adds the unsigned `tomato-VERSION.pkg` and its `pkg_*` fields.
2. Sign and notarize the package (below), then use the signed, stapled package as the release asset. `pkg_sha256` in `latest.json` must be the hash of that final file.
3. Publish: `gh release create vVERSION release/out/tomato-VERSION.tar.gz release/out/tomato-VERSION.pkg release/out/latest.json`, then commit `site/latest.json`. For an existing release, `gh release upload vVERSION FILE --clobber` and update `site/latest.json`; check that the downloaded asset's `shasum -a 256` equals the `pkg_sha256` there.

## Signing and notarizing the package

`release/sign-pkg.sh IN.pkg OUT.pkg` does the whole job and must run on a Mac that holds the signing certificates and the notary login. The build Mac has none of them (the private keys never leave Davis's MacBook Pro), so the package is copied there and back.

Environment (defaults shown):

- `TOMATO_PKG_SIGN`: `Developer ID Installer: Davis McDowell (39BK8TGQ26)`, signs the package.
- `TOMATO_APP_SIGN`: `Developer ID Application: Davis McDowell (39BK8TGQ26)`, signs the Mach-O files inside (`tomatoc`) with the hardened runtime and a secure timestamp. Apple rejects the package otherwise (status 4000: "The binary is not signed", "no secure timestamp", "hardened runtime not enabled").
- `TOMATO_NOTARY_PROFILE`: `tomato-notary`, a keychain profile made once with `xcrun notarytool store-credentials tomato-notary` (Apple ID and app-specific password live in the keychain; never write them anywhere).
- `TOMATO_LATEST_JSON`: optional path of a `latest.json` to update with the signed package's hash.

It runs `codesign` on each binary, `productsign`, `pkgutil --check-signature`, `notarytool submit --wait` (on rejection it prints `notarytool log` and fails), `stapler staple`, `stapler validate`, `spctl --assess --type install -vv`, and prints the final SHA-256.

**On the signing Mac itself:** `release/pkg.sh && release/sign-pkg.sh release/out/tomato-VERSION.pkg /tmp/tomato-VERSION.signed.pkg`.

**Agent-driven, from the build Mac (byre client `clitWDw4nYaqr3` is the MacBook Pro):**

1. Build on the server: `release/build.sh && release/pkg.sh`.
2. `copy` `release/out/tomato-VERSION.pkg` and `release/sign-pkg.sh` to `~/Library/Caches/tomato-release/` on the MacBook.
3. `bash` on the MacBook: `cd ~/Library/Caches/tomato-release && sh sign-pkg.sh tomato-VERSION.pkg tomato-VERSION.signed.pkg` (check the exit status, not a piped tail).
4. `copy` the signed file back to `release/out/tomato-VERSION.pkg`, then set `pkg_sha256` in `release/out/latest.json` to `shasum -a 256` of it.
5. Test: `pkgutil --expand-full` the signed file into a temp folder and check that `Scripts/preinstall` and `Scripts/postinstall` in the component are still executable, that `usr/local/bin/tomato` is still a symlink to `../lib/tomato/native/bin/tomato`, that `Distribution` still lists `component.pkg` at the right version, that `lsbom -p MUGsf` on the component `Bom` shows root and wheel for every entry (sign-pkg.sh rebuilds the component with `pkgbuild --ownership recommended` because `pkgutil --flatten-full` records the signer's own owner, and fails if any entry is not root:wheel), and that `tomato version` runs from `usr/local/lib/tomato/native/bin/` there. The expand and rebuild round trip in sign-pkg.sh produced the notarized v0.49 package (Accepted); for extra assurance also install once into a temp volume (`sudo installer -pkg FILE -target /Volumes/TEMP`) if one is available.

Status: done. The Developer ID Application certificate, the Installer certificate and the notary login all exist on the MacBook Pro. The published v0.49 package was re-signed with `sign-pkg.sh` (the `tomatoc` binary signed with the hardened runtime and a secure timestamp), notarized (Accepted), stapled, and passes `stapler validate` and `spctl -a -vv -t install`.
