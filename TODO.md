- Move the v0.50 tag to the merge commit
  After merge, move the v0.50 tag to the merge commit (the release was created with --target main before the version bump landed); assets are unaffected.
- Cut the remaining per-iteration cost of the mandelbrot loop
  At counting input 250, Tomato ÷ Go is 1.97 in instructions executed. The hot loop still pays for 3 float checks and the tagged counter `i` (tag tests, overflow-checked add). Removing the counter checks needs range reasoning such as proving that `i + 1` is small when `0 <= i < 100`.
- Teach the expression-position type parser the comma form `tuple[A, B]`
  Mixed-type tuple types parse only in annotations, so `x in tuple[str, int]` (which would narrow a union such as `int | tuple[str, int]`) and explicit generic arguments such as `Box[tuple[str, int]](('a', 1))` fail with `expected ']', but found ','`. Inference from arguments and `Box[tuple[str, int]]` in an annotation already work; see P89 in `docs/provisional.md`.
- Add a Linux CI job that runs tests/run.sh with LeakSanitizer
  macOS CI cannot detect leaks (LeakSanitizer does not run there), which is how the error-path and task-waiter leaks fixed by the code cleanup went unnoticed. Export `ASAN_SYMBOLIZER_PATH` so a failure shows the real report.
- Free temporaries on the error path of class-object slicing and big-int range bounds
  The last two known error-path leaks: `obj[a:b]` on a class object when it raises, and a big int in a range bound when a later bound fails its check. The other cases are covered by `tests/programs/error_path_release.tom`.
- Add a `time` module (wall clock, gmtime/strftime/isoformat, Stopwatch)
  The code cleanup task's tooling reviewer wrote a draft, kept at `~/.cache/tomato-time-module-draft/` on the build server (`std/time.tom` with `time()`, `monotonic()`, `Stopwatch`, `gmtime`, `timegm`, `strftime`, `isoformat`, `format_duration`, UTC only, plus a `tomato_time` runtime function); it was left out as a new feature and needs a decision on the API first.
- Make `site/wasm` builds byte-identical across Linux and macOS
  The Linux and macOS builds of WASI SDK 24 produce different `tomatoc.wasm`/`runtime.wasm` bytes from the same source, so wasm rebuilt and committed on biggie fails the Mac release gate ("wasm files rebuild identically"). Either make the build host-independent, or have tasks on Linux skip the rebuild comparison and leave the canonical rebuild to the Mac (macOS arm64 WASI SDK 24, as `docs/releasing.md` says).
