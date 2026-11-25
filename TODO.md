- Publish the LTO Linux timings
  The v0.51 Linux wall-clock snapshot and Linux time columns in `docs/performance.md` (and `site/benchmarks.json`, which has no Linux numbers) were measured without LTO; the instruction counts are already re-measured (`benchmarks/results/linux-x86_64/instructions.md`). After the "Re-run the Linux benchmarks on a quieter biggie" item lands (use `~/.tomato-release/linux-tools/bin` first on PATH; run `release/check-lto.sh` first), replace the timing numbers and remove the non-LTO notes in `docs/performance.md`. Also run the full tier of `tests/run.sh` once on a quiet biggie with `TOMATO_TEST_REQUIRE_LTO=1`, and one real `release/release.sh` Linux step (the fast tier with it set passed, 630 tests; the release path was not run).
- Test unattended release signing on the iMac
  Test signing after a restart, from an ssh session and after sleep, and run a `--no-linux` release attempt that must be refused at publish. v0.51 only showed prompt-free signing from byre sessions; the gate's refusal was only tested with stubbed state.
- Re-run the Linux benchmarks on a quieter biggie
  The v0.51 Linux x86-64 numbers were taken at load about 75; run them again when biggie's load is below 32.
- Re-measure the full tier on a quiet biggie (load below 32) with `-j 64` and put the real number in tests/README.md
  The test-suite speed-up was measured only at load 70-120 (full tier 125-267 s wall, 2,464-3,849 CPU s), so the one-minute target is not demonstrated. Run `tests/run.sh --times -j 64` when biggie is quiet and record wall, CPU and load.
- Confirm the split bootstrap build on the Mac
  Run `tests/run.sh` on the Mac (and the full tier) to confirm `build-object.sh` takes the split path under macOS's BWK awk and Apple ld rather than the fallback.
- Measure the per-item instruction saving of borrowed loop items on `objects`
  Measure it on a quiet machine (perf stat or valgrind).
- Widen the loop-item borrowing
  Cover methods that call other proven list-safe methods, and loops over non-class items.
- Find why collatz executes more instructions than at v0.51
  collatz executes 17% (plain or LTO link) to 24% (bitcode-merge link) more instructions at d83f43b0 than at v0.51 (70.3 M to 82–87 M, counting input, Linux x86-64). Compare the emitted IR at the two trees. Numbers: `benchmarks/results/linux-x86_64/lto-effect.md`.
- Check why fib executes more instructions with the runtime inlined
  fib executes 9% more instructions with the runtime inlined (bitcode merge or LTO) than with a plain link at d83f43b0 (123.5 M vs 113.0 M). Check the inliner's choices and whether the Linux timings agree. Numbers: `benchmarks/results/linux-x86_64/lto-effect.md`.
- Review the compiler changes (`for_file`, `open_call` class switch, `entry_wrapper` `*args`) and the runtime changes on macOS too
  `st_mtimespec` and `extern char **environ` in `runtime/tomato_rt.c` are untested there (only Linux native and WASI were built), and so is the read/write switch for files opened with `+` (`file_to_reading` and `file_to_writing`, which seek at every call on a `+` file on macOS because `__freading` and `__fwriting` do not exist there; read the stdio flags or track the last operation to avoid the extra seeks).
- Run the release script's `bump` step once on a scratch clone
  Confirm it rewrites `std/sys.tom` and `site/wasm/std/sys.tom` and that the commit step accepts the extra file.
- Run the full `tests/run.sh` once on the merged Wave 2 result
  Run it with `WASI_SDK` set so ASan and the wasm rebuild check run, and with node or jsc for the browser checks. The builders ran the full suite on identical trees, but nobody ran it on the final merged tree, and macOS is untested.
- Investigate why `tests/run.sh --fast -j 8` and `-j 16` exit with status 144 at the compiler step
  On the builder's machine the suite passes without `-j`. One guess is the memory use of parallel clang runs on the 14 MB `tomatoc.ll`.
- Decide the lifetime of a File opened in a `for` loop header (A-Q7)
  `for line in open(path):` never closes its file, so each use leaks a descriptor and a program that does it often hits EMFILE; using or closing a File after `close()` is also undefined. Choose one: close the temporary on every loop exit, warn when a loop header calls `open(...)`, or give File a closed flag so misuse raises `ValueError`. Add a test that counts open descriptors.
- Make `Pattern.match`/`search` with an advancing `pos` linear
  Each call compares the whole text with the cached copy, so a loop of `search(text, pos)` over one long text is quadratic (documented in `docs/regex.md`). It needs a cheap way to tell that the same text was passed again, such as a runtime string-identity test, or a scanning iterator.
- Floats of any size in the library and the formats (stage 4 of docs/bigfloat-design.md)
  Make std/math, round(x, n), f-string float formats, JSON, TOML and MessagePack handle floats outside the double range (the runtime already has tomato_bf_math1/2, tomato_bf_round, tomato_bf_format), with a decision entry for each visible change.
- Fast loop copy for float loops (stage 5 of docs/bigfloat-design.md)
  Fast loop copy for float loops, float interval facts for the word type (reusing or replacing the now-idle float interval code), and measurements on the M1, Linux and the browser.
- Make counted repeats `{m,n}` around a group that can match the empty string give Python's results
  The group's recorded span and, in rare cases, the overall match span differ from Python, for example `(a??){,2}` on `'a'` and `(.|(\s{,2})??){,2}` with `finditer` on `'\na'`. Stop a repeat after an empty iteration instead of unrolling plain optional copies, and add those cases as corpus rows (`docs/regex.md` documents the difference).
- Fix `path_rename` in `site/wasm/wasi.js` for files under a moved directory
  It moves the directory entries but leaves the `mtimes` entries of the files under the moved directory behind. Check and fix it when the browser tests run.
- Make refresh.sh use the split bootstrap build
  Make `compiler/bootstrap/refresh.sh` use `build-object.sh` (split build) and skip rebuilding a compiler that is already up to date. Expected 75 s to about 30-35 s (measured at load 63-77: two single-clang compiles of the 14.5 MB IR took about 62 s of the 75 s; the split build takes about 9 s).
- Design a non-LTO debug build path for tomato build and run
  Keep the runtime's inline fast paths (alwaysinline IR emitted or prepended by tomatoc) so the debug link needs no LTO merge. Expected debug builds 1.8-2.3x faster (fib 1.15 s to about 0.5 s; the LTO link is about 1.0 s of 1.15 s), which also speeds the test suite; needs a full test run and a wasm rebuild.
