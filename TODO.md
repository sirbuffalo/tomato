- Make open() failures name the file and decide Unicode case mapping for upper/lower
  The IOError message is the constant 'a file could not be opened', so it never says which file; `str.upper` and `str.lower` only change ASCII letters and the spec does not decide Unicode case mapping.
- Fix printing and str() of optional values and None
  Printing a `str | None` value crashes at runtime and `str(None)` fails to compile; found while testing f-strings and conditional expressions.
- Finish the dict and text built-ins
  Still missing: Unicode `isalpha`/`isdigit` (needs a decision on the Unicode category tables) and `dict.items()` as a value when the values are lists, dicts or objects (its tuples have one item type, so it needs mixed-type tuples; `for k, v in d.items():` already works for any value type).
- Fuse f-string chains ('w' + str(x)) into one buffer
  Needs a compiler change; the remainder of wordcount/strings time is malloc/free (size-class allocator task).
- Add `memoize(f)` / `@cached` to std/cache once function values land on main
  std/cache.tom has the cache and the injectable `Clock`, but a function cannot be passed as a value yet, so memoising a function waits for the function values task.
- Typed list storage: `list[bool]` as bytes (and possibly unboxed floats)
  Shrinks sieve's 160 MB working set; needs the runtime, compiler and site/wasm/llvm.js to know the element width.
- Add `r.json()` to requests and let `json=` take a Json value
  `loads(self.text)` once the json library is on main; its task has fixed the API as `from json import loads, dumps, Json`.
- Make `s[i]` O(1) for ASCII text (and a chunked index for other text, D17c)
  Indexing text is a linear scan today (`char_offset` in runtime/tomato_rt.c), so a character loop over a 300,000 character string takes about 57 s; std/json uses a C scanner because of it.
- Move the v0.50 tag to the merge commit
  After merge, move the v0.50 tag to the merge commit (the release was created with --target main before the version bump landed); assets are unaffected.
