# Performance notes

What the benchmarks (`benchmarks/`, results on the website's Benchmarks page) say about the compiler and runtime, and
what has been done about it. Every change below was measured with `benchmarks/run.sh` on the same Apple M1 (release
mode, median seconds) and kept only when it helped.

## Snapshot

v0.48 (median of 7 runs, load average about 2.7): Tomato release is 1.4x (mandelbrot) to 15x (sort) slower than Rust,
beats Rust on big integers, and beats Python on all ten benchmarks. Debug mode (`clang -O1`, no LTO, leak check) is now
1.0x to 2.9x slower than release.

| benchmark | v0.46 release | v0.48 release | v0.48 debug | Rust | change |
| --- | ---: | ---: | ---: | ---: | --- |
| fib | 0.447 | 0.220 | 0.407 | 0.126 | 2.0x faster |
| sieve | 0.736 | 0.446 | 0.754 | 0.053 | 1.7x |
| matmul | 0.779 | 0.370 | 0.777 | 0.064 | 2.1x |
| mandelbrot | 0.137 | 0.127 | 0.129 | 0.090 | 1.1x |
| collatz | 1.724 | 0.526 | 1.551 | 0.139 | 3.3x |
| strings | 0.563 | 0.484 | 0.555 | 0.106 | 1.2x |
| sort | 2.110 | 1.167 | 1.998 | 0.079 | 1.8x |
| wordcount | 0.658 | 0.581 | 0.664 | 0.324 | 1.1x |
| bigint | 1.413 | 0.130 | 0.113 | 0.423 | 6.3x |
| objects | 2.749 | 0.329 | 0.518 | 0.056 | 8.4x |

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
   1.41 s to 0.22 s, faster than Rust's hand-written limb array and Python.
4. **Big integers are freed** (D05av, replacing placeholder P63). Every variable, field and container slot owns its own
   limb array (copied when stored, freed when overwritten, out of scope, consumed or unwound), so no reference counts.
   `bigint` (40000): 0.224 s and 1.53 GB peak memory before; 0.130 s and 2.8 MB after (Rust 0.429 s / 2.1 MB), with the
   debug-mode leak check clean.

## Tried and not kept

- `clang -O3 -flto` alone, before the runtime was restructured for inlining: collatz -15%, objects -6%, nothing on fib,
  sieve or sort. The gains came once the hot runtime paths were made inlinable.
- A free-list allocator for small objects was not tried yet; after the collector change `objects` is no longer
  dominated by allocation.

## Still to do, biggest first

1. **Reference-count traffic in generated code** (`sort` 15x, `sieve` 8x, `objects` 6x, `matmul` 6x). Borrowed reads of a
   local (`xs[i]`, `self.x`, `for x in xs`) are wrapped in a retain/release pair; elide them when the local cannot
   change meanwhile. (In progress.)
2. **`range(a, b, step)` loops** allocate a range object and iterate it through method calls (`sieve`); compile them to a
   counted loop like `range(a, b)`.
3. **`sorted`** is a generic sort written in Tomato IR with a runtime comparison per pair; a native sort for
   `list[int]`/`list[float]`/`list[str]` in the runtime.
4. **Typed list storage** (`list[bool]` as bytes, unboxed floats) if measurements justify it.
5. **Strings** (`strings` 4.6x): `str(i)`, `join` and `split` allocate one string per piece.
