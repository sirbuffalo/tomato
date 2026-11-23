- Add list methods pop, insert, extend, sort and reverse, and list equality (==)
  Lists only have `append` today; `==` on two lists is not supported.
- Make open() failures name the file and decide Unicode case mapping for upper/lower
  The IOError message is the constant 'a file could not be opened', so it never says which file; `str.upper` and `str.lower` only change ASCII letters and the spec does not decide Unicode case mapping.
- Fix printing and str() of optional values and None
  Printing a `str | None` value crashes at runtime and `str(None)` fails to compile; found while testing f-strings and conditional expressions.
- Finish the dict and text built-ins
  Missing from the first version: `dict.get(key)` with one argument (gives None), `strip(chars)` (and lstrip/rstrip with chars), an end bound for `find`/`rfind`/`count`, Unicode `isalpha`/`isdigit`, `abs` on fixed-width integers, `dict.items()` for list and object values, and Python-style quoting of text inside `items()` output (it prints `(ann, 31)`, not `('ann', 31)`).
- Allow `for k, v in d.items():` and tuple targets in for loops
  A for loop with several variables only accepts `enumerate(...)` or `zip(...)` today, so looping over `dict.items()` or a list of tuples needs indexing; found while using the new features across the code.
- Act on docs/performance.md: cut refcount and cycle-collector bookkeeping, inline the small-int fast path, compile list indexing to a bounds check plus load
  The benchmarks (benchmarks/, site/benchmarks.html) show Tomato 12x to 48x slower than Rust on loops over big lists, sort and objects; docs/performance.md ranks the likely causes. Profile before building each one.
- Free temporaries on the failure path of compiler checks
  An error caught in the middle of an expression drops a fresh big-number (and object) temporary without freeing it (`huge() // 0`, `huge() ** -1`, `huge() + int('x')`). Free the pending temporaries on the failure path of `fail_if` checks (`int_zero_check`, the pow negative-exponent check, failing `int()` conversions), then make the big-number leak check strict after errors again and add those shapes to `bigint_unwind`.
- Fuse f-string chains ('w' + str(x)) into one buffer
  Needs a compiler change; the remainder of wordcount/strings time is malloc/free (size-class allocator task).
- Add `memoize(f)` / `@cached` to std/cache once function values land on main
  std/cache.tom has the cache and the injectable `Clock`, but a function cannot be passed as a value yet, so memoising a function waits for the function values task.
- Typed list storage: `list[bool]` as bytes (and possibly unboxed floats)
  Shrinks sieve's 160 MB working set; needs the runtime, compiler and site/wasm/llvm.js to know the element width.
- Speed up cmp= sort (inline small-int fast paths for comparison and index arithmetic, or a native merge sort calling the function directly on native builds)
  `sorted(xs, cmp=f)` is a merge sort written in Tomato (std/builtin.tom) and takes about 2.3 s for 3,000,000 ints (Rust 0.12 s) because every int operation calls the runtime; see docs/performance.md.
- Add `r.json()` to requests and let `json=` take a Json value
  `loads(self.text)` once the json library is on main; its task has fixed the API as `from json import loads, dumps, Json`.
- Make `s[i]` O(1) for ASCII text (and a chunked index for other text, D17c)
  Indexing text is a linear scan today (`char_offset` in runtime/tomato_rt.c), so a character loop over a 300,000 character string takes about 57 s; std/json uses a C scanner because of it.
- Move the v0.50 tag to the merge commit
  After merge, move the v0.50 tag to the merge commit (the release was created with --target main before the version bump landed); assets are unaffected.
