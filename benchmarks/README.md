# Benchmarks

Ten small programs, each written four times with the same algorithm and the same input: Tomato (`.tom`), Go (`.go`),
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
| `sort` | `sorted` on a million integers |
| `wordcount` | a dict from text to count, f-strings |
| `bigint` | unlimited-size integers (n!); Rust uses the num-bigint crate (benchmarks/bigint/Cargo.toml) |
| `objects` | a million heap objects and method calls |

## Running

```sh
benchmarks/run.sh                 # full inputs, 10 runs each in a shuffled order (--seed N, default 1); writes benchmarks/results/results.{json,md}
benchmarks/run.sh --runs 3 --only fib,sort
benchmarks/run.sh --smoke         # tiny inputs, only checks the four versions agree (tests/run.sh does this)
benchmarks/run.sh --site          # also copies the JSON to site/benchmarks.json for the Benchmarks page
```

It needs `clang` (it builds Tomato from this checkout and `measure.c`, the timing helper), `go`, `rustc` and `python3`;
a missing language is skipped. Inputs are in `sizes.txt`. Go is built with `go build`, Rust with `rustc -O`, Tomato with
`tomato build`, Python is run as installed. The results and caveats are on the website's Benchmarks page, and the
compiler improvements they suggest are in `docs/performance.md`.
