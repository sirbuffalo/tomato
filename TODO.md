- Teach the expression-position type parser the comma form `tuple[A, B]`
  Mixed-type tuple types parse only in annotations, so `x in tuple[str, int]` (which would narrow a union such as `int | tuple[str, int]`) and explicit generic arguments such as `Box[tuple[str, int]](('a', 1))` fail with `expected ']', but found ','`. Inference from arguments and `Box[tuple[str, int]]` in an annotation already work; see P89 in `docs/provisional.md`.
- Add a Linux CI job that runs tests/run.sh with LeakSanitizer
  macOS CI cannot detect leaks (LeakSanitizer does not run there), which is how the error-path and task-waiter leaks fixed by the code cleanup went unnoticed. Export `ASAN_SYMBOLIZER_PATH` so a failure shows the real report.
- Free temporaries on the error path of class-object slicing and big-int range bounds
  The last two known error-path leaks: `obj[a:b]` on a class object when it raises, and a big int in a range bound when a later bound fails its check. The other cases are covered by `tests/programs/error_path_release.tom`.
- Build Wave 1 of the next-features plan as Sonnet tasks
  See `docs/next-features.md`, section 6. Everyday built-ins, text methods and math additions (item 1); `random`/`secrets`/`uuid` (4); `urllib.parse`, `html` and `base64` (5); the `csv`/`textwrap`/`statistics` pack (7); `datetime` (11). Each starts only after Davis approves its API sheet.
- Assign a stronger agent to the async toolkit, then the scheduler fd-waiter and `socket` module
  Items 8 and 9 of `docs/next-features.md`: `gather`, timeouts and `Queue` first, then a scheduler wait on file descriptors plus a `socket` module, so the HTTP server (item 10) can follow. The scheduler is hand-written C with reference-counted frames, so use Opus or have Davis review it.
- Remove mandelbrot's remaining float finite checks with float interval reasoning
  The mandelbrot inner loop still pays for 3 finite checks per iteration. zr and zi are bounded once `zr*zr + zi*zi <= 4.0` holds, and cr, ci are bounded via `px < n`, so float interval reasoning (alongside the integer ranges in `Gen.range_of`) could prove the results finite. See the "integer ranges" section of docs/performance.md.
- Fix range loops whose bounds pass 2^62
  `tag_small` wraps the loop variable: `for i in range(E + 2, E - 3, -1)` with E = 2^62 - 1 starts at -2^62. Bounds beyond the small range need the general (big-number) loop or a check.
- Use the range facts in the small-int loop fast copy
  `small_loop`'s fast copy keeps its overflow checks even when an interval from `Gen.loop_facts` proves them unnecessary; dropping them there would cut the checks from small-int loops whose variables have known bounds (collatz itself has none).
