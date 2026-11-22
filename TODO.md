- Add a clock builtin
  So progress_bar can show elapsed time, speed and ETA. The language has no clock yet.
- Add list methods pop, insert, extend, sort and reverse, and list equality (==)
  Lists only have `append` today; `==` on two lists is not supported.
- Add function values or lambdas so map and filter can exist
  The language has no function values, so `map` and `filter` give a "not available" error.
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
- Add a size-class free-list allocator for small objects
  Bypassed under ASan, to cut malloc/free cost in the objects benchmark (about 0.5 s left after the collector fix).
