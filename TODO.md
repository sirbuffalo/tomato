- Run the LTO release checks through the real `release/release.sh` and on a quiet biggie
  Done on 2026-11-25 at load about 65 (not quiet): `release/check-lto.sh`, the full tier with `TOMATO_TEST_REQUIRE_LTO=1` (842 passed, 0 failed) and the release's Linux remote script piped to biggie by hand (tests, benchmarks and instruction counts all fine); see `tests/README.md`. Still to do: one real `release/release.sh` Linux step from the Mac (the ssh, fetch-back and publish-gate parts were not exercised; the next release does it), and the full tier timed once on a quiet biggie (load never fell below 32; another account's `prst` jobs). Use `~/.tomato-release/linux-tools/bin` first on PATH and run `release/check-lto.sh` first.
- Confirm the split bootstrap build on the Mac
  Run `tests/run.sh` on the Mac (and the full tier) to confirm `build-object.sh` takes the split path under macOS's BWK awk and Apple ld rather than the fallback.
- Widen the loop-item borrowing further
  Let proven methods take object, text or list parameters (`a.absorb(b)`), and let borrowed bodies hold nested range loops (`Gen.lent_loop_body`, `lent_method_info`; see "borrowed loop items" in `docs/performance.md`).
- Floats of any size in the library and the formats (stage 4 of docs/bigfloat-design.md)
  Make std/math, round(x, n), f-string float formats, JSON, TOML and MessagePack handle floats outside the double range (the runtime already has tomato_bf_math1/2, tomato_bf_round, tomato_bf_format), with a decision entry for each visible change.
- Fast loop copy for float loops (stage 5 of docs/bigfloat-design.md)
  Fast loop copy for float loops, float interval facts for the word type (reusing or replacing the now-idle float interval code), and measurements on the M1, Linux and the browser.
- Design a non-LTO debug build path for tomato build and run
  Keep the runtime's inline fast paths (alwaysinline IR emitted or prepended by tomatoc) so the debug link needs no LTO merge. Expected debug builds 1.8-2.3x faster (fib 1.15 s to about 0.5 s; the LTO link is about 1.0 s of 1.15 s), which also speeds the test suite; needs a full test run and a wasm rebuild.
- Make the `repl: up-arrow recalls a multi-line block as one history entry` check robust under load
  `tests/repl_history.exp` is sleep-driven (0.3 to 1.5 s between keys) and failed in both full-tier runs on biggie at load 65-100, where `expect` is a hand-unpacked package. Find out whether the load or that `expect` is the cause (run it alone on a quiet machine and with a normal `expect`), and make the check wait for the prompts instead of sleeping.
- Fix the float performance regression from `bf46a4ee`
  mandelbrot executes 7.6x, nbody 3.4x and spectral_norm 1.7x more instructions at `bf46a4ee` than at its parent (callgrind, `benchmarks/count.sh --guest`; numbers in `docs/performance.md` and `benchmarks/results/linux-x86_64/results-f533dbd0.md`). Compare the emitted IR before and after the bigfloat stage 3 commit. The Linux snapshot in `docs/performance.md` was measured at the same tree label (`f533dbd0`) without the slowdown, so first find out why the two runs differ.
- Run `release/release.sh --dry-run` on the signing Mac once to exercise the real Linux step
  Use `--dry-run` (or `--from linux`) so ssh, copy-back, the publish gate and the snapshot are exercised end to end, with `--linux-host` reachable from the Mac. The Linux step's remote script alone ran fine on biggie: the full tier passed 842 tests with `TOMATO_TEST_REQUIRE_LTO=1` at load about 62 (not quiet).
- Trace why the bitcode-merge link leaves `tomato.main` un-inlined
  With the runtime merged as bitcode (`-mlink-bitcode-file`), `tomato.main` is not inlined into `main` and `x*3` comes out as `lea`+`add` instead of one `lea` on collatz: 1 instruction per step (87.15 M against 82.12 M with LTO). The IR is the same; find the cause in the merge link's inlining or instruction selection. Numbers: `benchmarks/results/linux-x86_64/lto-effect.md`.
- Run tests/run.sh on macOS (with the wasi-sdk arm64-macos toolchain) to cover the untested platform.
  The full suite passed on Linux x86_64 on the merged Wave 2 tree (984 passed, 0 failed); macOS is the platform still untested.
- Run the full suite with ASan, LTO and the WASI SDK on a complete toolchain (or the Mac) to confirm the new test also passes under AddressSanitizer.
