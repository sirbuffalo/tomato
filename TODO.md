- Finish the dict and text built-ins
  Still missing: Unicode `isalpha`/`isdigit` (needs a decision on the Unicode category tables) and `dict.items()` as a value when the values are lists, dicts or objects (its tuples have one item type, so it needs mixed-type tuples; `for k, v in d.items():` already works for any value type).
- Typed list storage: `list[bool]` as bytes (and possibly unboxed floats)
  Shrinks sieve's 160 MB working set; needs the runtime, compiler and site/wasm/llvm.js to know the element width.
- Add msgpack file functions (`load_msgpack(path)`, `dump_msgpack(value, path)`)
  `open` is text-only, so this needs byte-level file functions in the runtime (native and wasm); `json.load`/`dump` and `toml.dump` exist.
- Move the v0.50 tag to the merge commit
  After merge, move the v0.50 tag to the merge commit (the release was created with --target main before the version bump landed); assets are unaffected.
- Cut the remaining per-iteration cost of the mandelbrot loop
  At counting input 250, Tomato ÷ Go is 1.97 in instructions executed. The hot loop still pays for 3 float checks and the tagged counter `i` (tag tests, overflow-checked add). Removing the counter checks needs range reasoning such as proving that `i + 1` is small when `0 <= i < 100`.
