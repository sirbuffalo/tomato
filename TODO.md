- Build the approved Wave 2 packs as Sonnet tasks
  After Davis answers the questions in `docs/wave2-api-sheets.md`, start build tasks for the approved sheets: `re` and hashing first (Sonnet-sized, pure Tomato), then os/sys, then testing.
- Publish the LTO Linux timings
  The v0.51 Linux wall-clock snapshot and Linux time columns in `docs/performance.md` (and `site/benchmarks.json`, which has no Linux numbers) were measured without LTO; the instruction counts are already re-measured (`benchmarks/results/linux-x86_64/instructions.md`). After the "Re-run the Linux benchmarks on a quieter biggie" item lands (use `~/.tomato-release/linux-tools/bin` first on PATH; run `release/check-lto.sh` first), replace the timing numbers and remove the non-LTO notes in `docs/performance.md`. Also run the full tier of `tests/run.sh` once on a quiet biggie with `TOMATO_TEST_REQUIRE_LTO=1`, and one real `release/release.sh` Linux step (the fast tier with it set passed, 630 tests; the release path was not run).
- Test unattended release signing on the iMac
  Test signing after a restart, from an ssh session and after sleep, and run a `--no-linux` release attempt that must be refused at publish. v0.51 only showed prompt-free signing from byre sessions; the gate's refusal was only tested with stubbed state.
- Re-run the Linux benchmarks on a quieter biggie
  The v0.51 Linux x86-64 numbers were taken at load about 75; run them again when biggie's load is below 32.
- Re-measure the full tier on a quiet biggie (load below 32) with `-j 64` and put the real number in tests/README.md
  The test-suite speed-up was measured only at load 70-120 (full tier 125-267 s wall, 2,464-3,849 CPU s), so the one-minute target is not demonstrated. Run `tests/run.sh --times -j 64` when biggie is quiet and record wall, CPU and load.
- Confirm the split bootstrap build on the Mac
  Run `tests/run.sh` on the Mac (and the full tier) to confirm `build-object.sh` takes the split path under macOS's BWK awk and Apple ld rather than the fallback.
- Measure the per-item instruction saving of borrowed loop items on `objects`
  Measure it on a quiet machine (perf stat or valgrind).
- Widen the loop-item borrowing
  Cover methods that call other proven list-safe methods, and loops over non-class items.
- Find why collatz executes more instructions than at v0.51
  collatz executes 17% (plain or LTO link) to 24% (bitcode-merge link) more instructions at d83f43b0 than at v0.51 (70.3 M to 82–87 M, counting input, Linux x86-64). Compare the emitted IR at the two trees. Numbers: `benchmarks/results/linux-x86_64/lto-effect.md`.
- Check why fib executes more instructions with the runtime inlined
  fib executes 9% more instructions with the runtime inlined (bitcode merge or LTO) than with a plain link at d83f43b0 (123.5 M vs 113.0 M). Check the inliner's choices and whether the Linux timings agree. Numbers: `benchmarks/results/linux-x86_64/lto-effect.md`.
