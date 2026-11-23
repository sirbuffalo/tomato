# Performance notes

What the benchmarks (`benchmarks/`, results on the website's Benchmarks page) say about the compiler and runtime, and
what has been done about it. Every change below was measured with `benchmarks/run.sh` on the same Apple M1 (release
mode, median seconds) and kept only when it helped.

## v0.50 snapshot

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

## What was done (text indexing and fused f-strings, unreleased)

**`s[i]`.** ASCII text was already indexed directly (the character number is the byte offset), but each `s[i]` allocated a one-character string, and text with any non-ASCII character was scanned from the start on every index (quadratic loops). Now: (1) `s[i]` on an ASCII character returns one of 128 shared immortal one-character strings (no allocation, no release work); (2) a string of 256 or more characters that is not all ASCII gets a chunked index (D17c) on its first indexed use: the byte offset of every 64th character, so an index scans at most 63 characters. The index lives in a side table of 4 strings (`chunk_cache` in the runtime, oldest dropped first), not in the string object, so the string layout, string constants and the wasm interpreter are unchanged; the table holds a reference to each indexed string (strings are immutable, so the address cannot be reused) and it is released before the debug-mode leak check. Slices, `find` from a position and extended slices use the same offsets. More than 4 long non-ASCII strings in use at once fall back to the plain scan. Measured with a loop reading every character of a 100,000 character non-ASCII text next to an ASCII one (release mode, user time, machine load average about 35 to 55 from other work): old 27.2 s, new 0.01 s; 300,000 characters take 0.05 s.

**f-strings.** `f'w{i}'` is `'w' + str(i)`, and every `+` and every `str()` made its own string. A chain of `+` whose first two operands include a text literal or a `str(...)` call (at most 16 operands) is compiled to one `tomato_str_cat` call: the parts are evaluated in order, then one allocation is filled, and an int inside `str()` is written as digits straight into it. Error messages for a wrong operand type are unchanged. `benchmarks/count.sh` (instructions executed under Valgrind, whole process): wordcount 191.76 M to 159.70 M (Tomato ÷ old Tomato 0.83; Tomato ÷ Go 1.01 to 0.84, ÷ Rust 0.78 to 0.65); strings is unchanged at 140.44 M (it uses `join` and `split`, not `s[i]` or f-strings). Wall clock, wordcount with n = 5,000,000, release mode, 7 alternating runs, user seconds, load average about 35: old median 0.79 s, new 0.66 s (ratio 0.84, the same as the instruction count).

## What was done (compact list storage, unreleased)

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

## What was done (mandelbrot, unreleased)

The baseline release binary from `dd719982` executed 102.44 M instructions at input 250 on Linux arm64. Callgrind (`--dump-instr=yes --collect-jumps=yes`) attributed 101.68 M (99.26%) to `tomato.main` itself. Matching the instruction addresses to `objdump -d --disassemble=tomato.main` put 99.61 M (97.24%) in the inner `while` condition and body (`0x15a4` through `0x1670` in that binary). The ten `fsub` / `fcmp` / branch sequences in that loop accounted for 57.37 M (56.01% of the whole run). These are self costs that count each executed instruction once. The emitted LLVM IR and disassembly also show unboxed `double` locals in registers, with no per-operation allocation or reference counting.

- **A finite check after every `+ - *`.** A full inner iteration ran three checks in the condition, four in the `t` assignment and three in the `zi` assignment. The three finite checks for `cr` ran once per grid point, outside the inner loop. Infinity and NaN never become finite under `+`, `-` or `*`, so checking the end of a chain catches any non-finite intermediate result. The compiler defers a left operand's check only when the right operand is a numeric local, a numeric literal or a float chain built from those. The right operand keeps its check when the left can require an overload or optional unwrapping. These rules preserve evaluation order, error reporting and temporary cleanup. The arithmetic keeps its original order and rounding.
- **Integer comparison through a three-way runtime call in the emitted IR.** `tomato_int_cmp` returns -1, 0 or 1, which the program compares with 0. The profiled baseline already inlines the fast path for `i < 100` under LTO. The compiler now emits a direct comparison of two small tagged integers and keeps the runtime fallback for other representations. A constant or a known-small operand skips its tag test.

Instructions executed (count.sh, Linux arm64 under Valgrind, input 250, 1 run each, deterministic): mandelbrot 106.7 M → 66.9 M after the finite-check change → 61.5 M with the compare change (Tomato ÷ Go 3.71 → 2.14; Tomato ÷ Rust 4.13 → 2.38). collatz 123.5 M → 103.3 M from the compare change alone. Wall clock (alternating runs of seven at n = 1000, on a machine with a load average of about 50, so only the order of magnitude is trustworthy): before 0.39 s median, after 0.23 s, Go 0.15 s, Rust 0.15 s.

After integrating the later compiler and runtime changes through `b0a638b1`, the same instruction count was 102.50 M on `main` and 56.61 M in both runs with the corrected Mandelbrot optimization. Tomato ÷ Go was 1.97 and Tomato ÷ Rust was 2.19. The programs agreed on the output. Host load average was 3–5 at the start of these runs.

Still to do: about 31 instructions per iteration remain against about 15 in Go, 9 of them the remaining checks (sum for the comparison, the new `zr` and `zi`) and about 10 the tagged counter `i` (tag test on the old value and on the compare, add with overflow test). Removing those needs range reasoning (`i < 100` makes `i + 1` small) that the compiler does not have yet. Tests: `float_chains` (results and errors of chains equal the old compiler's output, including which error comes first).

## What was done (refcount bookkeeping, unreleased)

Profile first (callgrind in the Lima VM, release mode, `benchmarks/count.sh` inputs): in `wordcount` and `strings` about 20% of the instructions, and in `objects` about 13%, were `destroy_object`, `free_internals` and `each_child` walking the type tables to free values that own nothing (every temporary string, every object with only number fields), and the inlined `tomato_release` ran the cycle-collector test (colour bits, kind table, offsets table) on every release that did not reach zero. The collector itself never ran in these three.

1. **Destroy fast paths** (runtime): a string, or a list of plain numbers, is freed at once; an object is destroyed in one pass over its offsets table (references, then the int fields) and a list of references in one loop, without the indirect `release_visit` call.
2. **`tomato_release_flat`**: the compiler picks it when the static type can never be part of a cycle (`str`, or a class with no reference-counted fields and no subclass; `Mod.flat_type`). It only decrements and destroys at zero, with no table lookups. It is used for `release`, for stores into a variable of such a type, and in the function epilogue.

| benchmark | before (M instr) | after | after ÷ before |
| --- | ---: | ---: | ---: |
| objects | 116.3 | 95.8 | 0.82 |
| wordcount | 191.8 | 157.3 | 0.82 |
| strings | 140.4 | 117.1 | 0.83 |
| matmul | 131.5 | 131.5 | 1.00 |

Not done, with the profile's reason: **list indexing** is already a bounds check plus a load in matmul's inner loop (about 28 instructions per iteration, none of them reference counting; the rest is tag tests, the overflow check on `+`/`*` and two bounds checks), so there is nothing refcount-related left there. The loop item of `for x in xs` is still retained and released (about 13 of the 35 instructions per item in `objects`): dropping it needs proof that the body cannot remove the item from the list, which a method call can do through an alias.

Also in this change: a failing check now frees the temporaries waiting in its expression (see D05av in `docs/decisions.md` and the `temp_unwind` test), and the big-number leak check is strict after errors again.

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
4. **Debug mode links with `-flto` too** (still `-O1`, still the leak check and full error text), so the runtime fast paths inline into the program in both modes; it falls back to a plain link when clang has no LTO. Debug compile and link time did not grow (0.6 s → 0.4 s on collatz).

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

## What was done (function values and sort, unreleased)

- `sorted(xs, key=f)`: the keys are worked out once per item in Tomato, then the runtime (`tomato_list_sorted_by`) stable-merge-sorts (key, position) pairs and gathers the items. 3,000,000 ints with `key=`: about 0.3 s for the sort (whole program 0.54 s; Python `sorted(key=lambda)` about 2.3 s, Rust `sort_by_key` 0.14 s on this loaded machine). Plain `sorted(xs)` is untouched (native introsort, same 0.17 s program as before).
- `sorted(xs, cmp=f)`: a stable run-detecting merge sort written in Tomato (`std/builtin.tom`), so it also runs in the browser, where the C runtime cannot call back into the interpreted program. It took about 2.3 s for 3,000,000 ints before the small-int work (Python `cmp_to_key` about 12 s, Rust `sort_by` 0.12 s); the inlined small-int paths (see the collatz section) brought it to 0.69 s on its own.
- **Native cmp sort (unreleased):** on native builds `sorted(xs, cmp=f)` calls `tomato_list_sorted_cmp` instead: a stable merge sort in the runtime (binary-insertion blocks of 16, then bottom-up merges, neighbours already in order copied not merged) that calls `f` through its function pointer with its own words as borrowed arguments (no copy, no per-call retain or free) and stops at the first error `f` raises, giving every item back. The compiler emits `tomato_callbacks()` and branches on it: 1 on native builds, 0 in the browser (`TOMATO_WASM`, `__wasi__`), where the Tomato sort (`_sorted_cmp`) still runs. It is used when the items are 8-byte slots holding an int or a pointer (not float, bool or the fixed-width integers; those use the Tomato sort). Measured with `time -l` on the 3,000,000-int program (`benchmarks/sort` generator, `cmp=` a subtraction function), instructions retired and cycles for the whole program on an Apple M1 with a load average above 60 (so wall time was useless, these counters are not): 7.40 G instructions and 2.35 G cycles before, 2.19 G instructions and 0.99 G cycles after (after ÷ before 0.30 and 0.42). Plain `sorted(xs)` is untouched (`benchmarks/count.sh --only sort`: 55.15 M instructions, the same as in the table below). Test: `sort_cmp_native` (sizes around the block and merge boundaries, big ints, text, objects, stability, an error raised mid-sort).

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
bytes so FNV is already cheap). Not done: an f-string is still `'w' + str(x)` (two allocations); a runtime call that
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

4. **Size-class free-list allocator** for small objects. Objects up to 256 bytes (every instance, string, list and dict
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
2. **Remaining list-read cost in matmul:** each `b[k][j]` still checks both bounds and tests the tag of each item (for the big-integer copy); no reference counting is left in that loop (see the refcount section).
3. **Typed list storage** is done for `bool` and the fixed-width integers (see above); `int` and `float` lists are already 8 bytes per item and cannot shrink.
4. **Strings:** f-strings and `split` still allocate one string per piece; fuse `'w' + str(x)` chains into one buffer (needs a compiler change).
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

**Reproducibility.** Two runs of every program: Tomato, Rust (except wordcount, 0.007%) and Python agree to the exact
instruction; Go differs by 0.003-0.16% (runtime threads). At the tiny smoke inputs Go's difference is up to 12%, because the
runtime's fixed work dominates, so only the counting inputs are meaningful.

Tomato v0.50 (release), instructions executed, millions, and Tomato's count divided by the other's (below 1.0 Tomato
executes fewer instructions):

| benchmark | input | tomato | go | rust | python | ÷ go | ÷ rust | ÷ python |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| fib | 32 | 127.0 | 110.0 | 58.8 | 3621.1 | 1.15 | 2.16 | 0.04 |
| sieve | 1000000 | 42.6 | 23.2 | 25.5 | 2706.1 | 1.84 | 1.67 | 0.02 |
| matmul | 150 | 131.5 | 52.4 | 55.2 | 6299.2 | 2.51 | 2.38 | 0.02 |
| mandelbrot | 250 | 106.7 | 28.7 | 25.9 | 7349.7 | 3.72 | 4.13 | 0.01 |
| collatz | 50000 | 123.5 | 36.5 | 36.0 | 8697.6 | 3.39 | 3.43 | 0.01 |
| strings | 150000 | 140.4 | 98.9 | 87.8 | 725.6 | 1.42 | 1.60 | 0.19 |
| sort | 150000 | 55.2 | 48.5 | 27.0 | 1178.3 | 1.14 | 2.05 | 0.05 |
| wordcount | 250000 | 191.8 | 189.1 | 244.6 | 1004.8 | 1.01 | 0.78 | 0.19 |
| bigint | 10000 | 83.2 | 41.1 | 87.6 | 214.7 | 2.02 | 0.95 | 0.39 |
| objects | 100000 | 116.3 | 79.3 | 50.5 | 2283.6 | 1.47 | 2.30 | 0.05 |

Measured on this branch after merging `main` (which includes the compact list storage; sieve fell from 70.5 to 42.6 million
instructions with it). Tomato's counts are 1.7-4.1 times Go's and Rust's on the numeric loops (sieve, matmul, mandelbrot,
collatz), where the generated code executes the most extra instructions. Instruction counts
alone do not say how those instructions perform, so compare them with the wall-clock table only as a second opinion.
Full output: `benchmarks/results/instructions.md`.
