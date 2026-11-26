# Benchmarks

Twenty-five small programs, each written with the same algorithm and input in Tomato (`.tom`), Go (`.go`), Rust (`.rs`), Python (`.py`), C (`.c`), C++ (`.cpp`), Java (`.java`), C# (`.cs`), Swift (`.swift`), JavaScript (`.js`), TypeScript (`.ts`) and PHP (`.php`), in `benchmarks/<name>/`. Each program takes one number on the command line and prints a checksum; `run.sh` checks that every version it runs prints the same. A language without an installed toolchain is left out of the results.

**The other languages' programs exist only as a comparison.** Tomato's own tooling uses no Python; nothing outside
`benchmarks/` runs them.

Where a language has no such thing in its standard library, the program carries a short one of its own: the big numbers of C,
C++, Swift and PHP (`bigint`: one number times a small one, not a general library) and the hash table of C (`wordcount`).
TypeScript runs on Node with its types stripped, so its times are JavaScript's.

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
benchmarks/run.sh                 # full inputs, 10 runs each in one shuffled order (--seed N, default 1); writes benchmarks/results/results.{json,md}
benchmarks/run.sh --runs 3 --only fib,sort   # also --python-runs N and --out DIR
benchmarks/run.sh --langs go,rust # only these other languages (default: every installed one)
benchmarks/run.sh --smoke         # tiny inputs, only checks that the versions agree (tests/run.sh does this for a few languages)
benchmarks/run.sh --site          # also copies the JSON to site/benchmarks.json for the Benchmarks page
benchmarks/run.sh --max-minutes 60 # stop scheduling runs after 60 minutes and save completed results
```

It needs `clang` (it builds Tomato from this checkout, using `compiler/bootstrap/tomatoc.ll`, `measure.c`, the timing helper, and
the C and C++ programs). The other languages are skipped when their tools are missing: `go`, `rustc` (and `cargo`, for
`bigint`), `javac` and `java`, `dotnet` 10 or newer, `swiftc`, `node` (22.6 or newer for TypeScript), `php` and `python3`.
Inputs are in `sizes.txt` (columns: smoke input, full input, input for `count.sh`). Tomato is built twice with `tomato build`,
in release mode (the `tomato` column) and in debug mode (`tomato-debug`); Go with `go build`, Rust with `rustc -O` (`bigint`
with `cargo build --release`, which fetches the pinned `num-bigint` crate once), C and C++ with `clang -O2`, C# with `dotnet
build -c Release`, Swift with `swiftc -O`; the rest are run as installed. It works on macOS and Linux.
The results and caveats are on the website's Benchmarks page, and what they say about the compiler is in `docs/performance.md`.

## Results

`results/results.json` and `results.md` contain the latest Mac run (Apple M3 Pro, 2026-11-25); `site/benchmarks.json` is a copy of that JSON. `results/linux-x86_64/` has the latest Linux run (2026-11-26, tree `1a07719f`, all 25 benchmarks in eight languages (no Java, C#, Swift or PHP: their tools were not on `PATH`), a loaded host: load 76.30/76.50/80.19 before and 62.11/63.52/65.30 after, per `results.md`, with the run pinned to 6 CPUs; `instructions.md` has the instruction counts (the older d83f43b0 ones are `instructions-d83f43b0.md`), `loadavg-1a07719f.log` the load samples; the previous run on the pre-bigfloat tree `c1fae360` is `results-c1fae360.*`); `results/linux-x86_64/v0.51-lto/` has the v0.51 tree built with LTO and measured the same way (Tomato release and debug, Go, Rust and Python, the ten v0.51 benchmarks; that tree's older `run.sh` wrote no `raw.tsv`, so only `results.json` and `results.md` are kept). `raw.tsv` in the other results directories records the individual measurements. The earlier Mac run (Apple M1, ten benchmarks, four languages) is in the git history and summarized in `docs/performance.md`. Instruction counts in `instructions.md` are separate measurements and may be older. `release/perf-snapshot.sh` can turn release results into a section of `docs/performance.md`.

When `--max-minutes` expires or the timing loop receives SIGINT or SIGTERM, the runner summarizes completed measurements. The JSON marks incomplete runs with `partial: true` and records each program's run count. An interruption during the build phase does not produce partial results.

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
