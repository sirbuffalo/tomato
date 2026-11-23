- Finish the dict and text built-ins
  Still missing: Unicode `isalpha`/`isdigit` (needs a decision on the Unicode category tables) and `dict.items()` as a value when the values are lists, dicts or objects (its tuples have one item type, so it needs mixed-type tuples; `for k, v in d.items():` already works for any value type).
- Move the v0.50 tag to the merge commit
  After merge, move the v0.50 tag to the merge commit (the release was created with --target main before the version bump landed); assets are unaffected.
- Cut the remaining per-iteration cost of the mandelbrot loop
  At counting input 250, Tomato ÷ Go is 1.97 in instructions executed. The hot loop still pays for 3 float checks and the tagged counter `i` (tag tests, overflow-checked add). Removing the counter checks needs range reasoning such as proving that `i + 1` is small when `0 <= i < 100`.
- Make tests use unique temp paths instead of fixed `/tmp/tomato_*` names
  `toml_api` fails on this machine because another user account owns `/tmp/tomato_toml_api_test.toml`, and parallel suite runs can collide. The new msgpack tests follow the same existing pattern as `json_files`.
- Fix the false 'might not have a value' warning for lambda parameters
  A lambda parameter with the same name as a local assigned only in one branch is warned about, e.g. `if c: b = 1` then `sorted(xs, key=b -> -b)`.
- Fix the print unwind leak after v0.51 lands
  After v0.51 lands: apply the print unwind leak fix (patch in this task's evidence and at ~/.cache/tomato-print-leak-followup.patch), refresh the bootstrap IR and rebuild site/wasm on the Mac. In `print(a, b)`, if `a`'s `@str` raises, `b` leaks; the patch keeps unprinted arguments held and adds two `temp_unwind` cases.
- Make the Linux test suite fully green
  Investigate the 8 failing checks on this Linux box: the progress-bar output tests (`iteration`, `progress_bar`, `itertools_any`), the native `angles` float rounding (3.0000000000000004 vs 3.0), and the AddressSanitizer symbolizer path (`msgpack_errors`, `bigint_frames`, `bigint_unwind`, `requests_local`).
