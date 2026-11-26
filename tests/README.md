# The test suite

`tests/run.sh` is the whole suite, in shell; it needs only clang (node or macOS's jsc for the WebAssembly checks, `expect` for the
repl history check). `tests/run.sh --help` prints the usage.

```
tests/run.sh                 the full suite: what CI and a release run
tests/run.sh --fast          a representative subset, for the edit-and-test loop and for an agent's check before a merge
tests/run.sh -j N            N tests at a time (TOMATO_TEST_JOBS=N)
tests/run.sh --times         after the summary: the 20 slowest tests and the time per section
```

## Browser entropy check

Serve the repository over HTTP on localhost (a secure context for Web Crypto) and open
`site/wasm/entropy-test.html` in a browser. It compiles and runs a Tomato program twice, compares its token and UUID
with the actual bytes supplied by `crypto.getRandomValues`, and reports PASS or FAIL. This supplements the JavaScript-shell
WebAssembly checks; it is not run by `tests/run.sh`.

## The two tiers

**Full** (no flag) runs every test. **`--fast`** (or `TOMATO_TEST_FAST=1`) runs the same kinds of check on fewer programs of the kinds
that have many. At its end it prints `fast tier: N tests were not run` and the exact list, `SECTION: NAME`, so a skipped test is never
silent. What it skips:

| Where | Full runs | `--fast` runs | Skipped |
| --- | --- | --- | --- |
| memory (AddressSanitizer builds of programs) | 128 | 49 (`fast_asan` in `tests/run.sh`) | 79 |
| release mode (AddressSanitizer) | 10 programs | 4: `fast_paths`, `loop_nests`, `int_ranges`, `containers` | 6 |
| WebAssembly (programs, rejected programs, runtime errors) | 109 | 36 (`fast_wasm`) | 73 |
| command line: release mode runs like debug mode | 10 programs | 3: `int_boundary`, `containers`, `cycle` | 7 |
| benchmarks smoke | 25 benchmarks, each in Tomato and go, rust, python, c, javascript | 6 (`fib sieve strings sort wordcount hof`), each in Tomato and c, python | 19 benchmarks (and, for the six, go, rust, javascript) |

That was 755 checks in the full suite and 654 in the fast tier (101 skipped) before the Wave 2 packs (`re`, hashing and binary, `os`/`sys`, testing), which added about 30 programs, 17 AddressSanitizer builds, a dozen WebAssembly programs and the `tomato test`, exit-status and `sys.version` checks; the ASan rows and the program count above are recounted, the other rows and totals are not; the fast tier takes a little over half the CPU time.
Everything else runs in both tiers: the compiler and its fixed point, the install, the 14 examples, all 200 programs with expected output,
the 103 rejected programs and 76 error messages, the 63 runtime errors, the input, error-id, known-gaps, highlighter and release-file checks, and
the rest of the command line (the update, the runtime cache, `explain`, the repl, colors, warnings, modes). Which tests were skipped is printed at the
end of every `--fast` run, as `SECTION: NAME`.

The fast tier still builds the compiler and the installed `tomato` and runs the command-line parts, so its wall time has a floor
(see below); what it saves is CPU, which is what counts on a small or busy machine. A change that touches one of the skipped areas
(the runtime's memory handling, the wasm path, release mode) should run the full suite before it lands.

## Why the full suite is quick

* **Parallel.** Each test is a function that runs in a job of its own with its own temp folder. `-j` defaults to half the cores (at
  most 64), and less on a busy machine (about half of the idle cores, at least 4). Whatever `-j` is, the output is the same and in the
  same order, and so are the count and the exit status.
* **Longest first.** The tests are registered in the order of the output and started in the order that is best for the wall time:
  the install and the compiler build first (everything but the tests listed next waits for the compiler, the command-line tests for the
  install); the WebAssembly and other checks that need neither start at once, in the time the compiler takes; then the longest tests
  (benchmarks, AddressSanitizer builds), then the rest. A test that is waiting for the install is not given a job slot until it is done.
* **One compiled runtime.** `runtime/tomato_rt.c` is compiled once per flag set and kept in the cache that `tomato run` uses
  (`native/rtcache.sh`: `~/.cache/tomato`, `~/Library/Caches/tomato` on macOS, or `$TOMATO_CACHE_DIR`; `TOMATO_CACHE=off` turns it
  off). A test links the stored object instead of compiling 5,000 lines of C again (10 s of CPU each). The variants (the leak test's
  runtime without a free, the heapsort fallback, no entropy) are cached by their flags and text too. The first run on a machine fills
  the cache; after that a runtime that did not change costs nothing.
* **One compiler.** `c1`, the compiler the tests use, is built from `compiler/bootstrap/tomatoc.ll` by `c0`; when `c0` reproduces the
  checked-in IR (the normal case, which `fixed_point` checks) `c1` is the same program as `c0`, so it is not built a second time. When
  the IR is stale, `c1` is built as before and the tests use it. The benchmark smoke runs use it too, instead of each building its own.
* **One build for two tests.** A program that is both a "decided rules" program and an AddressSanitizer test (90 of them) is compiled
  once, with AddressSanitizer, and run for both tests: the output check compares the output of that build (the same IR at `-O1` with
  the sanitizer's checks added), and the memory check looks at its standard error. This is the one place where a check is made on a
  different build than it was before: the plain `-O1` build of those 90 programs is no longer made separately.
* **Long tests are split.** The command-line tests that were one long test each (`modes`, `repl`, `color`, `warnings`, `runtime_cache`,
  `no_lto`, and the requests) are several independent parts, so they spread across jobs. `update` starts from a stand-in install (the
  `tomato` script and a VERSION, laid out as `install-native.sh` lays them out) rather than a full second install, because the update
  makes the real one. `runtime_cache` uses a copy of the command made from the compiler just built, so it does not wait for the install.
* **The benchmark smoke is one test per benchmark**, beside the others: it checks only that every version prints what Tomato prints
  (tiny inputs; nothing is timed), so it does not have to run alone.
* **`install-native.sh` compiles the IR and the runtime at the same time**, and then links them (same flags, same program). The IR is
  compiled by `compiler/bootstrap/build-object.sh`, in eight parts at once (`split.awk` cuts it; the checked-in file is unchanged), and
  falls back to one clang process if that fails. In the suite, the compiler build uses that script, and both installs (the installed
  command and the update's) are given its object through `TOMATO_TEST_BOOTSTRAP_OBJECT` (a test-only variable the script honours), so the
  13 MB is compiled once, not three times; the runtime compile and the link in the installer are still done for real. A separate test
  checks that the release archive ships the script and `split.awk` and that the unpacked `split.awk` splits its IR.

## What bounds the wall time

Test CPU time is what the machine pays: 2,500 to 4,100 CPU seconds for the full suite (the top of the range is a run with node and expect installed, which adds the WebAssembly
and repl-history checks; see the measurement below) and 1,900 to 2,500 for `--fast` (before this work:
5,900), the range being how much slower clang runs on the shared 128-core machine when other work keeps the load average near 100. With
`-j N` the wall time cannot be below the CPU time divided by N, plus what cannot be spread: **the compiler's IR (13 MB) is compiled once** (one core: 25 s on a quiet machine, up to 85 s on a busy one; the installs reuse its object),
then the longest command-line part that follows the install (5 to 15 s), and the update test, which compiles it once more from the release
archive. So the chain is about an IR compile plus one command-line part, and the rest is CPU divided by the jobs. `--times` shows both:
`compiler_build`, `install` and `cli_update` at the top of the slowest list are the chain; the per-section table gives wall and CPU
seconds. Compare wall times with the load average (`uptime`), and CPU seconds with CPU seconds.

## Measured full-tier time

`tests/run.sh --times -j 64` on the shared 128-core Linux machine (biggie), 25 November 2026, with clang 21, node 22 and expect on
`PATH` (Go is not installed, so the Go versions in the benchmark smoke are skipped). **The machine was not quiet**: another account's
58 CPU-bound jobs kept the load average at about 65 before each run, and the run itself pushes it to about 100, so these are
loaded numbers, not the quiet-machine number (one single-core benchmark run of another task also overlapped them) (the load never fell below 32 in the days this was tried).

| Run | Load average at start, peak | Wall | CPU (user + system) | Result |
| --- | --- | --- | --- | --- |
| Full, `-j 64` | 65, 107 | **112 s** | 4,123 s (3,442 + 681) | 846 passed, 1 failed |
| Full, `-j 64` (repeat) | 82 (the tail of the run before), 98 | 110 s | 4,114 s (3,420 + 694) | 846 passed, 1 failed |

The one failure, both times, is `repl: up-arrow recalls a multi-line block as one history entry`: its `expect` session sleeps between
keys, and here `expect` is a hand-unpacked package, so it is not known whether the cause is the load or that `expect`; every other check passed. It is a known failure that has not been
diagnosed yet, so a red `repl: up-arrow` line in a full run on a busy machine is not necessarily a regression.
Wall time is the elapsed time of `/usr/bin/time -v`; CPU is its user and system time (the `--times` footer's summed test CPU was 4,000 s).

So the full tier took about **1 min 50 s** at load 65 to 100, which is not the one-minute target. The numbers fit the bound above: 4,100 CPU
seconds over 64 jobs is 64 s, and the compiler's IR compile plus the command-line chain add to that; with the machine's other jobs taking cores the
wall time is longer still. The one-minute target needs either a quiet machine or less CPU; it is not demonstrated here.

## WebAssembly checks under load

The wasm path interprets the program in JavaScript with a time limit. `tests/run.sh` gives it 30 s (the website's 5 s is too short on a
busy machine; `TOMATO_WASM_TIMEOUT_MS` changes it, and jsc, which has no environment, gets it as `--timeout-ms`). A run that the limit
stopped (the toolchain prints `error[E369]`) is run again with three times the limit, at most three runs; a wrong answer, a compile
error or a crash is the first run's result and is never run again, so a retry cannot hide a real failure.

## Adding a test

Write `t_NAME` (it runs in `$work`, its own folder), and register it where it belongs with `spawn t_NAME args` (or `spawn_first` for one
that takes more than a few seconds, `spawn_cli` for one that uses the installed `tomato`, `last` for one that must run alone). Report
with `ok`, `bad` or `check`. For the fast tier, a test that is one of many alike should be listed in the sample (`fast_asan`,
`fast_wasm`, ...) or skipped with `skip NAME` when `$fast` is set.

## Tables generated from Python

`tests/programs/ospath_text.tom` and `tests/regex/cases.txt` hold data that was produced once by running Python 3.14.4 and then committed; no script that needs Python is kept in the repository. `ospath_text.tom` has 293 calls of `join`, `split`, `splitext`, `basename`, `dirname`, `isabs`, `normpath` and `relpath` on a fixed list of paths (empty, rooted, doubled slashes, dotted names, non-ASCII), each with the result of the same function in `posixpath`; `tests/regex/README.md` describes the regex rows. To extend either table, produce the new rows from Python the same way and append them with their expected results.
