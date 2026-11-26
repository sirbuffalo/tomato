# Instructions executed on the tree 1a07719f (Linux x86-64, Valgrind callgrind)

Tomato v0.51 plus later work, built from commit 1a07719f (including bigfloat stages 3 and 5), release mode, link-time optimisation. valgrind-3.26.0 callgrind, Linux 7.0.0-43-generic x86_64, clang 21.1.8, go1.27.4, rustc 1.100.0, Python 3.14.4; one run per program, counting inputs from sizes.txt, 2026-11-26. Made by `benchmarks/count.sh --guest --runs 1` in three invocations (the first was cut off by a time limit after levenshtein, so knapsack to hof and levenshtein were counted again separately); instruction counts do not depend on host load (biggie's 1-minute load average, sampled every two minutes, was 61.5 to 65.3 while they ran (11:50 to 12:47)).

| benchmark | input | tomato | go | rust | python |
| --- | --- | ---: | ---: | ---: | ---: |
| fib | 32 | 123.54 M | 103.03 M | 67.28 M | 3378.30 M |
| sieve | 1000000 | 30.08 M | 23.26 M | 24.64 M | 2494.49 M |
| matmul | 150 | 83.79 M | 56.01 M | 55.41 M | 5541.72 M |
| mandelbrot | 250 | 75.57 M | 38.58 M | 29.30 M | 7513.08 M |
| collatz | 50000 | 82.13 M | 53.33 M | 46.14 M | 8545.02 M |
| strings | 150000 | 69.52 M | 108.10 M | 94.28 M | 571.45 M |
| sort | 150000 | 22.67 M | 50.57 M | 35.87 M | 1025.96 M |
| wordcount | 250000 | 168.34 M | 193.20 M | 240.74 M | 934.58 M |
| bigint | 10000 | 71.82 M | 64.18 M | 74.74 M | 369.31 M |
| objects | 100000 | 42.74 M | 82.18 M | 56.46 M | 1959.72 M |
| nbody | 75000 | 236.29 M | 56.32 M | 30.46 M | 4171.73 M |
| spectral_norm | 220 | 102.12 M | 41.58 M | 33.42 M | 3312.21 M |
| fannkuch | 9 | 293.41 M | 124.43 M | 104.64 M | 23491.58 M |
| nqueens | 10 | 15.00 M | 10.63 M | 7.03 M | 304.82 M |
| binary_trees | 11 | 112.86 M | 54.20 M | 107.17 M | 611.94 M |
| levenshtein | 1100 | 75.34 M | 38.40 M | 33.69 M | 5791.97 M |
| knapsack | 700 | 66.82 M | 39.34 M | 31.51 M | 6892.91 M |
| life | 70 | 78.28 M | 29.62 M | 40.56 M | 2832.84 M |
| dijkstra | 160 | 24.26 M | 10.53 M | 7.02 M | 765.42 M |
| quicksort | 100000 | 49.15 M | 25.33 M | 21.79 M | 1769.86 M |
| kmers | 50000 | 157.52 M | 117.95 M | 66.92 M | 1066.62 M |
| revcomp | 50000 | 18.21 M | 42.85 M | 30.83 M | 314.02 M |
| tokenize | 50000 | 38.01 M | 51.24 M | 45.33 M | 907.71 M |
| crc32 | 200000 | 31.45 M | 18.15 M | 9.71 M | 2896.98 M |
| hof | 200000 | 39.02 M | 92.51 M | 21.95 M | 1423.15 M |

Tomato's instructions divided by each other language's (below 1.0 Tomato executes fewer instructions, above 1.0 more):

| benchmark | tomato ÷ go | tomato ÷ rust | tomato ÷ python |
| --- | ---: | ---: | ---: |
| fib | 1.20 | 1.84 | 0.04 |
| sieve | 1.29 | 1.22 | 0.01 |
| matmul | 1.50 | 1.51 | 0.02 |
| mandelbrot | 1.96 | 2.58 | 0.01 |
| collatz | 1.54 | 1.78 | 0.01 |
| strings | 0.64 | 0.74 | 0.12 |
| sort | 0.45 | 0.63 | 0.02 |
| wordcount | 0.87 | 0.70 | 0.18 |
| bigint | 1.12 | 0.96 | 0.19 |
| objects | 0.52 | 0.76 | 0.02 |
| nbody | 4.20 | 7.76 | 0.06 |
| spectral_norm | 2.46 | 3.06 | 0.03 |
| fannkuch | 2.36 | 2.80 | 0.01 |
| nqueens | 1.41 | 2.13 | 0.05 |
| binary_trees | 2.08 | 1.05 | 0.18 |
| levenshtein | 1.96 | 2.24 | 0.01 |
| knapsack | 1.70 | 2.12 | 0.01 |
| life | 2.64 | 1.93 | 0.03 |
| dijkstra | 2.30 | 3.45 | 0.03 |
| quicksort | 1.94 | 2.26 | 0.03 |
| kmers | 1.34 | 2.35 | 0.15 |
| revcomp | 0.42 | 0.59 | 0.06 |
| tokenize | 0.74 | 0.84 | 0.04 |
| crc32 | 1.73 | 3.24 | 0.01 |
| hof | 0.42 | 1.78 | 0.03 |
