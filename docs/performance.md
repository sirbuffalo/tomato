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

## What was done (function values and sort, unreleased)

- `sorted(xs, key=f)`: the keys are worked out once per item in Tomato, then the runtime (`tomato_list_sorted_by`) stable-merge-sorts (key, position) pairs and gathers the items. 3,000,000 ints with `key=`: about 0.3 s for the sort (whole program 0.54 s; Python `sorted(key=lambda)` about 2.3 s, Rust `sort_by_key` 0.14 s on this loaded machine). Plain `sorted(xs)` is untouched (native introsort, same 0.17 s program as before).
- `sorted(xs, cmp=f)`: a stable run-detecting merge sort written in Tomato (`std/builtin.tom`), so it also runs in the browser, where the C runtime cannot call back into the interpreted program. About 2.3 s for 3,000,000 ints (Python `cmp_to_key` about 12 s, Rust `sort_by` 0.12 s). A first version that sorted positions through `keys[a[j]]` took 3.5 s for `key=`; moving the keys with the positions and then sorting in C fixed that.

## What was done (after v0.49)

1. **`range(a, b, step)` is a counted loop.** It used to build a `range` object and walk it through its `@iter` method (a generator). The compiler now works out the number of rounds once (`(distance - 1) / |step| + 1`, 0 when empty; a zero step raises the same `RuntimeError`), then counts a hidden index from 0 and sets the loop variable to `start + index * step`, so reassigning the variable in the body does not change the walk, an empty loop leaves the variable alone, and the loop itself is one compare and one add whatever the sign of the step. Like `range(a, b)`, a bound too big for a machine word now stops with `the number is too big here` (the generator version took any big number). Test: `range_step_loop`.
2. **Tighter list indexing in counted loops.** `tag_small` now says the shift cannot overflow (`shl nsw`) and the counter says it does not wrap (`add nsw`, and `llvm.assume(i >= 0)` for loops that count from 0), so LLVM sees through the tag and untag of the loop variable and drops the negative-index wrap (`i < 0 ? i + len : i`) from `xs[i]`; the inner loop of matmul lost 4 instructions per list read.
   Measured in one session, release mode, load average 10 to 14 (so absolute seconds are inflated; old and new were run alternately, 11 runs, median): sieve 0.345 → 0.247 s, matmul 0.314 → 0.258 s.
3. **Typed list storage was not done.** In `sieve` the loop is limited by cache misses on a 160 MB list of 8-byte slots (Go uses 1 byte per bool), not by tag arithmetic: 10x the size costs only 13x the time. A byte-sized `list[bool]` would help `sieve` but touches every list operation in the runtime and the IR interpreter; it is a separate task.

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

1. **Sort with compare functions** is done (function values, D63a): the cmp sort is a stable merge sort written in Tomato and is slow
   because every int operation in it goes through the runtime (about 2.3 s for 3,000,000 ints; Rust 0.12 s). Next: inline the
   small-int fast path for comparisons and index arithmetic, or a native merge sort that calls the function directly.
2. **Remaining list-read cost in matmul:** each `b[k][j]` still checks both bounds, tests the tag of each item (for the big-integer copy) and keeps the list pointers in stack slots across the loop.
3. **Typed list storage** (`list[bool]` as bytes, unboxed floats): the likely next win for `sieve` (cache footprint 8x smaller), measured as memory-bound, not tag-bound; needs every list operation and the IR interpreter to know the element width.
4. **Strings:** f-strings and `split` still allocate one string per piece; fuse `'w' + str(x)` chains into one buffer (needs a compiler change).
5. **Debug-mode small-int arithmetic** got slower with the big-integer ownership change (fib 0.41 → 0.60 s); recover it.

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
Text indexing (`s[i]`) is a linear scan today, which is why the parser lives in the runtime; a pure Tomato parser took
57 s to walk a 300,000 character string. Writing is the slower half: one small string per token, then the join.
