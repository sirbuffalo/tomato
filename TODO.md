- Add an iterator hook to `for`
  So `for x in progress_bar(items)` (std/itertools.tom) draws as it goes. `for` only loops over lists, dicts and ranges today; needs a compiler change and a bootstrap refresh.
- Add a clock builtin
  So progress_bar can show elapsed time, speed and ETA. The language has no clock yet.
- Design an iteration protocol for `for`
  So `for i in progress_bar(range(..))` and a lazy range work (D18a); today `for` cannot walk class objects.
