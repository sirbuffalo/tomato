- Rebuild `site/wasm` on the Mac before the next release
  macOS arm64, WASI SDK 24: the error-path temporaries task landed a Linux-built `tomatoc.wasm`. It was built with the host-independent `site/wasm/build.sh`, so the Mac rebuild should give the same bytes ("wasm files rebuild identically").
- Build the approved Wave 2 packs as Sonnet tasks
  After Davis answers the questions in `docs/wave2-api-sheets.md`, start build tasks for the approved sheets: `re` and hashing first (Sonnet-sized, pure Tomato), then os/sys, then testing.
- Build Lock/Semaphore/Event on the Queue's waiter primitive
  After Davis answers the decisions in `docs/locks-design.md` section 9, build Lock/Semaphore/Event on the Queue's waiter primitive.
- Fix the macOS failure in the `Tests` workflow (`.github/workflows/tests.yml`, formerly part of `Test and publish the website`)
  The macOS (and Linux) job logs need repo admin, so the exact failing check was never read. A first round of fixes landed (jsc now honors the wasm time limit, the benchmarks smoke test skips a missing go or rust, `hdiutil` retries), and a failed run now writes its FAIL lines to annotations and the job summary, which anyone can read (`tests/ci_report.sh`). Check the next run's annotations: if the job is still red, fix the check named there.
- Make a lost LTO visible and re-measure the v0.51 Linux benchmarks
  `native/tomato` hides a failed `-flto` link and links without LTO. Warn on that fallback, test that LTO happened, and fix `release/linux-setup.sh` (its clang cannot load `LLVMgold.so`, and its `lld` lacks `libxml2`). Then re-measure the v0.51 Linux column, which was measured without LTO. See `docs/architecture-review.md`, section 3.3.
- Cache the compiled runtime
  For `tomato run`, `tomato build` and `tests/run.sh`, keyed on mode, clang version and runtime hash. Linking a prebuilt runtime took 0.4 to 0.6 s instead of 1.5 to 1.75 s, with an identical binary. See `docs/architecture-review.md`, section 3.3.
- Report failed text file writes and closes
  `tomato_file_write` and `tomato_file_close` in `runtime/tomato_rt.c` ignore the results of `fwrite` and `fclose`, so a full disk loses data silently.
- Say what is unsupported instead of E318 "write its type"
  For types that are written but not built, such as `dict[int, str]` and `int | None`. See the probes in `docs/architecture-review.md`, section 3.6.
- Test unattended release signing on the iMac
  Test signing after a restart, from an ssh session and after sleep, and run a `--no-linux` release attempt that must be refused at publish. v0.51 only showed prompt-free signing from byre sessions; the gate's refusal was only tested with stubbed state.
- Re-run the Linux benchmarks on a quieter biggie
  The v0.51 Linux x86-64 numbers were taken at load about 75; run them again when biggie's load is below 32.
- Verify browser entropy for the playground
  The wasm `random_get` path (`site/wasm/wasi.js` -> `crypto.getRandomValues`) was only exercised under node, so `secrets` and `uuid4` in a real browser are unverified.
- Mark error branches as unlikely in the emitted LLVM IR (`!prof` weights on `fail_if`)
  An experiment gave matmul -2.4% and strings -0.7% but sieve +2.2% and objects +0.7% instructions executed; it needs tuning, and site/wasm/llvm.js must accept the metadata.
- Add the other languages' versions of the 15 new benchmarks
  After the multi-language harness (JavaScript, Java, C, C++, C#, TypeScript, PHP, Swift; branch `byre/tskSQTqy23EMBy`) lands on main, add the other languages' versions of nbody, spectral_norm, fannkuch, nqueens, binary_trees, levenshtein, knapsack, life, dijkstra, quicksort, kmers, revcomp, tokenize, crc32 and hof, following its `<name>/<name>.<ext>` convention.
- Publish results for all 25 benchmarks and update the "ten benchmarks" text
  At the next release run, publish results for all 25 benchmarks (`benchmarks/run.sh --site`) and update the "ten benchmarks" text on `site/index.html` and `site/benchmarks.html`.
- Confirm on a Mac that the Linux-built `site/wasm/tomatoc.wasm` rebuilds identically (WASI SDK 24, arm64)
  The `std/builtin/` folder task landed a Linux-built `tomatoc.wasm`. Run `WASI_SDK=~/wasi-sdk-24.0-arm64-macos sh tests/run.sh` and look for "wasm files rebuild identically"; if it fails, run `site/wasm/build.sh` there and commit the result.
- Rerun the benchmark suite on the Mac with the new languages installed
  `benchmarks/run.sh --site` there, so the live page gets the new Tomato numbers, the fifteen newer benchmarks and the eight added languages; then update the page's text, which still describes the v0.51 numbers.
- Write the fifteen newer benchmarks in the eight added languages
  JavaScript, TypeScript, Java, C, C++, C#, PHP and Swift, 120 programs in all.
- Stop retaining the loop item in `for x in xs` when the body cannot change any list
  Needs a whole-program check of which functions change lists; about 8 of the instructions per item in `objects`.
- Divide big integers 64 bits at a time
  Division still works 32 bits at a time; a fuzz program with very large numbers took 70 s against Python's 3 s.
- Use `epoll`/`kqueue` for descriptor waits
  With 4,000 idle sockets a round trip takes about 20 ms, because `poll` itself is slow.
- Let sockets, requests and timeouts run while a task waits for input
  Today `await input()` stops everything until a line comes.
- Add UDP and a public `getaddrinfo` to `socket`
  Also do name lookup without blocking every task.
- Fix small async bugs found in the sockets reviews
  An error raised in a `finally` that replaces another leaks the first one; un-started async calls are accepted in some positions and never run; a generator cannot be used in an async function; a task that calls `wait_for` on itself deadlocks.
