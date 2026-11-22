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
- Free temporaries on the failure path of compiler checks
  An error caught in the middle of an expression drops a fresh big-number (and object) temporary without freeing it (`huge() // 0`, `huge() ** -1`, `huge() + int('x')`). Free the pending temporaries on the failure path of `fail_if` checks (`int_zero_check`, the pow negative-exponent check, failing `int()` conversions), then make the big-number leak check strict after errors again and add those shapes to `bigint_unwind`.
- Recover the debug-mode small-int arithmetic regression from the big-integer ownership change
  Debug-mode fib went from 0.41 s to 0.60 s (sieve 0.32 to 0.38 s, collatz 1.54 to 1.61 s) when big integers started owning their limbs; release mode lost about 7% on fib. Find which check or copy now sits on the small-int path (benchmarks/run.sh --only fib,sieve,collatz) and take it off.
- Create a Developer ID Application certificate and notarize the pkg
  Davis: create it on the MacBook (Xcode > Settings > Accounts > Manage Certificates > + > Developer ID Application). Then run the flow in docs/releasing.md on v0.49, upload with `gh release upload --clobber`, update site/latest.json pkg_sha256, and drop the unsigned note on the Download page.
- Fuse f-string chains ('w' + str(x)) into one buffer
  Needs a compiler change; the remainder of wordcount/strings time is malloc/free (size-class allocator task).
