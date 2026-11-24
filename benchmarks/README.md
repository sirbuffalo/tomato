# Benchmarks

Twenty-five small programs (the first ten are the ones on the website's Benchmarks page and in the v0.51 results; the other fifteen were added after v0.51 and have no published results yet), each written four times with the same algorithm and the same input: Tomato (`.tom`), Go (`.go`),
Rust (`.rs`) and Python (`.py`), in `benchmarks/<name>/`. Each takes one number on the command line and prints a checksum;
`run.sh` checks that all four print the same.

**The Python programs exist only as a comparison.** Tomato's own tooling uses no Python; nothing outside `benchmarks/` runs them.

| Benchmark | What it exercises |
| --- | --- |
| `fib` | recursive function calls, small integers |
| `sieve` | a big list of bools, nested counted loops |
| `matmul` | nested lists, integer arithmetic in triple loops |
| `mandelbrot` | 64-bit float arithmetic, a `while` loop |
| `collatz` | integer division and branching, no memory |
| `strings` | `str(i)`, `join`, `split`, `int(text)` |
| `sort` | `sorted` on millions of integers (`sort_radix.rs` is an extra Rust version that uses a radix sort) |
| `wordcount` | a dict from text to count, f-strings |
| `bigint` | unlimited-size integers (n!); Rust uses the num-bigint crate (benchmarks/bigint/Cargo.toml) |
| `objects` | millions of heap objects and method calls |
| `nbody` | 64-bit floats in objects with float fields, `sqrt` (the Sun and four planets) |
| `spectral_norm` | float arithmetic in nested loops, a small function called tens of millions of times |
| `fannkuch` | permutations in lists: element swaps, prefix reversals, `while` loops |
| `nqueens` | recursive backtracking over lists of bools |
| `binary_trees` | millions of small objects with `Node \| None` children, built, walked and freed recursively |
| `levenshtein` | dynamic programming over two rows, indexing into `str` |
| `knapsack` | dynamic programming over one row, a descending `while` loop |
| `life` | Conway's Game of Life on a torus: lists of lists, modulo wrap-around |
| `dijkstra` | shortest paths on a grid with a hand-written binary heap in a list |
| `quicksort` | a hand-written recursive quicksort (Hoare partition, insertion sort for short ranges) |
| `kmers` | substring slices as `dict` keys, counts for k = 1, 2, 4, 6, 12 |
| `revcomp` | building and joining a long string from one-letter strings, slicing into lines, a `dict` lookup per letter |
| `tokenize` | scanning text one character at a time (`isalpha`, `isdigit`, `ord`) with state flags, no regular expressions |
| `crc32` | bitwise operators (`^`, `&`, `>>`) and a 256-entry table over a long list of bytes, plus Adler-32 |
| `hof` | calls through function values (`list[fn(int) -> int]`), `map` and `filter` with lambdas, `sorted(key=...)` |

## Running

```sh
benchmarks/run.sh                 # full inputs, 10 runs each (Python too) in one shuffled order (--seed N, default 1); writes benchmarks/results/results.{json,md}
benchmarks/run.sh --runs 3 --only fib,sort   # also --python-runs N and --out DIR
benchmarks/run.sh --smoke         # tiny inputs, only checks the four versions agree (tests/run.sh does this)
benchmarks/run.sh --site          # also copies the JSON to site/benchmarks.json for the Benchmarks page
```

It needs `clang` (it builds Tomato from this checkout, using `compiler/bootstrap/tomatoc.ll`, and `measure.c`, the timing
helper), `go`, `rustc` (and `cargo`, for `bigint`) and `python3`; a missing language is skipped. Inputs are in `sizes.txt`
(columns: smoke input, full input, input for `count.sh`). Tomato is built twice with `tomato build`, in release mode (the
`tomato` column) and in debug mode (`tomato-debug`); Go with `go build`, Rust with `rustc -O` (`bigint` with `cargo build
--release`, which fetches the pinned `num-bigint` crate once), and Python is run as installed. It works on macOS and Linux.
The results and caveats are on the website's Benchmarks page, and what they say about the compiler is in `docs/performance.md`.

## Results

`results/results.json` and `results/results.md` are the last run of `run.sh` on the Mac (`site/benchmarks.json` is a copy of
the JSON); `results/instructions.md` is the last `count.sh`. When `release/release.sh` runs its Linux step, the same three
files for Linux x86-64 go in `results/linux-x86_64/`. `release/perf-snapshot.sh` turns them into the newest section of
`docs/performance.md`.

## json

`benchmarks/json/jsonbench.tom` (not part of `run.sh`; no other language is compared): `tomato build` it, then
`jsonbench gen FILE N` writes a document of N records, and `jsonbench loads|dumps|pretty FILE` parses it (and writes it
back). Results are in docs/performance.md.

## cache_scaling.tom

`benchmarks/cache_scaling.tom` (run it with `tomato run benchmarks/cache_scaling.tom`; not part of `run.sh`) times a million
`set` and `get` calls on `std/cache.tom` caches of very different sizes, to check that each call takes constant time.

## count.sh: instructions executed, not time

`benchmarks/count.sh` runs the same programs under Valgrind (callgrind) and reports instructions executed, which do not
depend on machine load. On a Mac it runs them in a Linux arm64 VM (Lima): `benchmarks/count.sh --setup` once, then
`benchmarks/count.sh`. On a Linux machine that has `valgrind`, `clang`, `gcc`, `go`, `rustc` and `python3`,
`benchmarks/count.sh --guest` does the counting directly (this is what the release's Linux step runs). It reports
instructions, not cycles. Details and results: docs/performance.md.
