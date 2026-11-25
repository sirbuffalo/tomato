# What link-time optimisation does to the Linux instruction counts (2026-11-25)

Tomato's own instructions executed (callgrind, release mode, counting inputs from `benchmarks/sizes.txt`, one run: Tomato's count does not vary), in
millions, on the Linux x86-64 box with the fixed toolchain. The benchmark programs and inputs are the same everywhere; only the compiler, runtime and
`native/tomato` change. Instruction counts are not time: they say nothing about cache or branch behaviour.

Three ways of linking a program exist on the current tree (`native/tomato`):

- **LTO**: the working toolchain (the linker's LLVM plugin or `lld`).
- **merge**: a clang whose linker has no LLVM plugin, the case this task makes visible: clang merges the runtime's bitcode into the program (`-mlink-bitcode-file`) and warns.
- **plain**: even the merge fails; the runtime is linked as an object, with no cross-module optimisation (what v0.51 did on the biggie toolchain, silently).

## At the v0.51 tree (`14b191e3`)

The v0.51 tree had no merge path, so a clang without the plugin gave the plain link: the published v0.51 Linux counts (`instructions-v0.51-no-lto.md`).
The same tree, rebuilt with the working toolchain:

| benchmark | v0.51 plain (published) | v0.51 LTO | LTO effect |
| --- | ---: | ---: | ---: |
| fib | 342.05 | 183.45 | 1.86× |
| sieve | 98.31 | 49.04 | 2.00× |
| matmul | 387.34 | 138.64 | 2.79× |
| mandelbrot | 102.55 | 79.67 | 1.29× |
| collatz | 70.77 | 70.33 | 1.01× |
| strings | 127.67 | 106.59 | 1.20× |
| sort | 71.10 | 50.83 | 1.40× |
| wordcount | 185.51 | 155.53 | 1.19× |
| bigint | 100.44 | 100.27 | 1.00× |
| objects | 147.90 | 106.01 | 1.40× |

This confirms `docs/architecture-review.md` section 3.3 (fib 183.46 M with LTO against 342.05 M without, reproduced as 183.45 M): at v0.51 the lost
LTO made fib, sieve and matmul 1.9 to 2.8 times too slow.

## At `d83f43b0` (v0.51 plus 25 later runtime and compiler changes; the tree of `instructions.md`)

| benchmark | v0.51 LTO | plain | merge | LTO | plain ÷ LTO | merge ÷ LTO |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| fib | 183.45 | 112.96 | 123.54 | 123.53 | 0.91× | 1.00× |
| sieve | 49.04 | 33.63 | 30.63 | 30.31 | 1.11× | 1.01× |
| matmul | 138.64 | 84.49 | 83.90 | 83.85 | 1.01× | 1.00× |
| mandelbrot | 79.67 | 33.69 | 33.56 | 35.52 | 0.95× | 0.94× |
| collatz | 70.33 | 82.43 | 87.15 | 82.12 | 1.00× | 1.06× |
| strings | 106.59 | 84.76 | 78.65 | 69.51 | 1.22× | 1.13× |
| sort | 50.83 | 22.98 | 22.67 | 22.67 | 1.01× | 1.00× |
| wordcount | 155.53 | 175.49 | 157.79 | 149.84 | 1.17× | 1.05× |
| bigint | 100.27 | 72.27 | 72.25 | 71.86 | 1.01× | 1.01× |
| objects | 106.01 | 80.64 | 61.84 | 60.34 | 1.34× | 1.02× |
| nbody | 279.26 | 152.89 | 114.18 | 115.30 | 1.33× | 0.99× |
| spectral_norm | 178.57 | 76.93 | 76.86 | 75.87 | 1.01× | 1.01× |
| fannkuch | 846.44 | 307.92 | 268.37 | 278.05 | 1.11× | 0.97× |
| nqueens | 24.10 | 18.25 | 15.15 | 15.06 | 1.21× | 1.01× |
| binary_trees | 112.61 | 145.31 | 110.94 | 112.05 | 1.30× | 0.99× |
| levenshtein | 206.73 | 85.46 | 74.16 | 72.91 | 1.17× | 1.02× |
| knapsack | 184.89 | 66.81 | 66.82 | 66.81 | 1.00× | 1.00× |
| life | 167.63 | 87.78 | 76.71 | 78.72 | 1.12× | 0.97× |
| dijkstra | 54.28 | 30.02 | 22.30 | 24.55 | 1.22× | 0.91× |
| quicksort | 134.92 | 51.01 | 48.98 | 48.97 | 1.04× | 1.00× |
| kmers | 147.83 | 182.64 | 157.25 | 139.90 | 1.31× | 1.12× |
| revcomp | 19.04 | 20.31 | 19.13 | 16.37 | 1.24× | 1.17× |
| tokenize | 44.96 | 58.80 | 46.77 | 37.38 | 1.57× | 1.25× |
| crc32 | 72.74 | 31.46 | 31.45 | 31.45 | 1.00× | 1.00× |
| hof | 55.68 | 54.69 | 39.77 | 38.61 | 1.42× | 1.03× |

Reading it. Later work (the fast paths now emitted into the IR, range analysis and others) has taken most of the LTO gain into the compiler: for the
arithmetic programs the three links differ by a few percent (matmul, sort, crc32, knapsack, bigint) and the cost of a lost LTO is now below 1.1 times.
Programs that call across the runtime still gain (objects 1.34, tokenize 1.57, kmers 1.31, wordcount 1.17 for plain against LTO), and **the merge fallback
recovers nearly all of that** (objects 1.02, nbody 0.99, binary_trees 0.99, hof 1.03 against LTO; tokenize 1.25 and kmers 1.12 are what it does not
recover). Two programs go the other way: fib needs 9% more instructions with the merge or LTO than with a plain link (123.5 M against 113.0 M), the same
for both, so it is the inlining of the runtime into the program, not the LTO linker; the instruction count does not say whether time follows (the
Linux timings will). collatz needs 17% (plain, LTO) to 24% (merge) more instructions than at v0.51: a change since v0.51, not a link effect.
