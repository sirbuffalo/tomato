- Build the approved Wave 2 packs as Sonnet tasks
  After Davis answers the questions in `docs/wave2-api-sheets.md`, start build tasks for the approved sheets: `re` and hashing first (Sonnet-sized, pure Tomato), then os/sys, then testing.
- Build Lock/Semaphore/Event on the Queue's waiter primitive
  After Davis answers the decisions in `docs/locks-design.md` section 9, build Lock/Semaphore/Event on the Queue's waiter primitive.
- Make a lost LTO visible and re-measure the v0.51 Linux benchmarks
  `native/tomato` hides a failed `-flto` link and links without LTO. Warn on that fallback, test that LTO happened, and fix `release/linux-setup.sh` (its clang cannot load `LLVMgold.so`, and its `lld` lacks `libxml2`). Then re-measure the v0.51 Linux column, which was measured without LTO. See `docs/architecture-review.md`, section 3.3.
- Test unattended release signing on the iMac
  Test signing after a restart, from an ssh session and after sleep, and run a `--no-linux` release attempt that must be refused at publish. v0.51 only showed prompt-free signing from byre sessions; the gate's refusal was only tested with stubbed state.
- Re-run the Linux benchmarks on a quieter biggie
  The v0.51 Linux x86-64 numbers were taken at load about 75; run them again when biggie's load is below 32.
- Mark error branches as unlikely in the emitted LLVM IR (`!prof` weights on `fail_if`)
  An experiment gave matmul -2.4% and strings -0.7% but sieve +2.2% and objects +0.7% instructions executed; it needs tuning, and site/wasm/llvm.js must accept the metadata.
- Rerun the benchmark suite on the Mac with the new languages installed
  `benchmarks/run.sh --site` there, so the live page gets the new Tomato numbers, the fifteen newer benchmarks and the eight added languages; then update the page's text, which still describes the v0.51 numbers.
- Stop retaining the loop item in `for x in xs` when the body cannot change any list
  Needs a whole-program check of which functions change lists; about 8 of the instructions per item in `objects`.
- Use `epoll`/`kqueue` for descriptor waits
  With 4,000 idle sockets a round trip takes about 20 ms, because `poll` itself is slow.
- Let sockets, requests and timeouts run while a task waits for input
  Today `await input()` stops everything until a line comes.
- Fix small async bugs found in the sockets reviews
  An error raised in a `finally` that replaces another leaks the first one; un-started async calls are accepted in some positions and never run; a generator cannot be used in an async function; a task that calls `wait_for` on itself deadlocks.
- Re-measure the full tier on a quiet biggie (load below 32) with `-j 64` and put the real number in tests/README.md
  The test-suite speed-up was measured only at load 70-120 (full tier 125-267 s wall, 2,464-3,849 CPU s), so the one-minute target is not demonstrated. Run `tests/run.sh --times -j 64` when biggie is quiet and record wall, CPU and load.
- Split the 13 MB compiler IR so it compiles in parallel (it is the unspreadable chain)
  `compiler/bootstrap/tomatoc.ll` compiles in one clang process (25 s quiet, 46-85 s busy); the test suite's wall time cannot go below that plus the longest command-line part.
