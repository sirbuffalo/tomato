- Move the v0.50 tag to the merge commit
  After merge, move the v0.50 tag to the merge commit (the release was created with --target main before the version bump landed); assets are unaffected.
- Cut the remaining per-iteration cost of the mandelbrot loop
  At counting input 250, Tomato ÷ Go is 1.97 in instructions executed. The hot loop still pays for 3 float checks and the tagged counter `i` (tag tests, overflow-checked add). Removing the counter checks needs range reasoning such as proving that `i + 1` is small when `0 <= i < 100`.
- Teach the expression-position type parser the comma form `tuple[A, B]`
  Mixed-type tuple types parse only in annotations, so `x in tuple[str, int]` (which would narrow a union such as `int | tuple[str, int]`) and explicit generic arguments such as `Box[tuple[str, int]](('a', 1))` fail with `expected ']', but found ','`. Inference from arguments and `Box[tuple[str, int]]` in an annotation already work; see P89 in `docs/provisional.md`.
- Print mixed tuples (and lists/objects) inside unions properly instead of `<object>`
  A union member that is a mixed tuple, list or object prints as `<object>` (`[1, <object>]`), because the box only knows how to print numbers, text and bools. Needs a per-member show function in the union box; see P89 in `docs/provisional.md`.
- Add a Linux CI job that runs tests/run.sh with LeakSanitizer
  macOS CI cannot detect leaks (LeakSanitizer does not run there), which is how the error-path and task-waiter leaks fixed by the code cleanup went unnoticed. Export `ASAN_SYMBOLIZER_PATH` so a failure shows the real report.
- Decide whether `d = {'a': 1}` without a type annotation should infer `dict[str, int]`
  Today it is rejected with E289 ("the type of an empty {} cannot be guessed"), which is wrong wording for a non-empty dict; either infer the type (a language decision) or give a better message.
- Free temporaries on the error path of class-object slicing and big-int range bounds
  The last two known error-path leaks: `obj[a:b]` on a class object when it raises, and a big int in a range bound when a later bound fails its check. The other cases are covered by `tests/programs/error_path_release.tom`.
- Make the `angles` test tolerant of libm differences
  glibc's `cbrt(27)` gives 3.0000000000000004 where macOS gives 3.0, so `program angles` fails on Linux; compare with a tolerance (or print a rounded value) so the suite is clean there (it is the only check that fails on Linux).
- Add a `time` module (wall clock, gmtime/strftime/isoformat, Stopwatch)
  The code cleanup task's tooling reviewer wrote a draft, kept at `~/.cache/tomato-time-module-draft/` on the build server (`std/time.tom` with `time()`, `monotonic()`, `Stopwatch`, `gmtime`, `timegm`, `strftime`, `isoformat`, `format_duration`, UTC only, plus a `tomato_time` runtime function); it was left out as a new feature and needs a decision on the API first.
