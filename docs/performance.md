# Performance notes

What the benchmarks (`benchmarks/`, results on the website's Benchmarks page) say about the compiler and runtime, and
what has been done about it. Every change below was measured with `benchmarks/run.sh` (wall-clock seconds, release mode,
median) or `benchmarks/count.sh` (instructions executed), mostly on the same Apple M1 (the Linux checks say so; the newest Mac numbers, on an M3 Pro, are in the first snapshot below), and kept
only when it helped.

## Mac (Apple M3 Pro) snapshot (2026-11-25)

Tomato v0.51, on macOS 27.0.1, Apple M3 Pro (12 cores), 36 GB RAM, a laptop on battery power. All 25 benchmarks in all twelve languages (Tomato in release and debug mode, Go, Rust, Python, C, C++, Java, C#, Swift, JavaScript, TypeScript and PHP) ran ten times in one shuffled order (seed 1); values are median wall-clock seconds. The Mac had restarted a few minutes before the run, so the load averages were 18.41, 45.54, 46.58 before (still settling; 3 to 7 while the programs ran) and 3.43, 4.20, 8.29 after. Node 26.13.1, PHP 8.6.0 and .NET 10.0.404 were not installed on the Mac and came from private, user-local installs. Full measurements are in `benchmarks/results/results.md` and `raw.tsv`; the website's Benchmarks page draws them from `site/benchmarks.json`. They replace the Apple M1 numbers (ten benchmarks, four languages) that the page showed before; the v0.51 snapshot below keeps those.

**The float slowdown of `bf46a4ee`, and why the two Linux runs disagreed.** The Linux snapshot below was labelled `f533dbd0`, but it was measured in a worktree based on `c1fae360`, which is `bf46a4ee^`, the commit before floats of any size: `main` (with `bf46a4ee`) was merged into that worktree only after the run, and the label was main's tip when the text was written (the measured tree differs from `c1fae360` only in result files). So the table below has no float slowdown, while a clean `git archive` of `f533dbd0` (`benchmarks/results/linux-x86_64/results-f533dbd0.md`, unpinned, load about 62) does: mandelbrot 0.265 s, nbody 0.671 s and spectral_norm 0.215 s against 0.090, 0.222 and 0.109 s. Callgrind agrees: `bf46a4ee` raised mandelbrot from 35.5 M to 269.0 M instructions, nbody from 115.6 M to 396.5 M and spectral_norm from 75.9 M to 131.3 M. In the emitted IR, a float variable might hold a box, so every assignment tested and freed the old value and every operation merged a runtime result back in; a product or quotient that came out as zero always went to the runtime, because it might have underflowed (mandelbrot starts every point at `zr = zi = 0.0`); and `math.sqrt` had grown too large to be inlined. Stage 5 of `docs/bigfloat-design.md` (D77e) gave floats a fast copy in loop nests: mandelbrot is back to 0.10 s on Linux (76.0 M instructions), nbody 0.33 s (244.8 M) and spectral_norm 0.16 s (102.2 M); the details and the M3 Pro and browser numbers are in that document's "Stage 5 as built".

| Benchmark | Tomato (s) | Tomato ÷ Go | Tomato ÷ Rust | Tomato ÷ Python |
| --- | ---: | ---: | ---: | ---: |
| fib | 0.175 | 1.12 | 1.23 | 0.05 |
| sieve | 0.069 | 1.03 | 0.97 | 0.01 |
| matmul | 0.123 | 2.15 | 1.91 | 0.02 |
| mandelbrot | 0.093 | 0.95 | 0.99 | 0.01 |
| collatz | 0.158 | 0.71 | 1.05 | 0.01 |
| strings | 0.111 | 0.76 | 0.90 | 0.15 |
| sort | 0.099 | 0.36 | 1.16 | 0.03 |
| wordcount | 0.227 | 0.86 | 0.62 | 0.19 |
| bigint | 0.123 | 1.65 | 1.01 | 0.18 |
| objects | 0.061 | 0.68 | 0.99 | 0.02 |
| nbody | 0.105 | 0.78 | 1.43 | 0.02 |
| spectral_norm | 0.089 | 1.48 | 2.26 | 0.02 |
| fannkuch | 0.233 | 1.16 | 1.29 | 0.01 |
| nqueens | 0.049 | 1.03 | 1.11 | 0.11 |
| binary_trees | 0.294 | 3.87 | 2.38 | 0.23 |
| levenshtein | 0.091 | 2.37 | 1.83 | 0.01 |
| knapsack | 0.077 | 2.03 | 2.11 | 0.01 |
| life | 0.109 | 1.83 | 1.94 | 0.03 |
| dijkstra | 0.045 | 1.14 | 1.90 | 0.04 |
| quicksort | 0.184 | 1.18 | 1.27 | 0.05 |
| kmers | 0.236 | 2.42 | 2.80 | 0.18 |
| revcomp | 0.027 | 0.25 | 0.63 | 0.07 |
| tokenize | 0.100 | 0.96 | 1.33 | 0.08 |
| crc32 | 0.095 | 0.99 | 1.24 | 0.03 |
| hof | 0.072 | 0.36 | 1.29 | 0.04 |

## Linux x86-64 snapshot (2026-11-25)

Tomato v0.51 plus later work (`c1fae360`, the commit before floats of any size; first published as `f533dbd0`, see the note above), built with link-time optimisation (`release/check-lto.sh` passed before the run), on Ubuntu 26.04.1 LTS, AMD Ryzen Threadripper 3990X (64 physical cores, 128 logical CPUs), 247 GB RAM. Each program ran ten times in one shuffled order (seed 1); values are median wall-clock seconds. This is not a quiet-machine run: biggie's one-, five-, and fifteen-minute load averages were 66.44, 71.05, 72.33 before and 60.91, 61.63, 63.40 after (mostly another user's long-running jobs, which were left alone), so the run was pinned to 6 otherwise idle CPUs. Its spread is still large: the median of (max - min) / median over the 325 program-language pairs is 54%, and 284 of them are above 20%. Read differences below about 20% as noise. Full measurements are in `benchmarks/results/linux-x86_64/results.md` and `raw.tsv`; earlier website numbers were measured on an Apple M1 Mac and are not directly comparable.

| Benchmark | Tomato (s) | Tomato ÷ Go | Tomato ÷ Rust | Tomato ÷ Python |
| --- | ---: | ---: | ---: | ---: |
| fib | 0.225 | 0.88 | 1.53 | 0.04 |
| sieve | 0.745 | 0.91 | 0.94 | 0.11 |
| matmul | 0.156 | 1.25 | 1.20 | 0.02 |
| mandelbrot | 0.090 | 0.97 | 0.98 | 0.01 |
| collatz | 0.166 | 0.62 | 1.03 | 0.01 |
| strings | 0.784 | 1.39 | 0.85 | 0.28 |
| sort | 0.306 | 0.74 | 0.88 | 0.04 |
| wordcount | 0.277 | 0.65 | 0.65 | 0.14 |
| bigint | 0.142 | 0.72 | 1.06 | 0.40 |
| objects | 1.048 | 1.13 | 0.90 | 0.11 |
| nbody | 0.222 | 1.55 | 2.64 | 0.03 |
| spectral_norm | 0.109 | 1.66 | 1.78 | 0.02 |
| fannkuch | 0.277 | 1.32 | 1.32 | 0.01 |
| nqueens | 0.064 | 1.03 | 1.15 | 0.10 |
| binary_trees | 0.409 | 2.12 | 1.53 | 0.23 |
| levenshtein | 0.130 | 1.55 | 1.74 | 0.01 |
| knapsack | 0.070 | 1.41 | 1.90 | 0.01 |
| life | 0.133 | 1.21 | 1.70 | 0.03 |
| dijkstra | 0.094 | 1.12 | 1.25 | 0.05 |
| quicksort | 0.323 | 1.30 | 1.21 | 0.04 |
| kmers | 0.406 | 1.11 | 1.43 | 0.17 |
| revcomp | 0.099 | 0.19 | 0.30 | 0.16 |
| tokenize | 0.248 | 0.64 | 0.67 | 0.12 |
| crc32 | 0.222 | 0.81 | 0.89 | 0.04 |
| hof | 0.205 | 0.52 | 2.08 | 0.05 |

## v0.51 snapshot

v0.51, median of 10 runs per program (Python too), all runs in one shuffled order (seed 1), Apple M1, load average (1, 5 and 15 minutes) 1.40 1.97 2.33 before and 3.00 2.56 2.39 after. Written by `release/perf-snapshot.sh` from `benchmarks/results/results.md`, which has the full tables. Seconds (release mode): fib 0.156, sieve 0.068, matmul 0.144, mandelbrot 0.102, collatz 0.206, strings 0.178, sort 0.111, wordcount 0.207, bigint 0.111, objects 0.113.

Linux x86-64 (`benchmarks/results/linux-x86_64/v0.51-lto/results.md`: this v0.51 tree, `14b191e3`, built with link-time optimisation and measured again on 2026-11-25): AMD Ryzen Threadripper 3990X 64-Core Processor, 128 logical CPUs (the run was pinned to 6 otherwise idle ones), median of 10 runs, seed 1, load average 89.69, 69.90, 65.89 before and 64.87, 65.25, 65.04 after. It is a shared machine, not a quiet one, and the min-to-max spread of many programs is 50% or more: read differences below about 20% as noise. Seconds (release mode): fib 0.250, sieve 0.843, matmul 0.244, mandelbrot 0.104, collatz 0.296, strings 1.552, sort 0.418, wordcount 0.294, bigint 0.144, objects 1.203.

Tomato's time divided by each language's time (below 1.0 Tomato is faster, above 1.0 it is slower):

| benchmark | Tomato ÷ Go (Mac) | Tomato ÷ Rust (Mac) | Tomato ÷ Python (Mac) | Tomato ÷ Go (Linux) | Tomato ÷ Rust (Linux) | Tomato ÷ Python (Linux) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| fib | 1.12 | 1.26 | 0.02 | 0.99 | 1.84 | 0.05 |
| sieve | 1.18 | 1.28 | 0.02 | 1.03 | 0.99 | 0.12 |
| matmul | 2.35 | 2.23 | 0.02 | 1.92 | 1.98 | 0.03 |
| mandelbrot | 1.08 | 1.15 | 0.01 | 1.13 | 1.12 | 0.01 |
| collatz | 1.07 | 1.52 | 0.01 | 1.10 | 1.83 | 0.02 |
| strings | 1.35 | 1.66 | 0.19 | 3.17 | 2.04 | 0.59 |
| sort | 0.45 | 1.40 | 0.05 | 1.06 | 1.13 | 0.06 |
| wordcount | 0.89 | 0.64 | 0.14 | 0.64 | 0.68 | 0.15 |
| bigint | 1.56 | 1.03 | 0.17 | 0.82 | 1.10 | 0.40 |
| objects | 1.17 | 1.94 | 0.02 | 1.36 | 1.04 | 0.13 |

Instructions executed (deterministic, `benchmarks/count.sh`, callgrind), Tomato's count divided by each language's (below 1.0 Tomato executes fewer): arm64 in a Linux VM on the Mac, and x86-64 on the Linux machine.

| benchmark | Tomato ÷ Go (arm64) | Tomato ÷ Rust (arm64) | Tomato ÷ Python (arm64) | Tomato ÷ Go (x86-64, LTO) | Tomato ÷ Rust (x86-64, LTO) | Tomato ÷ Python (x86-64, LTO) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| fib | 1.15 | 2.16 | 0.04 | 1.78 | 2.73 | 0.05 |
| sieve | 1.93 | 1.75 | 0.02 | 2.12 | 1.99 | 0.02 |
| matmul | 2.51 | 2.38 | 0.02 | 2.47 | 2.50 | 0.03 |
| mandelbrot | 1.96 | 2.19 | 0.01 | 2.07 | 2.72 | 0.01 |
| collatz | 1.51 | 1.52 | 0.01 | 1.32 | 1.52 | 0.01 |
| strings | 1.18 | 1.33 | 0.16 | 1.00 | 1.13 | 0.19 |
| sort | 1.10 | 1.99 | 0.05 | 1.01 | 1.42 | 0.05 |
| wordcount | 0.74 | 0.57 | 0.14 | 0.81 | 0.65 | 0.17 |
| bigint | 2.03 | 0.95 | 0.39 | 1.56 | 1.34 | 0.27 |
| objects | 1.21 | 1.90 | 0.04 | 1.09 | 1.88 | 0.05 |

The x86-64 columns are the v0.51 tree (`14b191e3`) built with link-time optimisation: Tomato's counts were re-measured with the fixed toolchain (`benchmarks/results/linux-x86_64/lto-effect.md`), Go's, Rust's and Python's counts are from the published v0.51 run (Tomato's link does not change them). The first published v0.51 Linux counts (fib 3.32, sieve 4.25, matmul 6.91 times Go) were taken with a clang that could not do LTO and silently linked without it; they are kept in `instructions-v0.51-no-lto.md`. `benchmarks/results/linux-x86_64/instructions.md` has the counts of all 25 benchmarks on a later tree (`d83f43b0`, v0.51 plus 25 runtime and compiler changes), also with LTO; on that tree LTO alone changes little, because the compiler now emits most of the fast paths itself (`lto-effect.md`). The wall-clock Linux snapshot above and the Linux time columns are with LTO too (measured at a load of about 65, pinned to 6 idle CPUs, so not quiet: see their notes).

## v0.50 snapshot (earlier)

v0.50, median of 10 runs per program (Python too), all runs in one shuffled order (seed 1), Apple M1, load average about
1.84 (1 minute) before and 1.60 after, with a 15-minute load of 2.93 before the run (iCloud sync and background indexing), so Go and Rust show wide spreads and their ratios may be somewhat inflated. Full tables in `benchmarks/results/results.md`. Seconds
(release mode): fib 0.236, sieve 0.221, matmul 0.172, mandelbrot 0.124, collatz 0.515, strings 0.227, sort 0.119,
wordcount 0.285, bigint 0.111, objects 0.162. Since v0.49 the size-class allocator, in-place string paths and counted
step ranges made strings (0.487 to 0.227), wordcount (0.585 to 0.285), sieve and matmul faster.

Tomato's time divided by each language's time (below 1.0 Tomato is faster, above 1.0 it is slower):

| benchmark | Tomato ÷ Go | Tomato ÷ Rust | Tomato ÷ Python |
| --- | ---: | ---: | ---: |
| fib | 1.74 | 1.90 | 0.03 |
| sieve | 4.19 | 4.28 | 0.05 |
| matmul | 2.91 | 2.71 | 0.02 |
| mandelbrot | 1.34 | 1.40 | 0.01 |
| collatz | 2.63 | 3.78 | 0.03 |
| strings | 1.74 | 2.16 | 0.24 |
| sort | 0.49 | 1.52 | 0.05 |
| wordcount | 1.23 | 0.88 | 0.19 |
| bigint | 1.69 | 1.03 | 0.17 |
| objects | 1.68 | 2.82 | 0.02 |

## v0.49 snapshot (earlier)

v0.49, median of 10 runs per program (Python too), all runs in one shuffled order (seed 1), Apple M1, load average about
2 throughout (iCloud sync and background indexing, so the spread is wide: see benchmarks/results/results.md). An
earlier full run, made before big integers were freed, gave the same medians within 5% on every benchmark except
`bigint` (which was 0.26 to 0.41 s then and is 0.11 s now). Every comparison is Tomato's time divided by the other
language's time: below 1.0 Tomato is faster, above 1.0 it is slower.

Seconds (release mode unless marked; earlier versions from their own runs, with 7 runs each):

| benchmark | v0.46 | v0.48 | v0.49 | v0.49 debug | Go | Rust | Python |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| fib | 0.447 | 0.220 | 0.236 | 0.597 | 0.139 | 0.124 | 8.288 |
| sieve | 0.736 | 0.446 | 0.269 | 0.381 | 0.055 | 0.053 | 4.349 |
| matmul | 0.779 | 0.370 | 0.220 | 0.395 | 0.057 | 0.064 | 7.696 |
| mandelbrot | 0.137 | 0.127 | 0.125 | 0.148 | 0.092 | 0.088 | 9.382 |
| collatz | 1.724 | 0.526 | 0.516 | 1.608 | 0.195 | 0.136 | 14.951 |
| strings | 0.563 | 0.484 | 0.487 | 0.557 | 0.132 | 0.106 | 0.951 |
| sort | 2.110 | 1.167 | 0.118 | 0.129 | 0.244 | 0.078 | 2.441 |
| wordcount | 0.658 | 0.581 | 0.585 | 0.667 | 0.233 | 0.325 | 1.473 |
| bigint | 1.413 | 0.224 | 0.111 | 0.112 | 0.071 | 0.108 | 0.643 |
| objects | 2.749 | 0.329 | 0.184 | 0.234 | 0.097 | 0.057 | 6.677 |

Tomato v0.49 release time ÷ each language's time:

| benchmark | Tomato ÷ Go | Tomato ÷ Rust | Tomato ÷ Python |
| --- | ---: | ---: | ---: |
| fib | 1.69 | 1.91 | 0.03 |
| sieve | 4.92 | 5.13 | 0.06 |
| matmul | 3.87 | 3.46 | 0.03 |
| mandelbrot | 1.36 | 1.41 | 0.01 |
| collatz | 2.64 | 3.79 | 0.03 |
| strings | 3.71 | 4.59 | 0.51 |
| sort | 0.48 | 1.51 | 0.05 |
| wordcount | 2.51 | 1.80 | 0.40 |
| bigint | 1.57 | 1.03 | 0.17 |
| objects | 1.90 | 3.22 | 0.03 |

Notes on the comparison:
- **bigint:** since v0.49 the Rust version uses the `num-bigint` crate (built with cargo, versions pinned in
  `benchmarks/bigint/Cargo.lock`) instead of a hand-written limb loop, as Go uses `math/big` and Python its built-in int.
  Big integers are now freed (see below), which took Tomato from 0.22 to 0.41 s with swings from run to run (it reached
  1.5 GB and its time depended on free memory) down to a steady 0.11 s: about the same as `num-bigint` (1.03) and 1.57
  times Go's `math/big`.
- **sort:** Tomato's `sorted` is an introsort in v0.49, because Davis wants a sort that can later take a compare
  function; the radix sort it replaced took 0.075 s on this input. Rust's `sort()` (a stable merge sort) is faster than
  the introsort again: Tomato ÷ Rust is 1.51, while Tomato ÷ Go is 0.48. A Rust radix sort
  (`benchmarks/sort/sort_radix.rs`) takes 0.036 s, so Tomato ÷ Rust radix sort = 3.27: that is the headroom a radix
  special case would give for plain int lists.
- **Debug mode got slower with freed big integers:** fib 0.407 → 0.597 s, sieve 0.317 → 0.381, collatz 1.537 → 1.608,
  against 0.221 → 0.236 and 0.260 → 0.269 in release mode. The earlier run (before that change) had the old numbers
  twice, so this is the cost of the new big-integer ownership code on small-int arithmetic, not noise. Worth recovering.
- Spreads: Go and Rust show 100% to 300% between their fastest and slowest run on the short benchmarks (single slow runs
  while other work ran); Tomato release runs 25% to 100%. The medians of 10 shuffled runs are much less affected than the
  extremes, and two full runs agreed.

## What was done (raises out of line, so short functions inline; unreleased)

Goal: `math.sqrt` and the other short std functions that `raise` and use `!` conversions are inlined into their callers in
release mode. Found with clang's inline remarks (`-Rpass=inline -Rpass-missed=inline`, and `-Wl,-plugin-opt=-pass-remarks=inline`
for the LTO link) on a plain function that calls 20 `math` functions:

- **Building the error message counted as the function's size.** `math.log` costs 815 against the 325 that `inlinehint` allows:
  its `raise ValueError(f'... {v}', 'E53')` is an f-string, a text of a float, a concatenation, an error object, four releases and
  four stores, all inline. `sqrt` (260) was inlined only because its message was already in a helper (`_bad_sqrt`).
- **The test for an error after each call had no branch weights**, and clang predicts that `tomato_exc != null` is *usually
  true* (a pointer compared with null). After about four calls the rest of the caller looked as if it rarely ran, the
  threshold there dropped to 45, and even `exp`, `cbrt`, `hypot` and `pow` (cost 145 to 295) were not inlined.

**What changed (release mode only; debug mode and the website are unchanged):**

1. `Gen.check_error` and the test after `@init` branch with the weight of a loop bailout (1:100000).
2. `raise ERROR` is compiled into a function of its own, `@tomato.raise.N` (`Gen.outline_raise`), marked `cold noinline`. It is passed
   the values of the variables ERROR reads, makes the error and sets it pending (or leaves the error that making it raised); the
   raise site is the loads, one call and the branch to the handler or the epilogue. ERROR is compiled with the function's own state
   (types, narrowing, facts), so the code is what it would have been inline; if it needs anything else of the function (a
   register, a label, a write to a variable, an async frame, a loop nest's fast copy) the raise is compiled inline as before.
3. A runtime error of the compiler's own checks (`Gen.fail_with`: an overflow, a float division by zero) is one call to a shared
   `@tomato.fail.N` (`Gen.fail_call`), one per error and list of types of the values to free, which frees those values, makes
   the error and sets it pending.

**Inline decisions in that function** (cost / threshold; before → after):

| function | before | after |
| --- | --- | --- |
| `sqrt` | inlined, 260 / 325 | inlined, 240 / 325 |
| `log`, `log2`, `log10`, `log1p`, `acosh` | not, 815 / 325 (45 after the fourth call) | inlined, 240 / 325 |
| `atanh` | not, 885 / 45 | inlined, 310 / 325 |
| `exp`, `cbrt`, `hypot` | not, 145 / 45 | inlined, 145 / 325 |
| `pow` | not, 295 / 45 | inlined, 295 / 325 |
| `log_base` | not, 1415 | not, 605 / 225 |
| `asin`, `acos` (make an `Angle`) | not, 1135 | not, 560 |
| `isqrt`, `factorial`, `comb`, `perm` (loops, big numbers) | not, 1725 to 2375 | not, 805 to 1660 |

**Instructions** (callgrind, Linux x86-64, clang 21, release LTO, the counting inputs; before → after): fannkuch 293.4 → 263.6 M
(−10.2%), levenshtein −3.2%, nbody −2.0%, spectral_norm −1.9%, life −1.8%, hof −1.5%, kmers −1.1%, revcomp −0.6%, quicksort −0.5%;
matmul 83.8 → 87.3 M (+4.2%), dijkstra +1.3%, tokenize +0.5%, nqueens +0.5%, binary_trees +0.4%; the other 11 within ±0.01%.
Every benchmark prints the same. Matmul's `main` became short enough to be inlined into the runtime's `main`, where its loop
is compiled with one more instruction per pass; marking the entry function `noinline` brought matmul back (+0.16%) but cost
collatz +6.1% and half of fannkuch's gain, so it was not kept. Dijkstra's +1.3% is the weights (+0.4% without them); 1:10, the
weight of the runtime error branches, gave dijkstra +0.85% but lost spectral_norm's and part of hof's gains.

Test: `raise_paths` (debug; release under AddressSanitizer with the leak check), raises with f-strings, fields, comprehensions, big
numbers, `finally`, re-raises inside `catch`, an error whose `@init` raises, and runtime errors with values to free. Outside the
suite: every program of `tests/programs.txt`, `tests/runtime/` and `examples/` (302) built in release mode under AddressSanitizer
with the old and the new compiler gave the same output, exit status and leak report (two differ from run to run with either
compiler); and the compiler itself built in release mode (437 raises moved out, 2 left inline, 207 `@tomato.fail` functions)
reproduces `compiler/bootstrap/tomatoc.ll` exactly. The website's IR interpreter (`site/wasm/llvm.js`) reads the `cold` and
`noinline` attributes, for release IR run in it (`wasm interpreter runs weighted error branches`).

## What was done (the suite's average at the speed goal, unreleased)

The second step toward the goal below, which is about the average over the suite (Tomato ÷ Go 1.11, Tomato ÷ Rust 1.33): **the averages over the
25 benchmarks now meet it** (0.98 and 1.27). Single programs do not all: 9 are above 1.11 times Go (spectral_norm 1.65, nbody 1.47, kmers 1.44,
knapsack 1.41, levenshtein 1.30, strings 1.29, matmul 1.28, binary_trees 1.28, fannkuch 1.24) and 9 above 1.33 times Rust (nbody 2.60, hof 2.13,
kmers 2.02, knapsack 1.89, spectral_norm 1.80, life 1.72, fib 1.63, binary_trees 1.59, levenshtein 1.58). One machine, and not the Mac. "Before" is `main` at `12f64cb4`, the first step. Same machine, load average 64, fastest of 11 runs in one shuffled order.

| benchmark | before (s) | after (s) | after ÷ before | Go (s) | Rust (s) | Tomato ÷ Go before → after | Tomato ÷ Rust before → after |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| fib | 0.222 | 0.222 | 1.00 | 0.246 | 0.136 | 0.90 → 0.90 | 1.64 → 1.63 |
| sieve | 0.434 | 0.486 | 1.12 | 0.740 | 0.535 | 0.59 → 0.66 | 0.81 → 0.91 |
| matmul | 0.175 | 0.152 | 0.87 | 0.119 | 0.115 | 1.47 → 1.28 | 1.51 → 1.32 |
| mandelbrot | 0.087 | 0.088 | 1.01 | 0.093 | 0.091 | 0.94 → 0.95 | 0.96 → 0.97 |
| collatz | 0.164 | 0.165 | 1.01 | 0.267 | 0.159 | 0.61 → 0.62 | 1.03 → 1.04 |
| strings | 0.534 | 0.554 | 1.04 | 0.429 | 0.768 | 1.24 → 1.29 | 0.69 → 0.72 |
| sort | 0.216 | 0.223 | 1.03 | 0.385 | 0.310 | 0.56 → 0.58 | 0.70 → 0.72 |
| wordcount | 0.267 | 0.265 | 0.99 | 0.599 | 0.413 | 0.45 → 0.44 | 0.65 → 0.64 |
| bigint | 0.139 | 0.138 | 1.00 | 0.197 | 0.128 | 0.71 → 0.70 | 1.08 → 1.08 |
| objects | 0.796 | 0.872 | 1.10 | 0.847 | 0.992 | 0.94 → 1.03 | 0.80 → 0.88 |
| nbody | 0.412 | 0.211 | 0.51 | 0.143 | 0.081 | 2.87 → 1.47 | 5.09 → 2.60 |
| spectral_norm | 0.178 | 0.106 | 0.60 | 0.064 | 0.059 | 2.77 → 1.65 | 3.02 → 1.80 |
| fannkuch | 0.544 | 0.259 | 0.48 | 0.208 | 0.205 | 2.62 → 1.24 | 2.65 → 1.26 |
| nqueens | 0.069 | 0.061 | 0.88 | 0.061 | 0.051 | 1.13 → 1.00 | 1.35 → 1.19 |
| binary_trees | 0.378 | 0.376 | 0.99 | 0.293 | 0.237 | 1.29 → 1.28 | 1.59 → 1.59 |
| levenshtein | 0.349 | 0.112 | 0.32 | 0.086 | 0.071 | 4.05 → 1.30 | 4.94 → 1.58 |
| knapsack | 0.172 | 0.067 | 0.39 | 0.048 | 0.035 | 3.60 → 1.41 | 4.84 → 1.89 |
| life | 0.194 | 0.132 | 0.68 | 0.119 | 0.077 | 1.64 → 1.11 | 2.53 → 1.72 |
| dijkstra | 0.100 | 0.073 | 0.73 | 0.071 | 0.056 | 1.40 → 1.03 | 1.78 → 1.31 |
| quicksort | 0.316 | 0.212 | 0.67 | 0.232 | 0.202 | 1.36 → 0.92 | 1.56 → 1.05 |
| kmers | 0.359 | 0.371 | 1.03 | 0.257 | 0.183 | 1.40 → 1.44 | 1.96 → 2.02 |
| revcomp | 0.063 | 0.071 | 1.13 | 0.561 | 0.284 | 0.11 → 0.13 | 0.22 → 0.25 |
| tokenize | 0.233 | 0.220 | 0.95 | 0.355 | 0.302 | 0.66 → 0.62 | 0.77 → 0.73 |
| crc32 | 0.175 | 0.171 | 0.98 | 0.217 | 0.207 | 0.81 → 0.79 | 0.84 → 0.82 |
| hof | 0.230 | 0.187 | 0.81 | 0.317 | 0.088 | 0.72 → 0.59 | 2.61 → 2.13 |
| **average** | | | | | | **1.39 → 0.98** | **1.83 → 1.27** |
| geometric mean | | | | | | 1.08 → 0.88 | 1.41 → 1.15 |
| average of the medians | | | | | | 1.35 → 0.92 | 1.86 → 1.27 |

Instructions executed (callgrind, whole process, counting inputs, release mode, deterministic):

| benchmark | before (M) | after (M) | after ÷ before | Rust (M) |
| --- | ---: | ---: | ---: | ---: |
| fib | 123.54 | 123.54 | 1.00 | 67.28 |
| sieve | 36.69 | 30.32 | 0.83 | 24.64 |
| matmul | 107.59 | 83.85 | 0.78 | 55.41 |
| mandelbrot | 34.12 | 35.52 | 1.04 | 29.30 |
| collatz | 82.13 | 82.13 | 1.00 | 46.14 |
| strings | 69.52 | 69.52 | 1.00 | 94.28 |
| sort | 24.02 | 22.67 | 0.94 | 35.87 |
| wordcount | 146.13 | 146.13 | 1.00 | 240.68 |
| bigint | 71.83 | 71.86 | 1.00 | 74.74 |
| objects | 60.34 | 60.34 | 1.00 | 56.46 |
| nbody | 261.11 | 115.31 | 0.44 | 30.46 |
| spectral_norm | 122.34 | 75.87 | 0.62 | 33.42 |
| fannkuch | 718.29 | 278.06 | 0.39 | 104.64 |
| nqueens | 20.75 | 15.06 | 0.73 | 7.03 |
| binary_trees | 113.54 | 111.78 | 0.98 | 107.17 |
| levenshtein | 200.57 | 72.92 | 0.36 | 33.69 |
| knapsack | 182.29 | 66.82 | 0.37 | 31.50 |
| life | 138.50 | 78.72 | 0.57 | 40.56 |
| dijkstra | 44.04 | 24.55 | 0.56 | 7.02 |
| quicksort | 116.19 | 48.97 | 0.42 | 21.79 |
| kmers | 136.86 | 135.02 | 0.99 | 66.90 |
| revcomp | 16.42 | 15.62 | 0.95 | 30.83 |
| tokenize | 39.46 | 37.38 | 0.95 | 45.33 |
| crc32 | 57.85 | 31.45 | 0.54 | 9.71 |
| hof | 47.34 | 38.65 | 0.82 | 21.95 |

In 25 more interleaved runs of the two builds the new median was 0.92 of the old one for sieve, 0.94 for revcomp and 0.97 for objects, so their slower
times above are noise. For kmers it was 1.09 (fastest runs 1.05): **kmers is slower**, though it executes slightly fewer instructions. Why is not known.

All in release mode only, unless noted:

1. **Loop nests** (`Gen.nest_loop`). An outermost `for` over a range or a list of plain numbers, or a `while`, is compiled twice with the loops in
   it. The general copy is the ordinary code; its loop heads go to the fast copy when every int variable of the nest is small.
   The fast copy has no big-number code: when a number is not small, an index is out of range or a float is not finite, it goes to
   the same statement of the general copy, which does it again and raises the error if there is one. A statement compiled
   this way (assignments to variables, fields and list items, conditions) has no effect before its one store; every other statement is the
   ordinary code in both copies. Loops of more than 700 nodes are compiled once.
2. **Functions that only compute with numbers** (`Mod.pure`) start over in their general copy instead of carrying big-number code, so the
   copy for small arguments is short enough to inline. `inlinehint` on functions of up to 60 nodes.
3. **Floats**: the test for infinity and NaN is one branch; a run of float assignments in a fast copy is tested once, before its stores
   (`float_group`), so clang can work on several at once; `std/math` functions that take `int | float` are compiled again for floats (no box).
4. **Text** (both modes): `text[i] == other` compares without making a one-character text.
5. **Bitwise operators**, shifts by a constant and `%` of small numbers are inline (both modes).
6. **`sorted(key=)`** over many whole-number or float keys is a stable radix sort when the keys span few enough digits (both modes).

Test: `loop_nests` (debug; release under AddressSanitizer with the leak check). Outside the suite: 195 random programs of loop nests with big
numbers, bad indices and lists that are replaced, swapped and resized in the loop, against Python (and about 770 on the way there); 233 of float runs, release against
debug (267 more before the last change to `sqrt`); and every program of `tests/programs.txt` in release mode under AddressSanitizer (which found a unary minus that the fast
copies got wrong; the test now has it).

**Cost** (the compiler itself, built in release mode): 7% more IR lines, a 5% larger program; clang took 0.97 (median) to 1.12 (fastest) of the
time before in 5 runs each, too noisy to say more. The website's `tomatoc.wasm` went from 2.00 to 2.14 MB.

**What is left:** nbody (2.6 times Rust, which works on two floats at a time), hof (2.1), kmers (2.0: `dict_find_entry` and a text per key), knapsack (1.9),
spectral_norm (1.8), life (1.7). Retaining and releasing an object per step costs nothing measurable in nbody. Nothing was measured on the Mac.

## What was done (toward the speed of Go and Rust, unreleased)

Goal: averaged over the suite, about 90% of Go's speed (Tomato ÷ Go 1.11) and 75% of Rust's (Tomato ÷ Rust 1.33). Measured on
Linux x86-64 (Threadripper 3990X, clang 21, Go 1.27.4, Rust 1.100.0), a shared machine with a load average around 75, so
every program was run 15 times in one shuffled order together with the old build (`bf8eb2c`), Go and Rust, and the **fastest**
run is the one compared. The medians are noisier: the old matmul, for one, ran in 0.24 s or in 1.3 s depending on what else ran.

(These Linux numbers were taken before the LTO-verified toolchain existed and were not checked for LTO; for current Linux timings see the "Linux x86-64 snapshot" section above.)

| benchmark | before (s) | after (s) | after ÷ before | Go (s) | Rust (s) | Tomato ÷ Go before → after | Tomato ÷ Rust before → after |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| fib | 0.243 | 0.221 | 0.91 | 0.252 | 0.136 | 0.96 → 0.88 | 1.80 → 1.63 |
| sieve | 1.237 | 1.133 | 0.92 | 1.145 | 1.009 | 1.08 → 0.99 | 1.23 → 1.12 |
| matmul | 0.240 | 0.178 | 0.74 | 0.132 | 0.120 | 1.81 → 1.35 | 1.99 → 1.48 |
| mandelbrot | 0.101 | 0.101 | 1.00 | 0.095 | 0.093 | 1.06 → 1.06 | 1.09 → 1.09 |
| collatz | 0.259 | 0.164 | 0.63 | 0.268 | 0.159 | 0.97 → 0.61 | 1.63 → 1.03 |
| strings | 1.690 | 0.733 | 0.43 | 0.568 | 0.815 | 2.98 → 1.29 | 2.07 → 0.90 |
| sort | 0.420 | 0.269 | 0.64 | 0.430 | 0.456 | 0.98 → 0.63 | 0.92 → 0.59 |
| wordcount | 0.287 | 0.268 | 0.93 | 0.802 | 0.415 | 0.36 → 0.33 | 0.69 → 0.65 |
| bigint | 0.142 | 0.141 | 1.00 | 0.295 | 0.130 | 0.48 → 0.48 | 1.09 → 1.09 |
| objects | 1.324 | 0.915 | 0.69 | 1.193 | 1.166 | 1.11 → 0.77 | 1.14 → 0.79 |
| **average** | | | | | | **1.18 → 0.84** | **1.36 → 1.04** |
| geometric mean | | | | | | 1.01 → 0.77 | 1.29 → 0.99 |

Medians of the same 15 runs: Tomato ÷ Go 1.40 → 0.73 (average) and 1.18 → 0.66 (geometric mean), Tomato ÷ Rust 2.31 → 1.03
and 1.76 → 0.98. Peak memory: strings 348 → 184 MB, objects 97 → 84 MB, sieve 21.0 → 22.3 MB, sort 49.3 → 50.2 MB, the rest
unchanged. Nothing here was measured on the Mac.

Instructions executed (callgrind, whole process, counting inputs, release mode, deterministic):

| benchmark | before (M) | after (M) | after ÷ before |
| --- | ---: | ---: | ---: |
| fib | 183.46 | 123.54 | 0.67 |
| sieve | 49.04 | 45.78 | 0.93 |
| matmul | 138.65 | 107.57 | 0.78 |
| mandelbrot | 62.37 | 62.30 | 1.00 |
| collatz | 70.34 | 82.13 | 1.17 |
| strings | 106.59 | 69.52 | 0.65 |
| sort | 50.83 | 24.02 | 0.47 |
| wordcount | 155.53 | 146.13 | 0.94 |
| bigint | 100.27 | 71.83 | 0.72 |
| objects | 106.01 | 60.24 | 0.57 |

(The old Linux snapshot, where fib was 5.13 times Rust, was measured with no link-time optimisation: see 10 below.)

**The 25-benchmark suite, after merging with the range-analysis work.** Fifteen programs joined the suite while this was being done; none
was looked at while the changes above were made. "Before" here is `main` at `f11e1824` (which already has the range-analysis
work), "after" the same with the changes above; fastest of 9 shuffled runs, same machine, load about 75.

| benchmark | before (s) | after (s) | after ÷ before | Go (s) | Rust (s) | Tomato ÷ Go before → after | Tomato ÷ Rust before → after |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| fib | 0.246 | 0.223 | 0.91 | 0.253 | 0.136 | 0.97 → 0.88 | 1.81 → 1.64 |
| sieve | 1.117 | 1.138 | 1.02 | 1.256 | 1.332 | 0.89 → 0.91 | 0.84 → 0.85 |
| matmul | 0.251 | 0.188 | 0.75 | 0.145 | 0.108 | 1.73 → 1.29 | 2.33 → 1.74 |
| mandelbrot | 0.087 | 0.088 | 1.01 | 0.096 | 0.091 | 0.91 → 0.92 | 0.96 → 0.97 |
| collatz | 0.271 | 0.166 | 0.61 | 0.270 | 0.157 | 1.01 → 0.62 | 1.73 → 1.06 |
| strings | 1.680 | 0.813 | 0.48 | 0.517 | 0.968 | 3.25 → 1.57 | 1.74 → 0.84 |
| sort | 0.470 | 0.293 | 0.62 | 0.519 | 0.512 | 0.91 → 0.56 | 0.92 → 0.57 |
| wordcount | 0.317 | 0.265 | 0.84 | 0.696 | 0.417 | 0.46 → 0.38 | 0.76 → 0.64 |
| bigint | 0.140 | 0.141 | 1.01 | 0.326 | 0.129 | 0.43 → 0.43 | 1.08 → 1.09 |
| objects | 1.418 | 1.187 | 0.84 | 1.180 | 1.316 | 1.20 → 1.01 | 1.08 → 0.90 |
| nbody | 0.446 | 0.414 | 0.93 | 0.144 | 0.082 | 3.09 → 2.87 | 5.44 → 5.05 |
| spectral_norm | 0.232 | 0.179 | 0.77 | 0.066 | 0.060 | 3.50 → 2.69 | 3.89 → 2.99 |
| fannkuch | 0.698 | 0.544 | 0.78 | 0.212 | 0.206 | 3.29 → 2.56 | 3.39 → 2.64 |
| nqueens | 0.079 | 0.069 | 0.88 | 0.065 | 0.051 | 1.21 → 1.07 | 1.53 → 1.35 |
| binary_trees | 0.393 | 0.394 | 1.00 | 0.421 | 0.246 | 0.93 → 0.94 | 1.59 → 1.60 |
| levenshtein | 0.384 | 0.353 | 0.92 | 0.091 | 0.074 | 4.21 → 3.86 | 5.21 → 4.78 |
| knapsack | 0.193 | 0.172 | 0.89 | 0.055 | 0.037 | 3.51 → 3.13 | 5.22 → 4.65 |
| life | 0.221 | 0.196 | 0.89 | 0.124 | 0.078 | 1.78 → 1.59 | 2.83 → 2.51 |
| dijkstra | 0.149 | 0.120 | 0.81 | 0.093 | 0.069 | 1.60 → 1.29 | 2.16 → 1.74 |
| quicksort | 0.431 | 0.394 | 0.91 | 0.343 | 0.254 | 1.26 → 1.15 | 1.69 → 1.55 |
| kmers | 0.656 | 0.426 | 0.65 | 0.608 | 0.330 | 1.08 → 0.70 | 1.99 → 1.29 |
| revcomp | 0.113 | 0.101 | 0.89 | 0.939 | 0.398 | 0.12 → 0.11 | 0.28 → 0.25 |
| tokenize | 0.302 | 0.245 | 0.81 | 0.695 | 0.350 | 0.43 → 0.35 | 0.86 → 0.70 |
| crc32 | 0.338 | 0.237 | 0.70 | 0.283 | 0.232 | 1.19 → 0.84 | 1.45 → 1.02 |
| hof | 0.547 | 0.467 | 0.85 | 0.364 | 0.112 | 1.50 → 1.28 | 4.87 → 4.16 |
| **average, all 25** | | | | | | **1.62 → 1.32** | **2.23 → 1.86** |
| geometric mean, all 25 | | | | | | 1.24 → 1.01 | 1.76 → 1.44 |
| average, the first ten | | | | | | 1.18 → 0.86 | 1.32 → 1.03 |
| average, the other fifteen | | | | | | 1.91 → 1.63 | 2.83 → 2.42 |

After this step the goal (1.11 and 1.33) was met on the first ten and not on the whole suite (the section above closes that). The furthest behind were: nbody, levenshtein,
knapsack, hof, spectral_norm, fannkuch and life. The medians of these runs agree on the averages (1.52 → 1.30 for Go, 2.04 → 1.76 for Rust) but
are noisy program by program (wordcount and life have slower medians after, and faster fastest runs).

**Compiler** (1 to 4 change release mode only: the IR they make is longer, and the website interprets the IR):

1. **Fused integer expressions** (`Gen.fused`). Two or more `+ - *` (and `//` or `%` by a positive constant) on ints are one unit. The
   numbers it starts from are worked out first, left to right, then one test of all their tags together leads to a fast copy
   with one overflow test per operation (none where the range facts prove it small). A big number or an overflow leads to a
   cold slow copy that redoes the expression from the same numbers with the general operations. `x = x * a + y` hands the old
   number to the operation, as single operations already did. `%` and `//` by d work on the tagged word with 2d.
2. **A copy for small arguments** (`has_small`). A short function that never assigns its int parameters is compiled twice; the copy
   knows that they are small, and after `if n < 2: return n` the range facts prove `n - 1` and `n - 2` need no test at all.
3. **Error tests after calls that cannot raise are removed** (`finish_bodies`): which functions can leave an error pending is worked
   out over the whole program once every function is compiled (this one is in both modes).
4. **A release program does not free what its entry function holds** when it ends (the process ends anyway; nothing in the
   language can see it).
5. **Direct method calls** (`Mod.overridden`): a method that no class below the static one overrides is called directly, so it
   can be inlined. Generic classes that could still be copied count as if they were.
6. **Lists that a loop only reads** (`keep_lists`): a loop of plain assignments, ifs and range loops over numbers, items and fields
   cannot run user code or change a list's length, so the length and the items' address of its local lists are loaded once.
7. **Small-int loops** (`small_loop`'s fast copy): `3 * x + 1` is one range test instead of two overflow tests, and an `if`/`else` that
   assigns one variable a short sum either way works out both and selects, so an unpredictable condition costs no branch
   (collatz executes more instructions and is 37% faster).
8. **`for piece in text.split(sep)`** makes one piece at a time instead of a list of them, and `int(text)` parses once instead of twice.

**Runtime and linking:**

9. **Numbers sort with a radix sort** above 512 items, when the values span few enough digits for the length; text, short lists, wide
   values, `key=` and `cmp=` sort as before. (The v0.49 radix sort was dropped because it could not take a compare function;
   those have had their own paths since, so this only replaces the introsort where no function is given.) The highest digit
   cuts the list in place into parts that fit the cache, with a prefetch ahead of each part's write position; the parts are sorted
   with a 64 KB buffer. A list already in order, or in reverse order, is noticed first.
10. **No silent loss of link-time optimisation on Linux.** When `-flto` fails at the link (no LLVM plugin in the linker), `tomato`
    used to fall back to a plain link, which makes a call of every integer operation. Now clang merges the runtime's
    bitcode into the program first (`-mlink-bitcode-file`).
11. **Big integers**: 64-bit words throughout `+`, `-` and `*` (the multiply by a word is unrolled), `x *= small` reuses x's memory, and
    sums are written straight into their result.
12. **Memory**: lists and pool chunks of many megabytes ask Linux for 2 MB pages, texts are not zeroed before they are filled, and
    the allocation of a small object is inlined.

Tests: `fast_paths` (debug and release), the release-mode AddressSanitizer section of `tests/run.sh`, and a check of 10. Outside the
suite: 959 random programs whose output matches Python's in release mode (plain and under AddressSanitizer, with the leak
check; one more was too slow to check there, in the old compiler as well), and
every program of `tests/programs.txt` in release mode under AddressSanitizer.

**What is left:** fib (1.63 times Rust, which unrolls part of the recursion) and matmul (1.48 times Rust, 1.35 times Go: two bounds
tests, three tags and two overflow tests per step). The loop item of `for x in xs` is still retained and released. Division
of big integers still goes 32 bits at a time.

## What was done (borrowed loop items, unreleased)

`for x in xs` no longer retains the item (nor copies a big int or a boxed float) when the compiler can prove that the body
cannot change any list: the item is read straight from the list, which the loop already holds, and made owned only when the
loop ends or an error leaves it (`Gen.lent_loop_body`, `lent_safe`, `lent_method`). The body may assign locals, append to a
comprehension's own list, use `if`, `break` and `continue`, hold `for i in range(...)` loops of the builtin `range` (`lent_range`)
made of the same statements, read fields, items and lengths, use operators on numbers and text, call numeric functions that
`Mod.lent_pure` proves, and call methods that `lent_method_info` proves: not overridden below the receiver's class, parameters
that are numbers, text, or lists and objects that are not optional (`lent_param`; an argument has the parameter's type, or a
class below it, and is itself read as above, as in `a.absorb(b)`), and a body of assignments to locals and to number fields of
`self`, `if`, range loops, `return` and calls of other proven methods (as statements or inside expressions such as
`total = total + p.area()`). Field writes stay number-only: replacing an object or list held in a field may free it, and the
body only reads its parameters. A method that calls itself, a `raise`, other loops, any other call and any list method keep
the loop owning. The item may be of any type that is reference counted (objects, text, lists, ...) or an `int` or `float`.
Test: `loop_lifetime` (its first line gives how many of its loops borrow, which `tests/run.sh` checks; AddressSanitizer runs
it too, including loops whose callee removes the item through a list parameter, a range loop or an override).

Measured with cachegrind (instructions, deterministic) on a program that walks a 1,000,000-item list ten times, linked at
`-O2`, the setup subtracted: per item, `total = total + n` over `list[int]` 33.4 → 20.1, `total = total + len(w)` over
`list[str]` 48.0 → 30.4, and `total = total + p.norm1()` over objects (a method returning `self.x + self.y`) 62.2 → 38.2.
The same way (release mode, `-O2`, runtime not inlined), the two loops `acc.absorb(v)` (an object parameter) and
`for i in range(2): total = total + v.x * i` (a nested range loop) over a list of objects together take 164.6 → 119.6
instructions per item (slope between 100,000 and 200,000 items, ten passes).

## What was done (text indexing and fused f-strings, v0.51)

**`s[i]`.** ASCII text was already indexed directly (the character number is the byte offset), but each `s[i]` allocated a one-character string, and text with any non-ASCII character was scanned from the start on every index (quadratic loops). Now: (1) `s[i]` on an ASCII character returns one of 128 shared immortal one-character strings (no allocation, no release work); (2) a string of 256 or more characters that is not all ASCII gets a chunked index (D17c) on its first indexed use: the byte offset of every 64th character, so an index scans at most 63 characters. The index lives in a side table of 4 strings (`chunk_cache` in the runtime, oldest dropped first), not in the string object, so the string layout, string constants and the wasm interpreter are unchanged; the table holds a reference to each indexed string (strings are immutable, so the address cannot be reused) and it is released before the debug-mode leak check. Slices, `find` from a position and extended slices use the same offsets. More than 4 long non-ASCII strings in use at once fall back to the plain scan. Measured with a loop reading every character of a 100,000 character non-ASCII text next to an ASCII one (release mode, user time, machine load average about 35 to 55 from other work): old 27.2 s, new 0.01 s; 300,000 characters take 0.05 s.

**f-strings.** `f'w{i}'` is `'w' + str(i)`, and every `+` and every `str()` made its own string. A chain of `+` whose first two operands include a text literal or a `str(...)` call (at most 16 operands) is compiled to one `tomato_str_cat` call: the parts are evaluated in order, then one allocation is filled, and an int inside `str()` is written as digits straight into it. Error messages for a wrong operand type are unchanged. `benchmarks/count.sh` (instructions executed under Valgrind, whole process): wordcount 191.76 M to 159.70 M (Tomato ÷ old Tomato 0.83; Tomato ÷ Go 1.01 to 0.84, ÷ Rust 0.78 to 0.65); strings is unchanged at 140.44 M (it uses `join` and `split`, not `s[i]` or f-strings). Wall clock, wordcount with n = 5,000,000, release mode, 7 alternating runs, user seconds, load average about 35: old median 0.79 s, new 0.66 s (ratio 0.84, the same as the instruction count).

## What was done (compact list storage, v0.51)

A list whose item type is fixed at compile time keeps its items without the 8-byte slot, and the program cannot tell
(no syntax, same results). The width comes from the static type (`item_width` in `compiler/src/compiler.tom`): `bool` is
1 byte, `int[length=8]`/`uint[length=8]` 1 byte, 16 bits 2 bytes, 32 bits 4 bytes; every other list and every tuple keeps
8-byte slots, and the generic path is untouched. Generic code is compiled once per type, so a `list[bool]` is always byte
storage: there is no way to meet a list of the wrong width. `float` needed nothing (a float slot already holds the plain
8-byte double with no tag), and `int` cannot shrink (a small int is one tagged 8-byte word and a big number is a pointer
in that word, so 8 bytes is the narrowest that holds both). Lists of fixed-width integers can only come from inference
today, such as `[int[length=8](1)]`, because a declared `list[int[length=8]]` is not accepted yet. The compiler asks for the width in every place it pushes,
loads or stores an item (`push_item`, `load_item`, `store_item`, `list_slot`: indexing, assignment, append, literals,
comprehensions, `for`, `in`, the async yield queue); `tomato_list_slice`, `_concat`, `_repeat`, `_sorted_by` and
`tomato_dict_values` take the width in the copy flag (`flags >> 2`), and `[False] * n` is one `memset`. The IR interpreter
needed no change (it already loads and stores `i8`, `i16` and `i32`).

Sieve (n = 20,000,000, release mode, median of 9 alternating runs on a loaded machine, load average about 3.7): the list
shrinks from 160 MB to 20 MB and the time from 0.23 s to 0.076 s. Tomato ÷ Go 1.25 (Go 0.061 s), Tomato ÷ Rust 1.30
(Rust 0.059 s); the v0.50 ratios were 4.19 and 4.28. The other nine benchmarks, run alternately old against new (median of
7, `time -p`, 0.01 s resolution), did not change: fib 0.23, matmul 0.17, mandelbrot 0.12, collatz 0.52, strings 0.21,
sort 0.12, wordcount 0.28, bigint 0.11, objects 0.16 seconds both ways.

**Linux x86-64 check** (at `0d6208f`, 128 cores, load average about 78 from other work; clang 21, Valgrind 3.26). The
baseline is the same compiler with `item_width` returning 8 for every list, so the two differ only in the storage width.
In release mode, only the sieve binary differs: the other nine benchmarks build to byte-identical programs. Instructions
executed (callgrind, whole process): sieve at the counting input (1,000,000) 67.25 → 49.04 million (× 0.73), at
20,000,000 1,394.0 → 1,013.7 million (× 0.73); matmul (150) 158.83 and mandelbrot (250) 79.67 million both ways. Sieve
at 20,000,000, 15 alternating runs: peak memory 160.5 → 21.0 MB, median wall time 3.58 → 1.50 s (user 3.18 → 1.45 s).
This machine is memory-starved under that load (Rust's sieve takes 1.2 to 1.6 s on it), so only the ratio means anything;
matmul (0.28/0.29 s) and mandelbrot (0.10 s fastest both ways) wall times moved only by noise. Test: `compact_fuzz` (1,000
random `list[bool]` operations whose output was checked against CPython; it also runs under AddressSanitizer and through
`site/wasm`, which gave the same output via Node on Linux) and `compact_lists`.

## What was done (mandelbrot, unreleased)

The baseline release binary from `dd719982` executed 102.44 M instructions at input 250 on Linux arm64. Callgrind (`--dump-instr=yes --collect-jumps=yes`) attributed 101.68 M (99.26%) to `tomato.main` itself. Matching the instruction addresses to `objdump -d --disassemble=tomato.main` put 99.61 M (97.24%) in the inner `while` condition and body (`0x15a4` through `0x1670` in that binary). The ten `fsub` / `fcmp` / branch sequences in that loop accounted for 57.37 M (56.01% of the whole run). These are self costs that count each executed instruction once. The emitted LLVM IR and disassembly also show unboxed `double` locals in registers, with no per-operation allocation or reference counting.

- **A finite check after every `+ - *`.** A full inner iteration ran three checks in the condition, four in the `t` assignment and three in the `zi` assignment. The three finite checks for `cr` ran once per grid point, outside the inner loop. Infinity and NaN never become finite under `+`, `-` or `*`, so checking the end of a chain catches any non-finite intermediate result. The compiler defers a left operand's check only when the right operand is a numeric local, a numeric literal or a float chain built from those. The right operand keeps its check when the left can require an overload or optional unwrapping. These rules preserve evaluation order, error reporting and temporary cleanup. The arithmetic keeps its original order and rounding.
- **Integer comparison through a three-way runtime call in the emitted IR.** `tomato_int_cmp` returns -1, 0 or 1, which the program compares with 0. The profiled baseline already inlines the fast path for `i < 100` under LTO. The compiler now emits a direct comparison of two small tagged integers and keeps the runtime fallback for other representations. A constant or a known-small operand skips its tag test.

Instructions executed (count.sh, Linux arm64 under Valgrind, input 250, 1 run each, deterministic): mandelbrot 106.7 M → 66.9 M after the finite-check change → 61.5 M with the compare change (Tomato ÷ Go 3.71 → 2.14; Tomato ÷ Rust 4.13 → 2.38). collatz 123.5 M → 103.3 M from the compare change alone. Wall clock (alternating runs of seven at n = 1000, on a machine with a load average of about 50, so only the order of magnitude is trustworthy): before 0.39 s median, after 0.23 s, Go 0.15 s, Rust 0.15 s.

After integrating the later compiler and runtime changes through `b0a638b1`, the same instruction count was 102.50 M on `main` and 56.61 M in both runs with the corrected Mandelbrot optimization. Tomato ÷ Go was 1.97 and Tomato ÷ Rust was 2.19. The programs agreed on the output. Host load average was 3–5 at the start of these runs.

What was left then: about 31 instructions per iteration against about 15 in Go, 9 of them the remaining finite checks and about 10 the tagged counter `i` (tag tests on the compare and the add, the add's overflow test). The counter part is done, see "integer ranges" below. Tests: `float_chains` (results and errors of chains equal the old compiler's output, including which error comes first).

## What was done (integer ranges, unreleased)

**The compiler now knows intervals of int locals** (`Gen.range_of`, `Gen.loop_facts` and the `Facts` helpers in `compiler/src/compiler.tom`). While a function is compiled, `self.facts` maps some int locals to an interval that certainly holds the number at that point. The facts come from:
- assignments of literals, of `+ - *`, of `//` and `%` by a constant, of `len(xs)` on a local list, tuple, dict, set or text, and of a range loop's variable;
- the conditions of `if` and `while`, with `and`, `or` and `not` (`i < 100` lowers the upper bound of `i`);
- for a `while` loop, a fixpoint over its body. The head facts start from the facts before the loop. They are joined with what one pass of the body gives back, including `continue`, and a bound that is still moving after two rounds is dropped (widening). Two more passes narrow the result again. Each step keeps a post-fixpoint, so the head facts hold on every pass. After the loop the facts are the head facts with the condition false, joined with those at each `break`.

**Uses.**
- A local whose interval lies inside the small range (-2^62 .. 2^62 - 1) is read as a known small int: its comparisons have no tag test, and indexing has no range check.
- A `+ - *` whose result interval lies inside the small range, with small operands, becomes one `add`/`sub`/`mul nsw` on the tagged words, with no tag test, no overflow check and no call (`small_arith`).
- Assigning to a local that holds a known small number frees nothing.
- A known small int converts to a float with a shift and `sitofp`.

**Soundness.** Each statement either has its effect modelled exactly (an assignment to a local, `if`, `while`, `break`, `continue`, `return`, `raise`), or every local it can assign is forgotten (`bound_names`: assignment targets, loop variables, comprehension variables, catch names).
- A `for` loop forgets the locals its body assigns at the start of every pass, and the range loop's variable gets the interval between its bounds. When a bound is not known to be small, it gets only the small range; a loop that would leave that range stops with an error (see "range loops and float intervals" below).
- A `try` keeps no facts inside, because its handlers can start from any point of its body. Generator loops (which switch scopes) and async functions keep none either.
- A local with no fact may hold anything, including the word 0 of a slot nothing has written. A fact is only created by an assignment of a computed int, never by refining an unknown local. So an interval inside the small range always means a tagged small word.
- Overflow stays exact: when the interval does not prove the result small, the checked operation is emitted as before.
- Test `int_ranges` covers loops that cross ±2^62 in both directions, multiplication past the edge, `break`/`continue`, `try`, comprehensions, generators, range loops with 1 to 3 arguments and negative steps, `//` and `%` with negative operands, nested loops, `len` bounds and constants. An independent fuzzing pass compared about 4,500 random programs against the old compiler at -O1 and -O2, plus 640 under AddressSanitizer, and found no difference.

**Mandelbrot.** The inner loop's `i < 100` now compiles to `icmp slt i64 %i, 201` and `i += 1` to `add nsw i64 %i, 2`, with nothing else.

**Results.** Instructions executed, `benchmarks/count.sh --guest` on Linux x86-64 (valgrind 3.26, clang 21, Go 1.27.4, Rust 1.100.0), counting inputs, one run each (Tomato is deterministic):

| benchmark | before | after | after ÷ before | Tomato ÷ Go before → after | Tomato ÷ Rust before → after |
| --- | ---: | ---: | ---: | ---: | ---: |
| mandelbrot | 79.67 M | 62.37 M | 0.78 | 2.07 → 1.62 | 2.72 → 2.13 |
| fib, sieve, matmul, collatz, strings, sort, bigint, objects | unchanged | unchanged | 1.00 | | |
| wordcount | 155.53 M | 155.53 M | 1.00 | | |

That is about 9.1 fewer instructions per inner iteration (1,898,564 iterations at input 250). Eight of the other nine benchmarks build to byte-identical binaries. Wordcount changes only in standard-library code it does not run: `_str_lstrip` loops on `i < len(s)` and now benefits. Compiling the compiler itself takes 2% more instructions (14.06 G → 14.34 G).

Wall clock: release binaries at the full inputs, old and new run alternately and pinned to one core, median of 21 runs. The machine is a shared 128-core Linux box with a load average around 90, so treat these seconds as rough. The identical binaries show the noise level:

| benchmark | input | before (s) | after (s) | after ÷ before | binary |
| --- | --- | ---: | ---: | ---: | --- |
| fib | 38 | 0.265 | 0.264 | 0.99 | identical |
| sieve | 20000000 | 1.738 | 1.736 | 1.00 | identical |
| matmul | 400 | 0.280 | 0.280 | 1.00 | identical |
| mandelbrot | 1000 | 0.1066 | 0.1051 | 0.99 | changed |
| collatz | 1000000 | 0.269 | 0.269 | 1.00 | identical |
| strings | 3000000 | 2.004 | 2.020 | 1.01 | identical |
| sort | 3000000 | 0.580 | 0.584 | 1.01 | identical |
| wordcount | 5000000 | 0.341 | 0.340 | 1.00 | changed (std code it does not run) |
| bigint | 40000 | 0.147 | 0.147 | 1.00 | identical |
| objects | 2000000 | 1.552 | 1.568 | 1.01 | identical |

Mandelbrot's wall time barely moves, although it executes 22% fewer instructions. A second session gave 0.1048 s before and 0.1052 s after, with Go at 0.0955 s and Rust at 0.0955 s, so Tomato ÷ Go is about 1.10 in time. The removed instructions were integer work that already ran alongside the loop's floating-point dependency chain: each pass needs the new `zr` and `zi`, and their multiply-adds are what set the pace on this x86 core. On a core with less spare integer throughput the gain may be larger; it was not measured on the M1.

The three finite checks per iteration, which this left, are gone now: see "range loops and float intervals" below.

## What was done (big-integer multiplication, unreleased)

`mag_mul` in the runtime was the schoolbook method only, so a product of two n-limb numbers took n² limb products. Now:

* **Karatsuba** (`kara_mul`) when the shorter operand has 48 limbs (32-bit) or more: three half-size products instead of four, with the
  middle term made as `a0 b0 + a1 b1 - (a0 - a1)(b0 - b1)` from the absolute differences (no carry limbs in the halves). One scratch
  buffer, sized by `kara_scratch`, is allocated per product and used by the whole recursion; below 48 limbs the old 64-bit-word schoolbook
  loop is the base case.
* **Squares** (`kara_sqr`, when both operands are the same number, as in `x * x` and the repeated squaring of `**`): Karatsuba with
  `(a0 - a1)²`, which is never negative, over a schoolbook square (`mag_sqr_base`, up to 64 limbs) that computes each cross product once
  and doubles the sum: about half the work of a product.
* **Uneven lengths**: the longer operand is cut into pieces as long as the shorter one; each piece is a balanced Karatsuba product
  added in at its place.
* **Zero limbs** at either end of an operand are skipped (the result pointer moves instead), so `(1 << k) * y` and products of
  numbers with many zero low limbs cost what their nonzero part costs.

The thresholds were measured on x86-64 (a shared, loaded machine): the product time is flat from 40 to 64 limbs, the square time
from 48 to 128.

`x * x` and `x * (x + 1)` with x = 2^bits // 3 (dense: every limb nonzero), release mode, wall time, load average about 75 from
other work; Python 3 timed on the same machine in the same session, around the product only:

| bits | old `x*x` | new `x*x` | new `x*(x+1)` | Python `x*x` | Python `x*(x+1)` |
| --- | --- | --- | --- | --- | --- |
| 2^20 | 0.29 s | 0.03 s | 0.03 s | 0.065 s | 0.065 s |
| 2^22 | 14.4 s | 0.49 s | 0.27 s | 1.03 s | 0.98 s |
| 2^24 | (96 s, TODO note) | 2.4 s | 4.4 s | 9.2 s | 15.4 s |

With x = 2^bits (the case first timed in the TODO note: 2^20 bits 0.28 s, 2^24 96 s), the product is now linear and takes no measurable time.

`3 ** 20000000` (31.7 million bits, repeated squaring): old 124 s, new 4.3 s, Python 7.9 s; `3 ** 2000000`: old 1.07 s, new 0.23 s, Python 0.20 s.

Tests: `tests/bigmul.c` (12,000 random products and squares around the thresholds, uneven lengths, all-ones and zero-half operands,
against a plain 32-bit schoolbook product, under AddressSanitizer and UBSan) and the program `big_karatsuba` (output computed with Python; also run under AddressSanitizer and through `site/wasm`).

*Not done here:* Toom-3. Decimal conversion is still quadratic; a divide-and-conquer `str(int)` can build on this multiplication
(division: see "big-integer division" below). The next section adds the transform product
that Karatsuba's n^1.585 (a dense 2^28-bit square would still take about 3 minutes) called for.

## What was done (big-integer multiplication by a number-theoretic transform, unreleased)

From 6000 limbs (32-bit) in the shorter operand, `mag_mul` multiplies with a number-theoretic transform (`ntt_mul`) instead of
Karatsuba:

* **Coefficients are 64-bit words** (two limbs), the numbers being polynomials in 2^64. A coefficient of the product is below
  min(words) * 2^128, so it is found exactly from its residues modulo three primes between 2^62 and 2^63 (`87 * 2^56 + 1`,
  `131 * 2^55 + 1`, `197 * 2^55 + 1`; the product of the three is above 2^187, so the length may reach 2^59 words, and each has a
  2-power order of at least 2^55, so a transform of any length that fits in memory exists) with the Chinese remainder theorem (Garner's
  form, one multiply-add chain per word, carries handled in 128 bits). Half the transform length that 32-bit coefficients would need.
* **One prime at a time**, with Montgomery arithmetic (R = 2^64, branch-free modular add and subtract: a compiler turned the
  conditional version into unpredictable branches, 2 to 3 times slower). A decimation-in-frequency forward transform gives
  bit-reversed order, the pointwise product needs no reordering, and a decimation-in-time inverse takes that order: no bit-reversal
  pass. Both recurse radix 4 (two levels per pass over memory) down to blocks of 4096 words done level by level, with twiddle tables
  for lengths up to 65,536 (forward and inverse) and twiddles stepped as they go above that. A square does one forward transform per
  prime instead of two. Memory: 3 (4 for a product) arrays of the transform length, 8 bytes each: 200 MB for a 2^28-bit square.
* **Uneven lengths:** a much longer operand (more than four times the shorter) is cut into pieces of four times the shorter one, each
  multiplied by transform and added in (a short last piece by `mag_mul`), so the memory and the transform length stay near the size of the
  shorter number.
* **The cutoff, 6000 limbs, was measured** (x86-64, Threadripper 3990X, loaded machine): below 2000 limbs Karatsuba is 2 times faster, from
  4000 to 6000 the two are within 20% of each other (the transform length is a power of two, so its time steps up there), at 8000 the
  transform is 2 times faster, at 16,000 2.5 times, at 500,000 limbs 6 times (squares: 7). That is far below the 10^5 limbs first
  guessed.

`x * x` and `x * (x + 1)` with x = 2^bits // 3 (dense), release-mode compiler and runtime, wall time, load average 70 to 100 from other
work on the 128-thread machine; Python 3.14 on the same machine:

| bits | Karatsuba `x*x` | NTT `x*x` | NTT `x*(x+1)` | Python `x*x` | Python `x*(x+1)` |
| --- | --- | --- | --- | --- | --- |
| 2^20 | 0.03 s | 0.02 s | 0.03 s | 0.065 s | 0.096 s |
| 2^22 | 0.49 s | 0.10 s | 0.13 s | 0.59 s | 0.88 s |
| 2^24 | 2.4 s | 0.43 s | 0.60 s | 5.4 s | 10.3 s |
| 2^26 | (about 20 s) | 1.4 s | 1.8 s | (about 80 s) | |
| 2^28 | (about 3 minutes) | 5.2 s | 8.0 s | (about 12 minutes) | |

(The Karatsuba column is the previous section's measurement; the parenthesised times are extrapolated at n^1.585, not run.)

Tests: `tests/bigmul.c` checks `ntt_mul` against Karatsuba (squares, uneven lengths, all-ones and zero-half operands, lengths around the
powers of two and 6000, and `mag_mul` through its cutoff and the pieces) under AddressSanitizer and UBSan, and the program `big_ntt` (output computed
with Python; also under AddressSanitizer and through `site/wasm`). Outside the suite: products and squares of 2^25 to 2^28 bits, all-ones and
random, even and uneven, were compared with Python 3 (the exact product up to 2^25 bits, residues modulo eight moduli above that, with `ulimit -v 4000000`).

*Not done:* a truncated (half-size) transform for the low or high half of a product, the transform of a shared operand reused across the
pieces of an uneven product, and a faster 2^28-bit time with more tuning (AVX2/Montgomery in vectors).

## What was done (big-integer division, unreleased)

`mag_divmod` was Knuth algorithm D only (in 64-bit words), so dividing a 2n-limb number by an n-limb one took about n² limb
products. Now a divisor and a quotient both of `DIV_DC_T` (160) limbs or more go to **Burnikel-Ziegler** recursive division, built on
the Karatsuba product, in the in-place form GMP uses (`dcpi1`):

* `div_qr_n` divides 2n limbs by n (the divisor normalized: top bit set). The top half of the quotient comes from dividing the top
  half of the dividend by the top half of the divisor (recursively); the low half of the divisor times that is subtracted, and while
  the result is negative the quotient goes down by one and the divisor is added back (at most a few times). The same again for the
  low half. Cost: about two products of n/2 limbs per level, so the same order as a multiplication.
* `div_qr` takes any lengths: a quotient at least as long as the divisor is made one divisor-length at a time from the top (the
  first piece takes the odd part); a shorter quotient (q limbs) is estimated from the top 2q limbs of the dividend and the top q
  limbs of the divisor, then corrected the same way.
* Below 160 limbs of divisor or of quotient the old Knuth D (`mag_divmod_base`) does the work, also as the recursion's base case.
  The threshold was measured on x86-64 (a shared, loaded machine): times are flat from 100 to 240 limbs, and at 160 the recursive
  path is never measurably slower than Knuth D.

The callers (`//`, `%`, `divmod`, true division of big ints) are unchanged: `mag_divmod` keeps its arguments.

Dividing a 2^(k+1)-bit number by a 2^k-bit one (dense random limbs), in C with the runtime at `-O2`, best of several runs, load
average about 75 from other work:

| divisor bits | Knuth D | Burnikel-Ziegler |
| --- | --- | --- |
| 2^16 | 1.3 ms | 0.61 ms |
| 2^18 | 21 ms | 5.7 ms |
| 2^20 | 0.35 s | 0.054 s |
| 2^22 | 5.7 s | 0.50 s |

`divmod(a, b)` in a release-mode program, a of 2^m bits and b of 2^(m-1) bits, against Python 3.14 on the same machine in the same
session (the quotients and remainders agree, checked by residues):

| a bits | Tomato | Python |
| --- | --- | --- |
| 2^20 | 0.029 s | 0.073 s |
| 2^22 | 0.29 s | 0.63 s |
| 2^24 | 2.5 s | 3.3 s |
| 2^26 | 39 s | 80 s |
| 2^28 | 316 s (peak memory 374 MB, `ulimit -v` 16 GB) | 678 s |

Tests: `tests/bigdiv.c` (the bitwise long-division check, now with the recursion threshold at 6 limbs so short numbers take the
recursive path too, and 1,500 long divisions up to 3,000 limbs checked by multiplying back: random, all-ones, lone-top-bit and
half-zero patterns, the largest remainder, under AddressSanitizer and UBSan; every correction branch is taken) and the program
`big_division` (also under AddressSanitizer and through `site/wasm`: lengths around the threshold, quotients shorter and much longer than the divisor, all four signs, exact quotients,
divisor patterns that make the estimates too big; output computed with Python).

The times above were measured with the Karatsuba product. The division's products go through `mag_mul`, so since the transform
product (previous section) they use it from 6000 limbs as well.

*Not done:* a Newton reciprocal (with the transform product it could beat the recursive division at the largest sizes).

## What was done (range loops and float intervals, unreleased)

Three follow-ups of the integer ranges above.

**1. Range loops past ±2^62** (a correctness fix). The variable of a counted `for i in range(...)` was tagged without a check, so a bound past the small range wrapped: `range(2**62 + 1, 2**62 - 4, -1)` began at -2^62 + 1, and some loops never ended. Now a start or stop that is not known to be small is tested once where the loop starts (its tag bit, which the conversion to a machine number tests anyway). When one is outside, `tomato_range_late` and `tomato_range_cut` (cold) cut the loop to the numbers inside the small range, and after those the loop stops with `the number is too big here`, as a bound past the machine word already did. A loop whose first number is already outside stops before its first pass, even when later numbers would be inside. A loop that breaks first, such as one over `range(2**63 - 1)`, is not affected. The count of a three-argument loop is worked out in unsigned arithmetic, so no step or distance overflows. Two things in the same code were fixed as well: a body that assigned a big number to its own range variable leaked it, and the three-argument loop tested its old variable for freeing on every pass (now once, before the loop).

*Tried and not kept:* exact big numbers in the loop. The body then has to be compiled twice, since a variable that may be big costs a tag test at each use. The second copy gave the inliner two call sites where it had one: matmul +7%, wordcount +2%, strings +1.4% instructions executed. The class `range` (`r = range(...)`, then `for i in r`) has no limit.

**2. Float intervals.** A float local can have an interval too (`Rng.fl`): its value is then certainly finite and lies between two whole numbers. The interval rules use only that rounding keeps order: the rounded result of `+ - *` lies between bounds that are floats themselves, so each bound moves outwards to a whole number that is a float (any up to 2^53, above that a power of two). An operation whose result interval is bounded (the cap is 2^256, far below the real limit of 2^1024) needs no finite check. Facts come from literals, `+ - *`, small ints converted to floats, division by a whole number (its magnitude is at least 1 once the zero check passed, so the quotient is not larger than the dividend) or by a positive literal, comparisons of a float local with a number of known interval, and sums: when `a*a + b*b + ... <= c` holds and every part is known not to be negative, each `x*x` is at most `c` after rounding, so `|x| <= r` for the smallest power of two with `r*r >= 2c`. A value with no known interval (a parameter, a call's result, a field) still gets its check, and so does everything computed from it. Refining a comparison is sound for NaN because both sides must have known intervals, which are finite.

In mandelbrot the inner loop has no check left. `cr` and `ci` are bounded because `px` and `py` are range variables and `n` is an int; the fixpoint at the loop head then finds `zr` and `zi` bounded (the condition gives `|zr|, |zi| <= 4`, and the body adds bounded numbers).

**3. Interval facts in the small-int fast copy.** In the fast copy of a small-int loop (`small_loop`) every variable is a small number at every point. `fast_facts` starts from the loop head's facts with every variable cut to the small range, and follows assignments, `if` and the conditions; an operation whose result interval is inside the small range is emitted as plain `add`/`sub`/`mul nsw`. The intervals also use what the fast copy itself guarantees: `x // 2 + y // 2` needs no check for any small `x` and `y`.

**Soundness checks.** Tests `range_wide`, `float_ranges` and `fast_ranges` (all also under AddressSanitizer and through `site/wasm`). `range_wide` agrees with a Python model of the same loops. Random programs (float loops with conditions on sums of squares, small-int loops near ±2^62, mixed nests with `try`, `break` and range loops) were compiled with the old compiler, the new one, and a build of the new one that tests at every read of a local that its value is inside its interval. All 2,136 programs that finished under the old compiler gave the same output and exit code (1,536 at -O1, 600 at -O2); 364 more were left out because the old compiler's program ran longer than 10 seconds. To see whether this can find mistakes, three compilers were broken on purpose (a root bound too small, float subtraction with swapped bounds, a fast-copy interval too small): all three were caught, but the float ones in only 1 to 3 of 60 programs of a generator (the root bound in none of 60 of the mixed one), so a rare float mistake could still hide.

**Results.** All three changes together, against `bf8eb2ce`. Instructions executed (million, callgrind, release mode, counting inputs, Linux x86-64, valgrind 3.26, clang 21) and wall time (seconds, full inputs, both programs run alternately 21 times, pinned to one core, median; a shared 128-core machine with a load average around 80, so treat the seconds as rough):

| benchmark | count input | before (M) | after (M) | change | full input | before (s) | after (s) | after ÷ before |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| fib | 32 | 183.46 | 183.46 | 0 | 38 | 0.321 | 0.322 | 1.00 |
| sieve | 1000000 | 49.04 | 40.10 | -18.2% | 20000000 | 1.888 | 1.802 | 0.95 |
| matmul | 150 | 138.65 | 138.76 | +0.08% | 400 | 2.108 | 2.123 | 1.01 |
| mandelbrot | 250 | 62.37 | 34.13 | -45.3% | 1000 | 0.210 | 0.140 | 0.67 |
| collatz | 50000 | 70.34 | 70.34 | 0 | 1000000 | 0.304 | 0.335 | 1.10 |
| strings | 150000 | 106.59 | 107.64 | +0.99% | 3000000 | 3.107 | 3.091 | 0.99 |
| sort | 150000 | 50.83 | 50.53 | -0.6% | 3000000 | 0.815 | 0.820 | 1.01 |
| wordcount | 250000 | 155.53 | 155.77 | +0.15% | 5000000 | 0.830 | 0.862 | 1.04 |
| bigint | 10000 | 100.27 | 100.27 | 0 | 40000 | 0.372 | 0.371 | 1.00 |
| objects | 100000 | 106.01 | 106.11 | +0.09% | 2000000 | 2.052 | 2.045 | 1.00 |

- **Mandelbrot** (float intervals): 28.2 M fewer, 14.9 per inner iteration. Tomato ÷ Go 1.62 → 0.89 and Tomato ÷ Rust 2.13 → 1.16 in instructions executed (Go 38.51 M, Rust 29.30 M). The checks also held up the floating-point chain, so this time the wall time follows.
- **Sieve** (range loops): the per-pass free test of the three-argument loop is gone.
- **The fast copy** changes no benchmark: all ten build to the same programs with and without it, because their small-int loops have no variable with a useful bound. Two loops written for it: a linear congruential generator modulo 65536 takes 17.18 → 13.18 M instructions (-23%, wall time 0.11 → 0.09 s at 50,000,000 passes), a bit-reversal loop 267.7 → 172.9 M (-35%, 1.11 → 0.86 s).
- **Regressions** (instructions): strings +1.0%, wordcount +0.15%, objects +0.09%, matmul +0.08%, all from the range-loop fix, which tests each unknown bound once per loop and once more at its end. Strings is more than that: the larger `main` makes the inliner keep `tomato_str_split` and `tomato_str_join` as calls.
- **Regressions** (wall time): collatz +10% and wordcount +4%. Collatz's hot loop is the same instructions before and after, at another address (0x20a0 before, 0x21f0 after). Linked with `-Wl,-plugin-opt=-align-loops=64`, both programs take the same time before and after (collatz 0.295 and 0.296 s, wordcount 0.808 and 0.805 s), so this is code placement. Not fixed: aligning loops in `tomato build` was not measured for the other benchmarks.
- **Compile time:** compiling the compiler (the `bf8eb2ce` sources, callgrind) takes 14,672.7 → 14,686.8 M instructions (+0.1%).

*Not tried further:* marking the error branches unlikely (`!prof` weights on every `fail_if`). An experiment on the emitted IR gave matmul -2.4% and strings -0.7%, but sieve +2.2% and objects +0.7%.

## What was done (refcount bookkeeping, v0.51)

Profile first (callgrind in the Lima VM, release mode, `benchmarks/count.sh` inputs): in `wordcount` and `strings` about 20% of the instructions, and in `objects` about 13%, were `destroy_object`, `free_internals` and `each_child` walking the type tables to free values that own nothing (every temporary string, every object with only number fields), and the inlined `tomato_release` ran the cycle-collector test (colour bits, kind table, offsets table) on every release that did not reach zero. The collector itself never ran in these three.

1. **Destroy fast paths** (runtime): a string, or a list of plain numbers, is freed at once; an object is destroyed in one pass over its offsets table (references, then the int fields) and a list of references in one loop, without the indirect `release_visit` call.
2. **`tomato_release_flat`**: the compiler picks it when the static type can never be part of a cycle (`str`, or a class with no reference-counted fields and no subclass; `Mod.flat_type`). It only decrements and destroys at zero, with no table lookups. It is used for `release`, for stores into a variable of such a type, and in the function epilogue.

| benchmark | before (M instr) | after | after ÷ before |
| --- | ---: | ---: | ---: |
| objects | 116.3 | 95.8 | 0.82 |
| wordcount | 191.8 | 157.3 | 0.82 |
| strings | 140.4 | 117.1 | 0.83 |
| matmul | 131.5 | 131.5 | 1.00 |

Not done, with the profile's reason: **list indexing** is already a bounds check plus a load in matmul's inner loop (about 28 instructions per iteration, none of them reference counting; the rest is tag tests, the overflow check on `+`/`*` and two bounds checks), so there is nothing refcount-related left there. The loop item of `for x in xs` is still retained and released (about 13 of the 35 instructions per item in `objects`; it was in fact 16 of 51, see "borrowed loop items, measured"): dropping it needs proof that the body cannot remove the item from the list, which a method call can do through an alias (done later for simple bodies, see that section).

Also in this change: a failing check now frees the temporaries waiting in its expression (see D05av in `docs/decisions.md` and the `temp_unwind` test), and the big-number leak check is strict after errors again.

## What was done (borrowed loop items, measured)

Commit `1a3a342e` stopped retaining the loop item of `for p in xs` when the body provably cannot change a list (`Gen.lent_loop_body`); this is what it saves per item in `objects`, whose two loops over `particles` both qualify (`p.step(round)`, 10 times per particle, and `total += p.x`, once).

**Method.** Same tree (`da596c95`), same runtime, same toolchain (clang 21.1.8, release mode, LTO working); two compilers differing in one line (the borrow gate `lent = self.lent_loop_body(...)` replaced by `lent = False`). `valgrind --tool=callgrind` (3.26.0), instructions executed by the whole process, Linux x86-64. `perf stat` was not available (`perf_event_paranoid` 4, no root). The count does not depend on machine load (load average was about 64 on 128 cores), so "quiet machine" matters for timing, not for this. Both programs print the same checksum. Per-item numbers are slopes between runs that differ only in `n` or in the number of rounds, so start-up (172.6 K instructions) and the build loop cancel.

| `objects` at n = 100000 | instructions |
| --- | ---: |
| loop item retained (before) | 60,534,589 |
| loop item borrowed (after) | 42,734,740 |
| saved | 17,799,849 (29.4%) |

| loop | saved per item | loop body per item, before → after |
| --- | ---: | ---: |
| `p.step(round)` (10 rounds, 1,000,000 items) | 16.0 (steady state, rounds 3 to 10) | 51 → 35 instructions |
| `total += p.x` (100,000 items) | 17.0 | |

Per particle (all 11 items): 601.1 → 423.1 instructions, 178.0 saved (the 10 rounds are 160.0 of that). The 16 instructions in the step loop are exactly the disassembled difference: a null test, a load, a sign test, an increment and a store to retain the new item (7), the same plus a branch to release the previous one (8), and one register move. With the borrow the item is just loaded from the list's data pointer.

The 13-of-35 estimate under "Not done" in the refcount bookkeeping section was low: the retain and release were 16 of 51.

## What was done (collatz and small-int arithmetic)

Profile first (`otool -tV` of the release binary, the emitted IR from `tomato compile`): `collatz` is pure small-int arithmetic, and every operation was already an inlined fast path, but the hot loop was long and tangled:

- the slow (big-integer) calls were ordinary `noinline` functions, so the optimiser laid the cold calls out between the hot instructions and kept values live across them;
- `x % 2 == 0` and `x // 2` went through the general floor-divide-and-fix-the-sign code, with a `tomato_int_sign` zero check of the (constant) divisor;
- `+`, `-`, `*` untagged both operands, did the operation, then range-checked and re-tagged; comparisons also tested for the word 0 (a zeroed slot) before comparing;
- in **debug mode** the runtime is a separate compilation unit (no LTO), so every add, compare, `dup` and `free` was a real call (collatz 1.60 s against 0.50 s in release). That is the "debug-mode small-int regression": the big-integer ownership code added a `dup`/`free` per assignment, which only hurts when each is a call.

Changes (language semantics unchanged: an overflow still becomes a big integer):

1. The slow paths are `cold` (`COLD` in the runtime): the hot loop is now straight-line code and the big-number calls sit out of line. collatz 0.50 → 0.45 s alone.
2. `x // 2^k` and `x % 2^k` with a constant power-of-two divisor compile to `tomato_int_floordivp2_c` / `tomato_int_modp2_c`: on a tagged word `(w >> k) | 1` and `(w & mask) | 1` (the floor modulo of a power of two is never negative, so no sign fix). A constant non-zero divisor no longer emits the zero check.
3. `+ - *` work on the tagged words and use the overflow flag of the 64-bit operation as the range check (`x + (y - 1)`, `x - (y - 1)`, `(x - 1) * (y >> 1)`): for a tagged word 2v+1 the 64-bit overflow is exactly "the result leaves -2^62 .. 2^62 - 1". Comparisons of two odd words compare the words.
4. **Debug mode links with `-flto` too** (still `-O1`, still the leak check and full error text), so the runtime fast paths inline into the program in both modes; it falls back to a plain link when clang has no LTO. Debug compile and link time did not grow (0.6 s → 0.4 s on collatz). *(Superseded: debug mode no longer links with LTO; see "Debug builds without LTO" at the end.)*

Measured on a loaded machine (load average 2.5 to 3), alternating runs, medians of 11 (user seconds): collatz release 0.51 → 0.28 s (Tomato ÷ Go 2.7 → 1.47, Tomato ÷ Rust 3.9 → 2.15 against the Go 0.19 s and Rust 0.13 s of the same session), collatz debug 1.60 → 0.27 s, fib debug 0.60 → 0.15 s, sieve debug 0.24 → 0.21 s; release fib 0.23 → 0.15 s, matmul 0.17 → 0.14 s, sieve unchanged (memory-bound). Test: `int_fast_paths` (constant and variable divisors agree on negative numbers, 0 and the 2^62 edge; `+ - *` across the edge; comparisons).

(Round two follows below; this paragraph is what round one left.) Not done then: collatz is still 1.5 times Go. Rust is probably branch-free on the `if x % 2 == 0` (not checked); Tomato keeps the branch, which is unpredictable on this input. Keeping untagged machine words across the loop when the type analysis proves no overflow is the next step and needs range reasoning the compiler does not have; the `<<`, `>>` operators do not help here (`x // 2` already is one shift).

## What was done (collatz, round two)

**Evidence first.** `benchmarks/count.sh --only collatz` (instructions executed, count input 50,000, 5,024,987 loop iterations): Tomato 123.5 million, Go 36.5 million, Rust 36.0 million, that is 24.6 instructions per iteration against 7.3 and 7.2. The emitted IR (`tomato compile`) and the arm64 code of the release loop showed where they go:

- the slow paths were already `cold` and out of line, but every operation tested the tag bit of its operand again (`x % 2`, `x // 2`, `3 * x`, `+ 1`, `length + 1`): LLVM cannot carry "x is small" across the merge after a slow call, so a loop iteration made five to six tag tests and kept the overflow flag, the tag and the big-number branch of each operation in the hot path;
- `x != 1` went through the general compare (a tag test on both words, then the three-way result), and `x % 2 == 0` freed the remainder after the compare;
- each assignment loaded the old value of `x` and `length`, stored, and tested the old word for freeing;
- `3 * x + 1` is two checked operations, each with its own tag test of the result of the other.

**Changes** (semantics unchanged: an overflow still becomes a big integer, tests `small_int_loops` and `int_fast_paths`):

1. **Small-int loops are compiled twice** (`small_loop` in `compiler/src/compiler.tom`). A `while` whose condition is a comparison and whose body is only int assignments (`+ - *`, `//` and `%` by a constant power of two) and `if`/`elif`/`else` on comparisons gets a *fast copy* that assumes every int variable it uses is a small number. The assumption is checked once when the loop is entered and again every time the general copy comes back to the loop head, by AND-ing the words and testing bit 0. The fast copy has no tag tests, no big-number calls and no frees: a `+ - *` is a 64-bit operation on the tagged words whose overflow flag (`llvm.*.with.overflow`) sends control to the start of the *same statement* in the general copy (nothing of the statement has been stored yet, so repeating it is exact); the general copy then carries on with big numbers exactly as before and returns to the fast copy at the next loop head when everything is small again. Both copies share the variable slots, so no state is copied. Loops with calls, `break`, `continue`, other loops, floats, list or field access, or a variable that is not a plain local `int` are not touched.
2. **`x = x op e` hands the old number to the operation** (`self_update`): when the right side is built from `+ - *` and a constant non-zero `//` or `%` with `x` read once, the operation frees `x` itself in its out-of-line big-number path and the store frees nothing (the general copy and every loop that does not qualify for the fast copy use this).
3. **`x == k` and `x != k` with a small constant** compare the words (a big number is never equal to a small one) and the remainder of `x % 2^k` is known small, so the compare and its free disappear.

**Result** (count input 50,000, instructions executed): collatz 123.5 → 55.0 million, 24.6 → 10.9 per iteration; Tomato ÷ Go 3.39 → 1.51 and Tomato ÷ Rust 3.43 → 1.53 (Go 36.5 million, Rust 36.0 million). Other benchmarks, same counting run: fib 127.0, sieve 42.6, matmul 131.4, bigint 83.3, objects 116.3, strings 140.4 million (all unchanged), mandelbrot 106.7 → 102.4 million. The fast copy's loop is eight instructions on the halving path and 16 on the `3x + 1` path: `asr`, `tbnz` on bit 1 for `x % 2`, then `orr`/`adds`/`b.vc` for `x // 2` and `length + 1`, `cmp` and branch for `x != 1`.

Wall clock (user seconds, release, input 1,000,000, 9 alternating runs, median, **load average 38 to 51** so every number is inflated and noisy): before 0.43, after 0.32, Go 0.27, Rust 0.20: Tomato ÷ Go 1.59 → 1.19, Tomato ÷ Rust 2.15 → 1.60 on that run (the Go and Rust binaries were built on this Mac with `go build` and `rustc -O`).

What is left: the remaining difference is the `adds` + branch of each checked add and the multiply check on the `3x + 1` path (Rust and Go test no overflow because their ints wrap), the `x != 1` compare and the `x % 2` branch, which is as unpredictable here as in Go. Fusing `3 * x + 1` into one checked operation saves about three instructions on a third of the iterations (not done). Extending the fast copy to `for` loops over a range, `and`/`or`/`not` in conditions and `break`/`continue` is the next step; mandelbrot is floats and does not use it.

## What was done (function values and sort)

- `sorted(xs, key=f)`: the keys are worked out once per item in Tomato, then the runtime (`tomato_list_sorted_by`) stable-merge-sorts (key, position) pairs and gathers the items. 3,000,000 ints with `key=`: about 0.3 s for the sort (whole program 0.54 s; Python `sorted(key=lambda)` about 2.3 s, Rust `sort_by_key` 0.14 s on this loaded machine). Plain `sorted(xs)` is untouched (native introsort, same 0.17 s program as before).
- `sorted(xs, cmp=f)`: a stable run-detecting merge sort written in Tomato (`std/builtin/sorting.tom`), so it also runs in the browser, where the C runtime cannot call back into the interpreted program. It took about 2.3 s for 3,000,000 ints before the small-int work (Python `cmp_to_key` about 12 s, Rust `sort_by` 0.12 s); the inlined small-int paths (see the collatz section) brought it to 0.69 s on its own.
- **Native cmp sort (v0.51):** on native builds `sorted(xs, cmp=f)` calls `tomato_list_sorted_cmp` instead: a stable merge sort in the runtime (binary-insertion blocks of 16, then bottom-up merges, neighbours already in order copied not merged) that calls `f` through its function pointer with its own words as borrowed arguments (no copy, no per-call retain or free) and stops at the first error `f` raises, giving every item back. The compiler emits `tomato_callbacks()` and branches on it: 1 on native builds, 0 in the browser (`TOMATO_WASM`, `__wasi__`), where the Tomato sort (`_sorted_cmp`) still runs. It is used when the items are 8-byte slots holding an int or a pointer (not float, bool or the fixed-width integers; those use the Tomato sort). Measured with `time -l` on the 3,000,000-int program (`benchmarks/sort` generator, `cmp=` a subtraction function), instructions retired and cycles for the whole program on an Apple M1 with a load average above 60 (so wall time was useless, these counters are not): 7.40 G instructions and 2.35 G cycles before, 2.19 G instructions and 0.99 G cycles after (after ÷ before 0.30 and 0.42). Plain `sorted(xs)` is untouched (`benchmarks/count.sh --only sort`: 55.15 M instructions, the same as in the table below). Test: `sort_cmp_native` (sizes around the block and merge boundaries, big ints, text, objects, stability, an error raised mid-sort).

## What was done (after v0.49)

1. **`range(a, b, step)` is a counted loop.** It used to build a `range` object and walk it through its `@iter` method (a generator). The compiler now works out the number of rounds once (`(distance - 1) / |step| + 1`, 0 when empty; a zero step raises the same `RuntimeError`), then counts a hidden index from 0 and sets the loop variable to `start + index * step`, so reassigning the variable in the body does not change the walk, an empty loop leaves the variable alone, and the loop itself is one compare and one add whatever the sign of the step. Like `range(a, b)`, a bound too big for a machine word now stops with `the number is too big here` (the generator version took any big number). Test: `range_step_loop`.
2. **Tighter list indexing in counted loops.** `tag_small` now says the shift cannot overflow (`shl nsw`) and the counter says it does not wrap (`add nsw`, and `llvm.assume(i >= 0)` for loops that count from 0), so LLVM sees through the tag and untag of the loop variable and drops the negative-index wrap (`i < 0 ? i + len : i`) from `xs[i]`; the inner loop of matmul lost 4 instructions per list read.
   Measured in one session, release mode, load average 10 to 14 (so absolute seconds are inflated; old and new were run alternately, 11 runs, median): sieve 0.345 → 0.247 s, matmul 0.314 → 0.258 s.
3. **Typed list storage** was done afterwards, see "compact list storage" above (sieve 0.221 s then).

## What was done (strings)

Measured on the same machine in one session, release mode, medians of 7 runs (noise about ±0.02 s; the machine drifted
about 5% between sessions):

1. **`str(i)` writes its digits straight into the string object** (no `snprintf`, no scratch copy) and **`int(text)`
   parses up to 18 digits into a small integer without allocating limbs**. strings 0.50 → 0.31 s, wordcount 0.61 → 0.36 s
   (the two changes together; `snprintf` was the top cost of wordcount, the limb `calloc` of `int(text)` of strings).
2. **`join` builds the result in place**: one allocation, character count summed from the pieces, no scratch buffer and
   no recount. strings 0.31 → 0.28 s.
3. Kept for tidiness, no measurable gain: `split` on a one-byte separator uses `memchr`, string dict keys compare length
   and bytes directly (and the pointer first).

Tried and dropped: hashing string keys eight bytes at a time (wordcount 0.42 → 0.45 s, slower; the keys are about five
bytes so FNV is already cheap). Not done then (later done, see "text indexing and fused f-strings"): an f-string is still `'w' + str(x)` (two allocations); a runtime call that
formats the pieces into one buffer needs a compiler change, and the rest of the time is `malloc`/`free`, which the
size-class allocator task covers.

## What was done (v0.49)

1. **Borrowed reads need no reference count.** The compiler no longer wraps a read of a local variable in
   retain/release when the local keeps the value alive throughout: indexing (`xs[i]`, `xs[i] = v`), field reads and
   writes (`p.x`), method receivers, `len(xs)` and arguments of the same type. Nothing in an expression can assign a
   local except a list comprehension, which turns the borrow off. A parameter the body never assigns uses the caller's
   reference (no retain on entry, no release at exit). Async and generator frames, which outlive the call, still take their
   own references. sieve 0.45 → 0.25 s, sort 1.17 → 0.69, matmul 0.37 → 0.27, objects 0.33 → 0.18; debug mode gains
   even more (sieve 0.75 → 0.31). The loop item of `for x in xs` is still retained: the body can shrink the list.
2. **Native sort.** `sorted` on `list[int]`, `list[float]` and `list[str]` calls an introsort in the runtime (quicksort,
   heapsort fallback, insertion sort for short runs) instead of a generic merge sort compiled from Tomato. sort 0.69 → 0.12 s
   (a radix sort reached 0.075 s but cannot take a compare function, so it was dropped).
3. **Big integers are freed** (D05av, replacing placeholder P63). Every variable, field and container slot owns its own
   limb array (copied when stored, freed when overwritten, out of scope, consumed or unwound), so no reference counts.
   `bigint` (40000): 0.224 s and 1.53 GB peak memory before; 0.11 s and a few MB after, with the debug-mode leak check
   clean. The price is a slower small-int path in debug mode (see the notes above).

4. **Size-class free-list allocator** for small objects (released in v0.50). Objects up to 256 bytes (every instance, string, list and dict
   header; strings up to about 230 bytes) come from 16 size classes in 16-byte steps, each a singly linked free list carved
   from 64 KB chunks; the class lives in bits 48..52 of the header's type word, so freeing needs no size and no prefix.
   Freed memory is reused within its class but chunks are never returned to the operating system (documented trade-off:
   a program that allocates a lot of one size and then only another keeps the first size's memory). List and dict
   buffers, string builders, big-integer limbs and objects over 256 bytes still use malloc. Under AddressSanitizer (and with
   `-DTOMATO_NO_POOL`) everything uses malloc, so the ASan tests and use-after-free checks are exact; the debug leak
   check counts live objects separately and still works. The runtime has no threads, so there is no locking; the
   WebAssembly build uses the same code. Gains are about 10%: objects, strings and wordcount each ran about 10% faster in
   interleaved runs on a loaded machine; `strings` peak memory grows about 6% (size-class rounding). Remaining malloc in
   those profiles is list/dict buffers and temporary string builders, see Still to do 4.

## What was done (v0.48)

1. **Release mode optimises.** `--mode release` links the program and the runtime with `clang -O2 -flto
   -DTOMATO_RELEASE`, so the runtime's small-integer fast paths (`tomato_int_add`, `_cmp`, `_raw`, ...) and
   retain/release are inlined into the program; release mode skips the leak check at exit. Debug mode is unchanged
   (`-O1`, separate runtime, leak check). Gains: fib, collatz, matmul, sieve, sort roughly halved.
2. **Cycle collector.** `possible_root` no longer buffers objects whose class can never be part of a cycle, and the
   collection threshold grows when a collection frees little. `objects` went from 2.7 s to 0.5 s on its own (0.33 s with
   LTO): before, the collector rescanned the 2-million-element list again and again.
3. **Big integers.** Multiplying a big number by a small one is a single pass over the limbs (128-bit products, no
   scratch array), and big-by-big products are computed straight into their final allocation. `bigint` went from
   1.41 s to 0.22 s.

## Tried and not kept

- `clang -O3 -flto` alone, before the runtime was restructured for inlining: collatz -15%, objects -6%, nothing on fib,
  sieve or sort. The gains came once the hot runtime paths were made inlinable.

## Still to do, biggest first

1. **Sort with compare functions** is done on native builds (see "function values and sort"); the browser still runs the Tomato merge sort, whose every compare is an interpreted call. The native loop takes 0.42 of the cycles of the Tomato merge sort. **Small-int fast paths** are already inlined everywhere in both modes (the collatz section); what remains in the generated code is the tagged-word untag and retag around each operation and the `dup`/`free` pairs on ints passed to calls.
2. **Remaining list-read cost in matmul:** each `b[k][j]` still checks both bounds and tests the tag of each item, now in one test per step (see "toward the speed of Go and Rust"); no reference counting is left in that loop (see the refcount section).
3. **Typed list storage** is done for `bool` and the fixed-width integers (see above); `int` and `float` lists are already 8 bytes per item and cannot shrink.
4. **Strings:** `split` still allocates one string per piece (a `for` loop over it reuses one at a time; f-strings and `+` chains are fused, see "text indexing and fused f-strings").
5. (done, see the collatz section) Debug-mode small-int arithmetic.

## JSON and MessagePack (std/json.tom)

`benchmarks/json/jsonbench.tom` writes a document of N records (nested objects, lists, strings with escapes, ints, floats,
booleans, null; about 207 bytes each), then times `loads`, compact `dumps` and `dumps(indent=2)` (Apple M1, release
build, one run, `/usr/bin/time -l`; the file is read inside the timed run):

| document | `loads` | `dumps` (includes `loads`) | `dumps(indent=2)` (includes `loads`) |
| --- | ---: | ---: | ---: |
| 40,000 records, 8.3 MB | 0.14 s, 124 MB | 0.47 s, 185 MB | 0.53 s, 218 MB |
| 400,000 records, 84.6 MB | 1.7 s, 1.0 GB | 5.0 s, 1.6 GB | not run |

Time and memory grow in proportion to the size (no quadratic string building): about 15 bytes of memory per byte of
document for the parsed tree. The parse is a single C pass (`tomato_json_scan`: strict checking, numbers, string
decoding) into a token tape, then Tomato builds the objects; writing is Tomato appending pieces to a list and joining once.
Text indexing (`s[i]`) was a linear scan for non-ASCII text when the parser was written, which is why it lives in the runtime; a pure Tomato parser took
57 s to walk a 300,000 character string. Writing is the slower half: one small string per token, then the join.

## Instruction counts (deterministic, in an emulated Linux arm64 target)

Wall-clock times on the Mac swing with load, clock speed and background work (our Go and Rust runs show 100-300% spreads),
and real cycle counters on macOS need root and Instruments. `benchmarks/count.sh` instead counts **instructions executed**
by each program under Valgrind (callgrind) inside a Linux arm64 virtual machine on the Mac.

**What it measures, and what it does not.** The number is instructions executed by the whole process, startup included
(Go about 0.7 million, Python tens of millions). It is not cycles: Valgrind has no pipeline model, so it cannot say how many
M1 cycles anything takes, and a program that executes more instructions can still run faster (better instruction-level
parallelism, fewer cache misses). Use it for "did this change make Tomato do less work", not for "how long does it take".

**Why this setup.** QEMU user mode does not exist on macOS, and a VM cannot expose hardware counters (Apple's
Virtualization framework gives the guest no PMU), so `perf stat` is out. Valgrind inside a Lima VM (Ubuntu 24.04 arm64,
Apple Virtualization, 4 cores, 6 GB) needs nothing from the host except Lima. gem5 was not needed. Tomato is built
inside the VM with its own `tomato build` (it only needs clang), so there is no cross-compiling. Go (1.27.4, the Mac's
version) is linked externally, because a plain static Go binary crashes under Valgrind at startup; Rust is 1.100.0 via
rustup; Python is the VM's 3.12.3 (the Mac has 3.9.6, so Python counts are not the same interpreter).

**Setup, once:** `benchmarks/count.sh --setup` (installs Lima with Homebrew, creates the VM `tomato-count`, installs
valgrind, clang, gcc, Go, Rust and Python in it). **Run:** `benchmarks/count.sh [--runs N] [--only a,b] [--smoke]`; it copies
this checkout into the VM, builds every program there, runs each N times (default 2) and writes
`benchmarks/results/instructions.md`. The inputs are about 1/20 of the full ones (column 4 of `benchmarks/sizes.txt`),
because Valgrind is about 50 times slower; the whole run takes roughly 15 minutes. Python's hash seed is fixed and Go
runs with `GOMAXPROCS=1`.

On a Linux machine with `valgrind`, `clang`, `gcc`, Go, Rust and Python, `benchmarks/count.sh --guest` does the counting directly, without a VM (the release's Linux step uses it, and its report goes to `benchmarks/results/linux-x86_64/instructions.md`).

**Reproducibility.** Two runs of every program: Tomato, Rust (except wordcount, 0.007%) and Python agree to the exact
instruction; Go differs by 0.003-0.16% (runtime threads). At the tiny smoke inputs Go's difference is up to 12%, because the
runtime's fixed work dominates, so only the counting inputs are meaningful.

Tomato v0.51 (release mode), instructions executed, millions, and Tomato's count divided by the other's (below 1.0 Tomato
executes fewer instructions; from `benchmarks/results/instructions.md`):

| benchmark | input | tomato | go | rust | python | ÷ go | ÷ rust | ÷ python |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| fib | 32 | 127.0 | 110.0 | 58.8 | 3621.1 | 1.15 | 2.16 | 0.04 |
| sieve | 1000000 | 44.6 | 23.1 | 25.5 | 2706.1 | 1.93 | 1.75 | 0.02 |
| matmul | 150 | 131.4 | 52.4 | 55.2 | 6299.2 | 2.51 | 2.38 | 0.02 |
| mandelbrot | 250 | 56.6 | 28.8 | 25.9 | 7349.7 | 1.96 | 2.19 | 0.01 |
| collatz | 50000 | 54.9 | 36.5 | 36.0 | 8697.6 | 1.51 | 1.52 | 0.01 |
| strings | 150000 | 116.5 | 99.1 | 87.8 | 725.6 | 1.18 | 1.33 | 0.16 |
| sort | 150000 | 53.6 | 48.6 | 26.9 | 1178.3 | 1.10 | 1.99 | 0.05 |
| wordcount | 250000 | 139.3 | 189.1 | 244.6 | 1004.8 | 0.74 | 0.57 | 0.14 |
| bigint | 10000 | 83.3 | 41.1 | 87.6 | 214.7 | 2.03 | 0.95 | 0.39 |
| objects | 100000 | 95.8 | 79.3 | 50.5 | 2283.7 | 1.21 | 1.90 | 0.04 |

Tomato's counts are 1.5-2.5 times Go's and Rust's on the numeric loops (sieve, matmul, mandelbrot, collatz), where the generated code executes the most extra instructions. Instruction counts
alone do not say how those instructions perform, so compare them with the wall-clock table only as a second opinion.
Full output: `benchmarks/results/instructions.md`.

**Error branch weights.** Release IR gives runtime error branches weights 1:10 (error:success); loop bailouts keep their
separate 1:100000 weights. On Linux x86-64, clang 21 and Callgrind 3.26, one run at each counting input with release LTO
gave these whole-process instruction counts (millions), comparing unweighted error branches with 1:10:

| benchmark | unweighted | 1:10 | change |
| --- | ---: | ---: | ---: |
| matmul | 83.851 | 83.783 | −0.08% |
| strings | 69.516 | 69.516 | approximately 0% |
| sieve | 30.317 | 30.081 | −0.78% |
| objects | 60.337 | 60.538 | +0.33% |

Weights of 1:100, 1:1000 and 1:100000 had different tradeoffs; in this run 1:100 increased sieve's count by 3.8%,
while 1:100000 increased it by 0.26%. These counts measure instructions, not elapsed time, and are not a universal
performance guarantee.

## Debug builds without LTO

**Why.** The profile of `tomato build` (a small program, debug mode) showed that clang is about 90% of the time and most of that is the LTO link: fib took 1.15 to 1.4 s, of which `tomatoc` is 0.28 s and the `-O1 -flto` link about 1.0 s. On Linux (clang 21, lld) that link did not even inline the runtime's fast paths: its instruction counts equal a plain `-O1` link (fib 303 M, collatz 82 M, strings 100 M, sort 46 M, matmul 191 M). On the Mac (Apple clang 21, arm64) LTO does inline them, and a plain link without them ran 1.1 to 2.5 times slower (fib 0.045 s → 0.114 s).

**What changed.** Debug mode (the default of `tomato run`, `tomato build` and `tomato test`) no longer uses LTO or the bitcode merge. `native/tomato` puts `runtime/tomato_inline.ll` in front of the program IR (an `awk` step, `inline_merge`) and links with plain `clang -O1` against the runtime compiled as an ordinary object (cached like before, but a `.o` instead of bitcode). The IR file holds `internal alwaysinline` copies of the runtime's integer fast paths (`tomato_int_add_c`, `sub`, `mul`, `floordiv`, `mod`, the power-of-two forms, `cmp`, `shl`, `shr`, `not`, `raw`, `dup`, `free`) and `tomato_retain`; the program's calls of `tomato_X` become calls of `tomato_inl_X`, and anything a copy does not decide itself (a big number, an overflow) calls the real `tomato_X`, which repeats the test and takes the slow path. Nothing in the compiler or the runtime changed, so the bootstrap IR and the wasm files are untouched. Release mode is unchanged (`-O2`, LTO, and the bitcode-merge and plain-link fallbacks with their warning). If the IR file is missing or clang rejects the merged program, the program is linked without the copies and a warning says so.

**Measured** (Linux x86-64 on the shared biggie at load 70 to 120, so the build times are CPU seconds of the whole `tomato build`, minimum of five, and only comparable with each other; instruction counts are exact, Callgrind, whole process, the counting inputs of `benchmarks/sizes.txt`; Mac: wall seconds, minimum of five, Apple clang 21 on an M-series MacBook Pro that was quiet):

| benchmark | build old → new, Linux CPU s | run old → new, Linux M instr | build old → new, Mac s | run old → new, Mac s |
| --- | ---: | ---: | ---: | ---: |
| fib | 1.29 → 0.69 | 303 → 232 | 0.71 → 0.39 | 0.045 → 0.068 |
| collatz | 1.57 → 0.86 | 82 → 82 | 0.76 → 0.39 | 0.077 → 0.077 |
| strings | 1.68 → 0.71 | 100 → 94 | 0.77 → 0.39 | 0.043 → 0.053 |
| objects | 2.10 → 0.84 | 106 → 90 | 0.78 → 0.39 | 0.042 → 0.053 |
| sort | 1.50 → 0.76 | 46 → 33 | 0.83 → 0.40 | 0.027 → 0.028 |
| matmul | 1.82 → 1.68 (noisy) | 191 → 152 | 0.80 → 0.42 | 0.070 → 0.074 |
| quicksort | 1.56 → 0.83 | 179 → 110 | | |
| hof | 1.42 → 0.64 | 90 → 55 | | |

So a debug build is about 2 times faster to build on both machines (the build of a small program is `tomatoc` 0.28 s plus a link that went from about 1.0 s to about 0.4 s). Debug programs run as fast as before or faster on Linux. On the Mac they are still up to 1.5 times slower than the LTO build on call-heavy code (fib, objects, strings), because the copies cover the integer and retain fast paths only: `tomato_release`, `tomato_alloc` and the list and string helpers stay real calls (they use the runtime's static state), where LTO inlined them. That is still faster than a plain link (fib 0.114 s). Two alternatives were measured and not taken: `-O0` for debug (links in 0.13 s, but programs run 1.1 to 2.9 times slower: collatz 82 → 193 M instructions) and a plain `-O1` link without the copies (the same build time, but the Mac slowdown above).

**Keeping the copies right.** `runtime/tomato_inline.ll` is hand-written IR that mirrors the C functions it replaces (the `ALWAYS` functions in `tomato_rt.c`); if one of those changes, change its copy. `tests/run.sh` runs ten programs about the edges of the small-number range through the debug link and compares them with the outputs made by the plain link (`debug link runs NAME like the plain link`), and `debug link:` tests check that no `-flto` is used, that the calls are renamed and that the fallback warns.
