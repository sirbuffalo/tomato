# Benchmark results

Machine: Apple M1, 8 cores, 8 GB, macOS 27.2.1 (Darwin 27.2.0). Tomato v0.49. Median of 10 runs (10 for Python), all runs in one shuffled order (seed 1); load average before 1.95 2.93 2.98, after 1.82 1.93 2.33.

| benchmark | input | tomato (s) | tomato-debug (s) | go (s) | rust (s) | python (s) |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| fib | 38 | 0.236 | 0.597 | 0.139 | 0.124 | 8.288 |
| sieve | 20000000 | 0.269 | 0.381 | 0.055 | 0.053 | 4.349 |
| matmul | 400 | 0.220 | 0.395 | 0.057 | 0.064 | 7.696 |
| mandelbrot | 1000 | 0.125 | 0.148 | 0.092 | 0.088 | 9.382 |
| collatz | 1000000 | 0.516 | 1.608 | 0.195 | 0.136 | 14.951 |
| strings | 3000000 | 0.487 | 0.557 | 0.132 | 0.106 | 0.951 |
| sort | 3000000 | 0.118 | 0.129 | 0.244 | 0.078 | 2.441 |
| wordcount | 5000000 | 0.585 | 0.667 | 0.233 | 0.325 | 1.473 |
| bigint | 40000 | 0.111 | 0.112 | 0.071 | 0.108 | 0.643 |
| objects | 2000000 | 0.184 | 0.234 | 0.097 | 0.057 | 6.677 |

Fastest run and spread ((slowest - fastest) / median), per program:

| benchmark | tomato min (s) | spread | tomato-debug min (s) | spread | go min (s) | spread | rust min (s) | spread | python min (s) | spread |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| fib | 0.235 | 15% | 0.595 | 7% | 0.135 | 63% | 0.123 | 107% | 8.230 | 1% |
| sieve | 0.267 | 16% | 0.379 | 11% | 0.052 | 182% | 0.051 | 93% | 4.224 | 6% |
| matmul | 0.219 | 16% | 0.394 | 10% | 0.056 | 151% | 0.063 | 81% | 7.029 | 27% |
| mandelbrot | 0.121 | 37% | 0.145 | 26% | 0.089 | 87% | 0.088 | 54% | 8.983 | 10% |
| collatz | 0.512 | 8% | 1.605 | 1% | 0.191 | 38% | 0.135 | 37% | 14.245 | 10% |
| strings | 0.482 | 13% | 0.552 | 7% | 0.125 | 62% | 0.103 | 40% | 0.907 | 7% |
| sort | 0.117 | 33% | 0.128 | 28% | 0.241 | 37% | 0.077 | 68% | 2.427 | 3% |
| wordcount | 0.584 | 8% | 0.666 | 5% | 0.227 | 36% | 0.321 | 14% | 1.421 | 6% |
| bigint | 0.109 | 34% | 0.111 | 37% | 0.066 | 133% | 0.107 | 50% | 0.641 | 1% |
| objects | 0.182 | 14% | 0.232 | 17% | 0.091 | 86% | 0.056 | 75% | 6.519 | 4% |

sort, rust-radix: median 0.036 s, fastest 0.034 s, tomato ÷ rust-radix 3.27 (benchmarks/sort/sort_radix.rs; not in the tables above).

Tomato's time divided by each other language's time (below 1.0 Tomato is faster, above 1.0 it is slower):

| benchmark | tomato ÷ go | tomato ÷ rust | tomato ÷ python | tomato-debug ÷ go | tomato-debug ÷ rust | tomato-debug ÷ python |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| fib | 1.69 | 1.91 | 0.03 | 4.28 | 4.83 | 0.07 |
| sieve | 4.92 | 5.13 | 0.06 | 6.96 | 7.25 | 0.09 |
| matmul | 3.87 | 3.46 | 0.03 | 6.94 | 6.20 | 0.05 |
| mandelbrot | 1.36 | 1.41 | 0.01 | 1.61 | 1.67 | 0.02 |
| collatz | 2.64 | 3.79 | 0.03 | 8.23 | 11.82 | 0.11 |
| strings | 3.71 | 4.59 | 0.51 | 4.24 | 5.25 | 0.59 |
| sort | 0.48 | 1.51 | 0.05 | 0.53 | 1.66 | 0.05 |
| wordcount | 2.51 | 1.80 | 0.40 | 2.86 | 2.05 | 0.45 |
| bigint | 1.57 | 1.03 | 0.17 | 1.57 | 1.03 | 0.17 |
| objects | 1.90 | 3.22 | 0.03 | 2.42 | 4.10 | 0.04 |
