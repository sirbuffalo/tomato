- Finish the dict and text built-ins
  Still missing: Unicode `isalpha`/`isdigit` (needs a decision on the Unicode category tables) and `dict.items()` as a value when the values are lists, dicts or objects (its tuples have one item type, so it needs mixed-type tuples; `for k, v in d.items():` already works for any value type).
- Typed list storage: `list[bool]` as bytes (and possibly unboxed floats)
  Shrinks sieve's 160 MB working set; needs the runtime, compiler and site/wasm/llvm.js to know the element width.
- Move the v0.50 tag to the merge commit
  After merge, move the v0.50 tag to the merge commit (the release was created with --target main before the version bump landed); assets are unaffected.
- Cut the remaining per-iteration cost of the mandelbrot loop
  At counting input 250, Tomato ÷ Go is 1.97 in instructions executed. The hot loop still pays for 3 float checks and the tagged counter `i` (tag tests, overflow-checked add). Removing the counter checks needs range reasoning such as proving that `i + 1` is small when `0 <= i < 100`.
- Fix the 10 Linux x86-64 test failures so the Linux release gate can pass
  Found by `release/release.sh` on biggie: LeakSanitizer leaks in 5 asan tests (msgpack_errors, bigint_frames, bigint_unwind, toml_invalid, requests_local), progress-bar output (iteration main, progress_bar, itertools_any), `angles` libm rounding (3.0000000000000004 vs 3.0) and the REPL missing-module message test. Until fixed, a release needs `--ignore-linux-failures`.
- Make tests use unique temp paths instead of fixed `/tmp/tomato_*` names
  `toml_api` fails on this machine because another user account owns `/tmp/tomato_toml_api_test.toml`, and parallel suite runs can collide. The new msgpack tests follow the same existing pattern as `json_files`.
