# Benchmark results

Machine: Apple M1, 8 cores, 8 GB, macOS 27.2.1 (Darwin 27.2.0). Tomato v0.50. Median of 10 runs (10 for Python), all runs in one shuffled order (seed 1); load average before 1.84 2.23 2.93, after 1.60 1.99 2.42.

| benchmark | input | tomato (s) | tomato-debug (s) | go (s) | rust (s) | python (s) |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| fib | 38 | 0.236 | 0.597 | 0.135 | 0.124 | 8.292 |
| sieve | 20000000 | 0.221 | 0.255 | 0.053 | 0.052 | 4.344 |
| matmul | 400 | 0.172 | 0.395 | 0.059 | 0.063 | 7.844 |
| mandelbrot | 1000 | 0.124 | 0.148 | 0.093 | 0.089 | 9.466 |
| collatz | 1000000 | 0.515 | 1.608 | 0.196 | 0.136 | 15.168 |
| strings | 3000000 | 0.227 | 0.247 | 0.130 | 0.105 | 0.938 |
| sort | 3000000 | 0.119 | 0.128 | 0.242 | 0.078 | 2.467 |
| wordcount | 5000000 | 0.285 | 0.356 | 0.231 | 0.322 | 1.480 |
| bigint | 40000 | 0.111 | 0.112 | 0.066 | 0.108 | 0.643 |
| objects | 2000000 | 0.162 | 0.215 | 0.097 | 0.057 | 6.601 |

Fastest run and spread ((slowest - fastest) / median), per program:

| benchmark | tomato min (s) | spread | tomato-debug min (s) | spread | go min (s) | spread | rust min (s) | spread | python min (s) | spread |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| fib | 0.235 | 15% | 0.595 | 7% | 0.135 | 67% | 0.122 | 38% | 8.249 | 1% |
| sieve | 0.218 | 25% | 0.251 | 19% | 0.052 | 184% | 0.051 | 95% | 4.164 | 14% |
| matmul | 0.171 | 22% | 0.394 | 11% | 0.056 | 140% | 0.063 | 82% | 7.445 | 11% |
| mandelbrot | 0.123 | 29% | 0.146 | 32% | 0.090 | 97% | 0.088 | 54% | 8.888 | 10% |
| collatz | 0.511 | 8% | 1.605 | 2% | 0.191 | 48% | 0.135 | 33% | 14.263 | 15% |
| strings | 0.212 | 17% | 0.244 | 22% | 0.125 | 50% | 0.102 | 61% | 0.910 | 10% |
| sort | 0.118 | 34% | 0.127 | 32% | 0.240 | 41% | 0.077 | 63% | 2.436 | 5% |
| wordcount | 0.283 | 13% | 0.354 | 11% | 0.227 | 39% | 0.320 | 14% | 1.434 | 6% |
| bigint | 0.110 | 30% | 0.111 | 39% | 0.065 | 142% | 0.107 | 46% | 0.642 | 1% |
| objects | 0.161 | 23% | 0.213 | 17% | 0.091 | 84% | 0.056 | 76% | 6.520 | 6% |

sort, rust-radix: median 0.037 s, fastest 0.035 s, tomato ÷ rust-radix 3.23 (benchmarks/sort/sort_radix.rs; not in the tables above).

Tomato's time divided by each other language's time (below 1.0 Tomato is faster, above 1.0 it is slower):

| benchmark | tomato ÷ go | tomato ÷ rust | tomato ÷ python | tomato-debug ÷ go | tomato-debug ÷ rust | tomato-debug ÷ python |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| fib | 1.74 | 1.90 | 0.03 | 4.41 | 4.80 | 0.07 |
| sieve | 4.19 | 4.28 | 0.05 | 4.83 | 4.93 | 0.06 |
| matmul | 2.91 | 2.71 | 0.02 | 6.68 | 6.22 | 0.05 |
| mandelbrot | 1.34 | 1.40 | 0.01 | 1.60 | 1.67 | 0.02 |
| collatz | 2.63 | 3.78 | 0.03 | 8.21 | 11.80 | 0.11 |
| strings | 1.74 | 2.16 | 0.24 | 1.90 | 2.35 | 0.26 |
| sort | 0.49 | 1.52 | 0.05 | 0.53 | 1.64 | 0.05 |
| wordcount | 1.23 | 0.88 | 0.19 | 1.54 | 1.10 | 0.24 |
| bigint | 1.69 | 1.03 | 0.17 | 1.69 | 1.04 | 0.17 |
| objects | 1.68 | 2.82 | 0.02 | 2.22 | 3.74 | 0.03 |
