# Instructions executed (deterministic, under Valgrind on Linux x86-64)

Tomato built from commit d83f43b0 (VERSION 0.51 plus 25 later runtime and compiler changes; not the v0.51 release tree), release mode, with link-time optimisation (release/check-lto.sh passes). See lto-effect.md for the same counts with and without LTO, and at the v0.51 tree. valgrind-3.26.0 callgrind, Linux 7.0.0-43-generic x86_64, 128 cores. clang version 21.1.8, go1.27.4, rustc 1.100.0, Python 3.14.4. Every program ran 2 times; inputs are the counting inputs from sizes.txt.

These are INSTRUCTIONS EXECUTED by the whole process (startup included), not cycles. Valgrind has no pipeline model, so this says nothing about M1 cycles; it is the same on a busy machine and on an idle one.

| benchmark | input | tomato | go | rust | python |
| --- | --- | ---: | ---: | ---: | ---: |
| fib | 32 | 123.53 M | 103.04 M | 67.28 M | 3378.24 M |
| sieve | 1000000 | 30.31 M | 23.18 M | 24.64 M | 2494.43 M |
| matmul | 150 | 83.85 M | 56.00 M | 55.41 M | 5541.65 M |
| mandelbrot | 250 | 35.52 M | 38.50 M | 29.29 M | 7513.02 M |
| collatz | 50000 | 82.12 M | 53.31 M | 46.13 M | 8544.95 M |
| strings | 150000 | 69.51 M | 106.38 M | 94.28 M | 571.19 M |
| sort | 150000 | 22.67 M | 50.66 M | 35.87 M | 1025.89 M |
| wordcount | 250000 | 149.84 M | 193.04 M | 240.77 M | 934.14 M |
| bigint | 10000 | 71.86 M | 64.16 M | 74.74 M | 369.25 M |
| objects | 100000 | 60.34 M | 94.41 M | 56.46 M | 1959.63 M |
| nbody | 75000 | 115.30 M | 56.40 M | 30.46 M | 4171.67 M |
| spectral_norm | 220 | 75.87 M | 41.59 M | 33.42 M | 3312.15 M |
| fannkuch | 9 | 278.05 M | 124.42 M | 104.64 M | 23491.52 M |
| nqueens | 10 | 15.06 M | 10.62 M | 7.03 M | 304.75 M |
| binary_trees | 11 | 112.05 M | 54.21 M | 107.17 M | 611.87 M |
| levenshtein | 1100 | 72.91 M | 38.40 M | 33.69 M | 5791.91 M |
| knapsack | 700 | 66.81 M | 39.26 M | 31.51 M | 6892.85 M |
| life | 70 | 78.72 M | 29.61 M | 40.55 M | 2832.78 M |
| dijkstra | 160 | 24.55 M | 10.54 M | 7.02 M | 765.35 M |
| quicksort | 100000 | 48.97 M | 25.38 M | 21.79 M | 1769.79 M |
| kmers | 50000 | 139.90 M | 104.79 M | 66.90 M | 1066.53 M |
| revcomp | 50000 | 16.37 M | 39.52 M | 30.83 M | 313.95 M |
| tokenize | 50000 | 37.38 M | 58.91 M | 45.33 M | 907.69 M |
| crc32 | 200000 | 31.45 M | 18.12 M | 9.71 M | 2896.91 M |
| hof | 200000 | 38.61 M | 92.51 M | 21.95 M | 1423.09 M |

Tomato's instructions divided by each other language's (below 1.0 Tomato executes fewer instructions, above 1.0 more):

| benchmark | tomato ÷ go | tomato ÷ rust | tomato ÷ python |
| --- | ---: | ---: | ---: |
| fib | 1.20 | 1.84 | 0.04 |
| sieve | 1.31 | 1.23 | 0.01 |
| matmul | 1.50 | 1.51 | 0.02 |
| mandelbrot | 0.92 | 1.21 | 0.00 |
| collatz | 1.54 | 1.78 | 0.01 |
| strings | 0.65 | 0.74 | 0.12 |
| sort | 0.45 | 0.63 | 0.02 |
| wordcount | 0.78 | 0.62 | 0.16 |
| bigint | 1.12 | 0.96 | 0.19 |
| objects | 0.64 | 1.07 | 0.03 |
| nbody | 2.04 | 3.79 | 0.03 |
| spectral_norm | 1.82 | 2.27 | 0.02 |
| fannkuch | 2.23 | 2.66 | 0.01 |
| nqueens | 1.42 | 2.14 | 0.05 |
| binary_trees | 2.07 | 1.05 | 0.18 |
| levenshtein | 1.90 | 2.16 | 0.01 |
| knapsack | 1.70 | 2.12 | 0.01 |
| life | 2.66 | 1.94 | 0.03 |
| dijkstra | 2.33 | 3.50 | 0.03 |
| quicksort | 1.93 | 2.25 | 0.03 |
| kmers | 1.34 | 2.09 | 0.13 |
| revcomp | 0.41 | 0.53 | 0.05 |
| tokenize | 0.63 | 0.82 | 0.04 |
| crc32 | 1.74 | 3.24 | 0.01 |
| hof | 0.42 | 1.76 | 0.03 |

Run-to-run difference, (largest - smallest) / smallest over 2 runs, in percent:

| benchmark | tomato | go | rust | python |
| --- | ---: | ---: | ---: | ---: |
| fib | 0.0000 | 0.0229 | 0.0000 | 0.0000 |
| sieve | 0.0000 | 0.0847 | 0.0000 | 0.0000 |
| matmul | 0.0000 | 0.0279 | 0.0000 | 0.0000 |
| mandelbrot | 0.0000 | 0.0197 | 0.0000 | 0.0000 |
| collatz | 0.0000 | 0.0090 | 0.0000 | 0.0000 |
| strings | 0.0000 | 0.0415 | 0.0000 | 0.0000 |
| sort | 0.0000 | 0.2108 | 0.0000 | 0.0000 |
| wordcount | 0.0000 | 0.1790 | 0.0177 | 0.0000 |
| bigint | 0.0000 | 0.1046 | 0.0000 | 0.0000 |
| objects | 0.0000 | 0.1249 | 0.0000 | 0.0000 |
| nbody | 0.0000 | 0.1525 | 0.0000 | 0.0000 |
| spectral_norm | 0.0000 | 0.0440 | 0.0000 | 0.0000 |
| fannkuch | 0.0000 | 0.0112 | 0.0000 | 0.0000 |
| nqueens | 0.0000 | 0.0559 | 0.0000 | 0.0000 |
| binary_trees | 0.0000 | 0.2525 | 0.0000 | 0.0000 |
| levenshtein | 0.0000 | 0.0129 | 0.0000 | 0.0000 |
| knapsack | 0.0000 | 0.0338 | 0.0000 | 0.0000 |
| life | 0.0000 | 0.0223 | 0.0000 | 0.0000 |
| dijkstra | 0.0000 | 0.1055 | 0.0000 | 0.0000 |
| quicksort | 0.0000 | 0.2346 | 0.0000 | 0.0000 |
| kmers | 0.0000 | 12.9557 | 0.0035 | 0.0000 |
| revcomp | 0.0000 | 0.0009 | 0.0000 | 0.0000 |
| tokenize | 0.0000 | 0.0263 | 0.0000 | 0.0000 |
| crc32 | 0.0000 | 0.3664 | 0.0000 | 0.0000 |
| hof | 0.0000 | 0.0585 | 0.0000 | 0.0000 |
