- Add an iterator hook to `for`
  So `for x in progress_bar(items)` (std/itertools.tom) draws as it goes. `for` only loops over lists, dicts and ranges today; needs a compiler change and a bootstrap refresh.
- Add a clock builtin
  So progress_bar can show elapsed time, speed and ETA. The language has no clock yet.
- Design an iteration protocol for `for`
  So `for i in progress_bar(range(..))` and a lazy range work (D18a); today `for` cannot walk class objects.
- Add list methods pop, insert, extend, sort and reverse, and list equality (==)
  Lists only have `append` today; `==` on two lists is not supported.
- Add function values or lambdas so map and filter can exist
  The language has no function values, so `map` and `filter` give a "not available" error.
- Make open() failures name the file and decide Unicode case mapping for upper/lower
  The IOError message is the constant 'a file could not be opened', so it never says which file; `str.upper` and `str.lower` only change ASCII letters and the spec does not decide Unicode case mapping.
