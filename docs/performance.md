# Performance notes

What the benchmarks (`benchmarks/`, results on the website's Benchmarks page) suggest for the compiler and runtime. They
are hypotheses read from the numbers and the generated IR, not profiles; check each with a profiler before building it.

Snapshot (Apple M1, v0.46, release mode = `clang -O2`, median seconds): Tomato is 1.5x (mandelbrot) to 48x (objects)
slower than Rust, beats Python on nine of ten benchmarks, and loses to Python on big integers (1.4 s against 0.65 s).
Release mode and debug mode (`clang -O1`) run at almost the same speed, so the gap is in the generated code and the
runtime, not in the C compiler's optimisation level.

## Suggested improvements, biggest first

1. **Reference-count traffic and the cycle collector's bookkeeping** (`objects` 48x, `sort` 26x, `sieve` 13x, `collatz` 12x).
   Every `tomato_release` that does not free calls `possible_root`, and loops retain and release the same value every
   iteration. Skip counting for values that provably do not escape a loop, borrow loop variables of `for x in list`,
   and keep the root buffer work off the hot path (for example only record candidates for classes that can form a cycle).
2. **Inline the small-integer fast path.** Every `+ - * < ==` on `int` is a call into the runtime (`tomato_int_add`,
   `tomato_int_cmp`, ...) that tests the tag bit and checks overflow. The compiler could emit the tag test and the
   overflow-checked add inline (with `llvm.sadd.with.overflow`) and call the runtime only for big numbers. A quick
   `-flto` experiment only gained about 10-15%, so the calls are not the whole story; inlining is worth doing with item 1.
3. **Typed lists of small values.** `list[int]` and `list[bool]` hold tagged words and go through runtime calls for
   index and store (`sieve`, `matmul`). Compile indexing to a bounds check plus a load/store, and consider unboxed
   `list[bool]` / `list[float]` storage.
4. **Allocation.** Each object is a separate `calloc` plus a header (`objects`). A free list or size-class allocator
   in the runtime would cut the cost of making and freeing millions of small objects.
5. **`sorted`.** Three million integers take 2.1 s against Rust's 0.08 s. Sort tagged small integers directly with a
   specialised comparison (no per-compare runtime call), or use a radix/merge sort for lists of `int`.
6. **Big integers** (`bigint` 1.4 s, Go's `math/big` 0.07 s, Python 0.65 s). Multiplying a big number by a small one
   should be a single pass over the limbs with no allocation of a second number; check `int_mul` for avoidable copies.
7. **Strings** (`strings` 5x). `str(i)`, `join` and `split` allocate one string per piece; a builder for `join` and
   in-place parse in `int(piece)` would help.
