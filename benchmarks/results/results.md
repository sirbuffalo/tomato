# Benchmark results

Machine: Apple M1, 8 cores, 8 GB, macOS 27.2.1 (Darwin 27.2.0). Tomato v0.51. Median of 10 runs (10 for Python), all runs in one shuffled order (seed 1); load average before 1.40 1.97 2.33, after 3.00 2.56 2.39.

| benchmark | input | tomato (s) | tomato-debug (s) | go (s) | rust (s) | python (s) |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| fib | 38 | 0.156 | 0.156 | 0.139 | 0.124 | 8.270 |
| sieve | 20000000 | 0.068 | 0.071 | 0.058 | 0.053 | 4.283 |
| matmul | 400 | 0.144 | 0.142 | 0.061 | 0.065 | 7.443 |
| mandelbrot | 1000 | 0.102 | 0.103 | 0.094 | 0.089 | 9.674 |
| collatz | 1000000 | 0.206 | 0.202 | 0.193 | 0.136 | 15.090 |
| strings | 3000000 | 0.178 | 0.186 | 0.132 | 0.107 | 0.950 |
| sort | 3000000 | 0.111 | 0.101 | 0.245 | 0.079 | 2.457 |
| wordcount | 5000000 | 0.207 | 0.214 | 0.232 | 0.325 | 1.457 |
| bigint | 40000 | 0.111 | 0.111 | 0.071 | 0.108 | 0.643 |
| objects | 2000000 | 0.113 | 0.114 | 0.097 | 0.058 | 6.534 |

Fastest run and spread ((slowest - fastest) / median), per program:

| benchmark | tomato min (s) | spread | tomato-debug min (s) | spread | go min (s) | spread | rust min (s) | spread | python min (s) | spread |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| fib | 0.156 | 114% | 0.156 | 114% | 0.133 | 156% | 0.121 | 143% | 8.191 | 2% |
| sieve | 0.066 | 278% | 0.070 | 262% | 0.053 | 359% | 0.051 | 346% | 4.149 | 8% |
| matmul | 0.143 | 122% | 0.141 | 105% | 0.056 | 331% | 0.062 | 284% | 7.114 | 17% |
| mandelbrot | 0.101 | 181% | 0.101 | 173% | 0.089 | 244% | 0.087 | 220% | 8.812 | 13% |
| collatz | 0.203 | 85% | 0.201 | 93% | 0.191 | 112% | 0.134 | 134% | 14.159 | 21% |
| strings | 0.173 | 120% | 0.177 | 114% | 0.126 | 152% | 0.106 | 184% | 0.932 | 7% |
| sort | 0.110 | 153% | 0.097 | 188% | 0.237 | 89% | 0.078 | 272% | 2.437 | 4% |
| wordcount | 0.206 | 81% | 0.211 | 80% | 0.225 | 94% | 0.315 | 60% | 1.428 | 4% |
| bigint | 0.109 | 160% | 0.109 | 157% | 0.065 | 317% | 0.105 | 158% | 0.631 | 5% |
| objects | 0.111 | 163% | 0.113 | 154% | 0.092 | 232% | 0.055 | 313% | 6.494 | 4% |

sort, rust-radix: median 0.037 s, fastest 0.036 s, tomato ÷ rust-radix 3.03 (benchmarks/sort/sort_radix.rs; not in the tables above).

Tomato's time divided by each other language's time (below 1.0 Tomato is faster, above 1.0 it is slower):

| benchmark | tomato ÷ go | tomato ÷ rust | tomato ÷ python | tomato-debug ÷ go | tomato-debug ÷ rust | tomato-debug ÷ python |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| fib | 1.12 | 1.26 | 0.02 | 1.12 | 1.26 | 0.02 |
| sieve | 1.18 | 1.28 | 0.02 | 1.24 | 1.34 | 0.02 |
| matmul | 2.35 | 2.23 | 0.02 | 2.32 | 2.20 | 0.02 |
| mandelbrot | 1.08 | 1.15 | 0.01 | 1.09 | 1.16 | 0.01 |
| collatz | 1.07 | 1.52 | 0.01 | 1.04 | 1.49 | 0.01 |
| strings | 1.35 | 1.66 | 0.19 | 1.41 | 1.74 | 0.20 |
| sort | 0.45 | 1.40 | 0.05 | 0.41 | 1.27 | 0.04 |
| wordcount | 0.89 | 0.64 | 0.14 | 0.92 | 0.66 | 0.15 |
| bigint | 1.56 | 1.03 | 0.17 | 1.56 | 1.03 | 0.17 |
| objects | 1.17 | 1.94 | 0.02 | 1.18 | 1.97 | 0.02 |
