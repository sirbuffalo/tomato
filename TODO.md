- Assign a stronger agent to the async toolkit, then the scheduler fd-waiter and `socket` module
  Items 8 and 9 of `docs/next-features.md`: `gather`, timeouts and `Queue` first, then a scheduler wait on file descriptors plus a `socket` module, so the HTTP server (item 10) can follow. The scheduler is hand-written C with reference-counted frames, so use Opus or have Davis review it.
- Rebuild `site/wasm` on the Mac before the next release
  macOS arm64, WASI SDK 24: the error-path temporaries task landed a Linux-built `tomatoc.wasm`. It was built with the host-independent `site/wasm/build.sh`, so the Mac rebuild should give the same bytes ("wasm files rebuild identically").
- Build the approved Wave 2 packs as Sonnet tasks
  After Davis answers the questions in `docs/wave2-api-sheets.md`, start build tasks for the approved sheets: `re` and hashing first (Sonnet-sized, pure Tomato), then os/sys, then testing.
- Build Lock/Semaphore/Event on the Queue's waiter primitive
  After Davis answers the decisions in `docs/locks-design.md` section 9, build Lock/Semaphore/Event on the Queue's waiter primitive.
- Fix today's int to float bugs (stage 0 of docs/bigfloat-design.md)
  `float(huge)` silently gives `inf`, big ints round wrong, `10**400 / 10**399` raises although D05ad says 10.0, `sqrt` of a huge int gives `inf`.
- Fix the macOS failure in the `Tests` workflow (`.github/workflows/tests.yml`, formerly part of `Test and publish the website`)
  Open the latest failed run on GitHub and fix the macOS test failure (needs repo admin to read logs). Every run since #59 fails near the end of the log; the website now deploys through `site/check.sh`, so this no longer blocks it.
- Make a lost LTO visible and re-measure the v0.51 Linux benchmarks
  `native/tomato` hides a failed `-flto` link and links without LTO. Warn on that fallback, test that LTO happened, and fix `release/linux-setup.sh` (its clang cannot load `LLVMgold.so`, and its `lld` lacks `libxml2`). Then re-measure the v0.51 Linux column, which was measured without LTO. See `docs/architecture-review.md`, section 3.3.
- Join the compiler's output in `compile_with` instead of appending
  Build it with a list and one join instead of appending to a 10 MB string (self-compile 24.0 s to 9.9 s in an experiment, identical output). See `docs/architecture-review.md`, section 3.3.
- Cache the compiled runtime
  For `tomato run`, `tomato build` and `tests/run.sh`, keyed on mode, clang version and runtime hash. Linking a prebuilt runtime took 0.4 to 0.6 s instead of 1.5 to 1.75 s, with an identical binary. See `docs/architecture-review.md`, section 3.3.
- Report failed text file writes and closes
  `tomato_file_write` and `tomato_file_close` in `runtime/tomato_rt.c` ignore the results of `fwrite` and `fclose`, so a full disk loses data silently.
- Say what is unsupported instead of E318 "write its type"
  For types that are written but not built, such as `dict[int, str]` and `int | None`. See the probes in `docs/architecture-review.md`, section 3.6.
- Refill `tests/known_gaps/` and fix the drifted docs
  P26, P65, P83 and P85 in `docs/provisional.md`, the status table in `docs/specification.md`, and `docs/open-questions.md`. See `docs/architecture-review.md`, section 3.7.
- Test unattended release signing on the iMac
  Test signing after a restart, from an ssh session and after sleep, and run a `--no-linux` release attempt that must be refused at publish. v0.51 only showed prompt-free signing from byre sessions; the gate's refusal was only tested with stubbed state.
- Re-run the Linux benchmarks on a quieter biggie
  The v0.51 Linux x86-64 numbers were taken at load about 75; run them again when biggie's load is below 32.
- Fix the compiler bug `set.discard(x)`
  `set_method` implements only `add` and `remove`, but the error text for set methods lists `discard` (and the lint's loop-change check names it), so `s.discard(x)` is rejected with "set has no method 'discard'". Found by the documentation review; see `docs/documentation-review.md`.
- Verify browser entropy for the playground
  The wasm `random_get` path (`site/wasm/wasi.js` -> `crypto.getRandomValues`) was only exercised under node, so `secrets` and `uuid4` in a real browser are unverified.
- Add timedelta total_seconds, negation, multiplication and datetime replace/combine/timestamp
  These are not in the approved Wave 1 datetime sheet, so `std/datetime.tom` lacks them.
- Allow comparing a function's `tuple[int, int]` result with a tuple literal
  Today `divmod(a, b) == (q, r)` does not compile because mixed and same-type tuple literals are different types.
- Teach the VS Code grammar and website highlighter about f-string format specs
  `{x:spec}` in an f-string has a format spec after the colon.
- Mark error branches as unlikely in the emitted LLVM IR (`!prof` weights on `fail_if`)
  An experiment gave matmul -2.4% and strings -0.7% but sieve +2.2% and objects +0.7% instructions executed; it needs tuning, and site/wasm/llvm.js must accept the metadata.
