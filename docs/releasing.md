# Releasing

## One command: `release/release.sh`

Run it **on the Mac that holds the signing identities** (Davis's iMac; byre agents use the byre `bash` tool with that client, so no ssh is needed):

```sh
release/release.sh --dry-run        # everything except publishing: no tag, no GitHub release, no push
release/release.sh                  # the real release
```

It works in its own private clone (`~/.tomato-release/tomato`, never your own checkout; state and logs are next to it), so "clean, on main, equal to origin" is always true when it starts. It runs these steps in order, prints each one and stops at the first failure:

| step | what it does |
| --- | --- |
| `preflight` | tools (git, clang, Xcode signing tools, gh, and Go, Rust and python3 unless `--skip-bench`), both Developer ID identities **and a real test signature with each** (this catches a locked keychain), the `tomato-notary` profile (`notarytool history`), a WASI SDK, `gh auth` plus write permission on the repository, push access, then the clone is synced to `origin/main`, and the machine must be quiet (1- and 5-minute load average at most `--max-load`, default 2.0; it waits up to `--wait-quiet` seconds, default 900, then refuses). **All** missing things are listed together, each with its fix. |
| `version` | the next version (`--version X` to choose; a `VERSION` that was bumped ahead of its release is used as it is); refuses one that already has a tag or a GitHub release |
| `test` | `tests/run.sh` with the WASI SDK, so the wasm files are rebuilt and compared byte for byte. This runs **before** the version bump because the tests check `VERSION` against `site/latest.json` |
| `bump` | `VERSION` and `site/config.js` |
| `linux` | the same `tests/run.sh` and benchmarks on a Linux x86-64 machine (`--linux-host`, default `biggie.davismcd.com`) over ssh, on the commit being released (the tests see it before the bump, as the Mac tests do; the benchmarks run with the new version), plus callgrind instruction counts (`benchmarks/count.sh --guest`). Linux skips the wasm rebuild comparison because its SDK produces different bytes; the Mac test is canonical. Results come back to `benchmarks/results/linux-x86_64/`. It waits up to `--linux-wait` seconds (300) for that machine's load to drop to `--linux-max-load` (32), then goes on with a warning. **A Linux test failure stops the release** (continue with `--resume --ignore-linux-failures`); an unreachable host, missing tools or failed Linux benchmarks only warn and are recorded in the summary. `--no-linux` skips it |
| `bench` | `benchmarks/run.sh` (10 runs per program in a seeded shuffled order: Tomato, Go, Rust and Python; `--runs`, `--seed`), `benchmarks/count.sh` (deterministic instruction counts) when the Lima VM `tomato-count` exists (otherwise skipped with a note) |
| `snapshot` | `release/perf-snapshot.sh`: the `docs/performance.md` section, with Mac and Linux x86-64 columns side by side |
| `build` | `release/build.sh`, `release/pkg.sh` |
| `sign` | `release/sign-pkg.sh` (every Mach-O signed with the Application identity, hardened runtime and secure timestamp; package signed with the Installer identity; notarized with `tomato-notary`; stapled), then independent checks: `pkgutil --check-signature`, `stapler validate`, `spctl`, every Mach-O's signature, the package's scripts, symlink, `Distribution` version, and that the packaged `tomato version` runs; `pkg_sha256` in `latest.json` must equal the signed file's hash. Then `release/dmg.sh` puts that finished package into `tomato-X.dmg` and signs (Application identity), notarizes and staples the disk image; `dmg_sha256` in `latest.json` must equal its hash |
| `commit` | `site/build.sh` (so `site/latest.json` has the new version, `pkg_sha256` and `dmg_sha256`), consistency checks, and **one local commit** (`VERSION`, `site/`, `benchmarks/results/`, `docs/performance.md`; anything else changed stops the run) |
| `publish` | pushes the tag `vX` (the release commit), first requires a recorded passing Linux test run (or `--ignore-linux-failures`) and the signed disk image, then creates the GitHub release with the package, disk image, tarball and `latest.json`, **downloads them again** and compares sha256 (the public `pkg_url` and `dmg_url` too) |
| `push` | pushes the release commit to main. The site changes only now, after the assets are live and verified. `--no-push` leaves the commit in the clone and says so |
| `summary` | version, tests, benchmark ratios, notarization result, sha256 sums, release URL |

Options: `--dry-run`, `--skip-bench`, `--no-push`, `--version X`, `--seed N`, `--runs N`, `--max-load N`, `--wait-quiet SEC`, `--no-load-check`, `--no-linux`, `--linux-host H`, `--linux-tools DIR`, `--linux-max-load N`, `--linux-wait SEC`, `--ignore-linux-failures`, `--branch NAME`, `--origin URL`, `--work-dir DIR`, `--wasi-sdk DIR`, `--host USER@HOST` (optional: stream the script over ssh to another Mac and run it there; needs Remote Login and a key), `--unlock-keychain` (with `--host`: asks for that Mac's login password on your terminal), `--list-steps`, `--help`. Defaults can go in `release/release.conf` (git-ignored; see `release.conf.example`). `--dry-run` also accepts `--skip-notarize` (sign but do not notarize) and `--no-sign`, for a Mac that cannot sign or notarize yet; both are refused without `--dry-run` because an unsigned or un-notarized package must never be published.

**The Linux gate (read this before a real release):** a Linux test failure stops the run at `linux`, and `publish` refuses a real release unless a passing Linux run is recorded, so an unreachable host, missing tools or `--no-linux` also stop it there. Only `--ignore-linux-failures` overrides this, and it needs explicit approval. The 10 Linux x86-64 failures found before v0.51 (LeakSanitizer leaks in five asan tests, progress-bar output, `angles` libm rounding, one REPL message) are fixed. A skipped, unreachable or failed Linux benchmark step keeps the previously committed `benchmarks/results/linux-x86_64` untouched; only a successful run replaces it. The `linux` step comes before the long Mac benchmarks so this fails fast. If pushing main is rejected after publishing, merge (`git pull --no-rebase`), never rebase: the published tag must stay an ancestor of main.

**Failure and resume.** The script ends with the exact command to continue. `--resume` continues at the first unfinished step, `--from STEP` at a named one (steps before it count as done), `--restart` throws the unfinished run and the clone's local changes away. A resumed run first re-checks the environment and that the clone still holds only release changes. If `publish` fails halfway, nothing has reached the site (main is pushed last); `gh release delete vX --cleanup-tag -y` undoes a half-made release.

**Deviations from the old manual order, on purpose.** The release commit is made locally before the tag so the tag points at the commit with the new version, but main is pushed only after the published assets are downloaded and verified.

### One-time setup of the release Mac

1. Both certificates with their private keys in the login keychain: `Developer ID Application: Davis McDowell (39BK8TGQ26)` and `Developer ID Installer: ...` (`security find-identity -v`).
2. Let non-interactive sessions use the keys (an agent's shell is not the GUI session). In Terminal there, once, typing the login password when asked: `security unlock-keychain ~/Library/Keychains/login.keychain-db`, then `security set-key-partition-list -S apple-tool:,apple:,codesign: -s ~/Library/Keychains/login.keychain-db`. `errSecInternalComponent` from `codesign` means this is missing. The preflight signs a small test file with both identities to catch it.
3. The notary login, once, in Terminal there (the app-specific password is typed there and stays in the keychain, never in a file): `xcrun notarytool store-credentials tomato-notary --apple-id APPLE_ID --team-id 39BK8TGQ26`.
4. A WASI SDK unpacked in the home folder: `~/wasi-sdk-24.0-arm64-macos` (from https://github.com/WebAssembly/wasi-sdk/releases), found automatically, or pass `--wasi-sdk`.
5. `gh auth login` as an account that can push to `sirbuffalo/tomato`, and ssh access to GitHub for `git push`.
6. For the benchmarks: Go, Rust (cargo) and python3 (the Python programs exist only as a comparison). For instruction counts: `benchmarks/count.sh --setup` once (Lima and the Linux arm64 VM `tomato-count`); without the VM that part is skipped.
7. For the Linux step: `ssh biggie.davismcd.com true` must work without a password from the release Mac (accept the host key once by hand; the short name `biggie` has no known host key; authorize the release Mac's `~/.ssh/id_ed25519.pub` in `~/.ssh/authorized_keys` there). Install the toolchains once, with no root: `ssh biggie.davismcd.com 'sh -s' < release/linux-setup.sh` (clang 21.1.8, Go 1.27.4, Rust, Valgrind 3.26.0 into `~/.tomato-release/linux-tools`).
8. Quit other work before a release: timings taken on a busy Mac are not comparable, which is why the script refuses to run above the load limit.

## The steps by hand

The script does exactly this; the rest of this page describes the pieces.


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

## The disk image

`release/dmg.sh PKG OUT.dmg` runs after `sign-pkg.sh`, on the same Mac. It copies the finished package (signed, notarized and stapled) into a compressed HFS+ image named `Tomato VERSION`, which holds only `tomato-VERSION.pkg`. Then it signs the image with `codesign --timestamp` and the **Application** identity (a disk image is code-signed, not product-signed), notarizes it with `tomato-notary`, staples it, and checks it with `hdiutil verify`, `codesign --verify --strict`, `stapler validate` and `spctl --assess --type open --context context:primary-signature`. Finally it mounts the image read-only and checks that the package inside is byte-identical to PKG, still signed and still stapled. With `TOMATO_LATEST_JSON` it adds `dmg_url` and `dmg_sha256` to that file. `tomato update` ignores both fields, and the download page shows the link. `TOMATO_SKIP_NOTARIZE` and `TOMATO_NO_SIGN` are for dry runs only, as with `sign-pkg.sh`.
