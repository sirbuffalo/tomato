# Performance notes

What the benchmarks (`benchmarks/`, results on the website's Benchmarks page) say about the compiler and runtime, and
what has been done about it. Every change below was measured with `benchmarks/run.sh` on the same Apple M1 (release
mode, median seconds) and kept only when it helped.

## Snapshot

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
- A free-list allocator for small objects was not tried yet; after the collector change `objects` is no longer
  dominated by allocation.

## Still to do, biggest first

1. **Sort with compare functions:** the introsort for plain lists is done; a stable Timsort-style merge sort for compare
   and key functions needs function values first.
2. **`range(a, b, step)` loops** allocate a range object and iterate it through method calls (`sieve`); compile them to a
   counted loop like `range(a, b)`.
3. **Typed list storage** (`list[bool]` as bytes, unboxed floats) if measurements justify it.
4. **Strings** (Tomato ÷ Rust 4.6 on `strings`): `str(i)`, `join` and `split` allocate one string per piece.
5. **Debug-mode small-int arithmetic** got slower with the big-integer ownership change (fib 0.41 → 0.60 s); recover it.
6. **Size-class free-list allocator** for small objects (`objects`, `strings`, `wordcount`).
