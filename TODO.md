- Finish the dict and text built-ins
  Still missing: Unicode `isalpha`/`isdigit` (needs a decision on the Unicode category tables) and `dict.items()` as a value when the values are lists, dicts or objects (its tuples have one item type, so it needs mixed-type tuples; `for k, v in d.items():` already works for any value type).
- Add `memoize(f)` / `@cached` to std/cache once function values land on main
  std/cache.tom has the cache and the injectable `Clock`, but a function cannot be passed as a value yet, so memoising a function waits for the function values task.
- Typed list storage: `list[bool]` as bytes (and possibly unboxed floats)
  Shrinks sieve's 160 MB working set; needs the runtime, compiler and site/wasm/llvm.js to know the element width.
- Add msgpack file functions (`load_msgpack(path)`, `dump_msgpack(value, path)`)
  `open` is text-only, so this needs byte-level file functions in the runtime (native and wasm); `json.load`/`dump` and `toml.dump` exist.
- Move the v0.50 tag to the merge commit
  After merge, move the v0.50 tag to the merge commit (the release was created with --target main before the version bump landed); assets are unaffected.
