- Run the LTO release checks through the real `release/release.sh` and on a quiet biggie
  Done on 2026-11-25 at load about 65 (not quiet): `release/check-lto.sh`, the full tier with `TOMATO_TEST_REQUIRE_LTO=1` (842 passed, 0 failed) and the release's Linux remote script piped to biggie by hand (tests, benchmarks and instruction counts all fine); see `tests/README.md`. Still to do: one real `release/release.sh` Linux step from the Mac (the ssh, fetch-back and publish-gate parts were not exercised; the next release does it), and the full tier timed once on a quiet biggie (load never fell below 32; another account's `prst` jobs). Use `~/.tomato-release/linux-tools/bin` first on PATH and run `release/check-lto.sh` first.
- Run `release/release.sh --dry-run` on the signing Mac once to exercise the real Linux step
  Use `--dry-run --version 1.0.0` (or `--from linux`) so ssh, copy-back, the publish gate and the snapshot are exercised end to end, with `--linux-host` reachable from the Mac. The Linux step's remote script alone ran fine on biggie: the full tier passed 842 tests with `TOMATO_TEST_REQUIRE_LTO=1` at load about 62 (not quiet).
- Answer the seed registry open questions, then build the rest of stage 3 onward
  Answer the open questions in section 19 of `docs/package-registry-design.md` (1 to 11). The local part is built (D95a, `docs/manifest.md`: the strict manifest reader, `[build]`, path and git seeds with the store, `tomato.lock`, `tomato seed install/add/remove/vendor/check/hash`, the foreign-symbol question, D100a, no helper program); what is left is the registry, signatures, the index client and everything under "Not built yet" in the sheet.
- Settle the compatibility-promise items of docs/language-design-review.md before tagging 1.0.0
  Its ranked list ("Decisions to make, ranked"): triage `docs/provisional.md`, release-mode error messages, builtin shadowing, the `@` namespace and `x is T`, `bytes`, `File` safety, reserved std module names and the `!` interface. Each needs Davis's decision, then a decision entry and the change.
- Check the shell-to-Tomato plan's open Mac points on a Mac
  Time the first-run cost of a freshly installed signed binary, check that `renamex_np` with `RENAME_SWAP` swaps two folders atomically, and check that `pkgbuild` accepts compiled executables as package scripts. All three are marked "to verify" in `docs/shell-to-tomato-plan.md`.
- Change `datetime.replace` part parameters from `int | bool = False` to `int | None = None`
  `datetime.replace` still takes year, month, day, hour, minute, second and microsecond as `int | bool = False`; convert them to `int | None = None` like `offset_minutes` (D94a), and update the callers, docs and tests.
- Replace a redeclared repl variable in place
  A redeclared variable moves to the end of the session's statements, so an earlier line that used it (`print(x)` between `x: int = 1` and `x: int = 2`) fails with 'name x is not defined'. Pre-existing; replace the declaration in place instead.
- Run the new `sys_async` test on macOS
  Check the kqueue wait on pipes and the `/dev/fd` listing (`tests/programs/sys_async.tom`, and the open-files check in `tests/programs/sys_run.tom`); everything of D98b was tested on Linux only.
- Write the init name with `printf`, not `echo`, in `native/tomato`
  `tomato init 'a\b'` writes `name = "a\b"` (the shell's `echo` turns the escaped `\\` back into `\`, and `\b` is a backspace in TOML), so the project is named "a" plus a backspace and the rest (`tomato config` shows `project: a`). Found by the CLI contract suite, which leaves backslash names untested until this is fixed.
- Make `tomato config` print only the error when a settings file is wrong
  With `[build] output = "x"` in `~/.tomato/config.toml`, `tomato config` prints nothing on standard output and the whole report up to the error (project file, user file, limits) on standard error before `error[E558]`, because the script merges the compiler's two streams; `tomato run` prints only the error.
- Say why `tomato seed install --locked` fails when a path seed's files changed
  After `seed install`, editing `thing/src/thing.tom`, `--locked` says `tomato.lock does not match this manifest` (E578): the manifest did not change, the seed's content hash did. And `tomato run` still builds with the changed seed and no complaint (a changed path seed is not checked against the lock); confirm that is intended for path seeds and word the E578 text for the hash.
- Refuse an empty `--mode` in `tomato run`
  `tomato run hello.tom --mode ""` runs in debug mode with no error (the empty word means "no flag"); `--mode release` and a bad word are checked.
- Narrow an optional by assignment of a non-None value
  `if x is None: x = default` should leave `x` a `T` for the rest of the block, as Python's checkers do. D102a narrows only by tests: an assignment ends the narrowing and the variable is `T | None` again whatever was assigned. Make the end of an `if` know it when its branch assigns a value of type `T`, and extend it to a plain `x = value` of a `T` value, keeping the statement rule of D102a for everything else.
- Add a bare-clone cache for seed fetches
  Bare-clone cache `~/.tomato/seeds/git/` (design section 6): `seed update` fetches the tag and then the commit with `--depth 1` each time; a cache would fetch only new objects.
