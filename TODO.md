- Build the approved Wave 2 packs as Sonnet tasks
  After Davis answers the questions in `docs/wave2-api-sheets.md`, start build tasks for the approved sheets: `re` and hashing first (Sonnet-sized, pure Tomato), then os/sys, then testing.
- Make a lost LTO visible and re-measure the v0.51 Linux benchmarks
  `native/tomato` hides a failed `-flto` link and links without LTO. Warn on that fallback, test that LTO happened, and fix `release/linux-setup.sh` (its clang cannot load `LLVMgold.so`, and its `lld` lacks `libxml2`). Then re-measure the v0.51 Linux column, which was measured without LTO. See `docs/architecture-review.md`, section 3.3.
- Test unattended release signing on the iMac
  Test signing after a restart, from an ssh session and after sleep, and run a `--no-linux` release attempt that must be refused at publish. v0.51 only showed prompt-free signing from byre sessions; the gate's refusal was only tested with stubbed state.
- Re-run the Linux benchmarks on a quieter biggie
  The v0.51 Linux x86-64 numbers were taken at load about 75; run them again when biggie's load is below 32.
- Use `epoll`/`kqueue` for descriptor waits
  With 4,000 idle sockets a round trip takes about 20 ms, because `poll` itself is slow.
- Fix small async bugs found in the sockets reviews
  An error raised in a `finally` that replaces another leaks the first one; un-started async calls are accepted in some positions and never run; a generator cannot be used in an async function; a task that calls `wait_for` on itself deadlocks.
- Re-measure the full tier on a quiet biggie (load below 32) with `-j 64` and put the real number in tests/README.md
  The test-suite speed-up was measured only at load 70-120 (full tier 125-267 s wall, 2,464-3,849 CPU s), so the one-minute target is not demonstrated. Run `tests/run.sh --times -j 64` when biggie is quiet and record wall, CPU and load.
- Confirm the split bootstrap build on the Mac
  Run `tests/run.sh` on the Mac (and the full tier) to confirm `build-object.sh` takes the split path under macOS's BWK awk and Apple ld rather than the fallback.
- Measure the per-item instruction saving of borrowed loop items on `objects`
  Measure it on a quiet machine (perf stat or valgrind).
- Widen the loop-item borrowing
  Cover methods that call other proven list-safe methods, and loops over non-class items.
