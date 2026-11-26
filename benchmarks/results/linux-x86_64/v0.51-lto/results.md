# Benchmark results

Machine: AMD Ryzen Threadripper 3990X 64-Core Processor, 128 logical CPUs (the run was pinned to 6 otherwise idle ones), 247 GB, Ubuntu 26.04.1 LTS on x86_64 (Linux 7.0.0-43-generic). Tomato v0.51. Median of 10 runs (10 for Python), all runs in one shuffled order (seed 1); load average before 89.69, 69.90, 65.89, after 64.87, 65.25, 65.04.

| benchmark | input | tomato (s) | tomato-debug (s) | go (s) | rust (s) | python (s) |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| fib | 38 | 0.250 | 0.692 | 0.253 | 0.136 | 5.166 |
| sieve | 20000000 | 0.843 | 0.965 | 0.818 | 0.855 | 6.743 |
| matmul | 400 | 0.244 | 0.687 | 0.127 | 0.123 | 9.267 |
| mandelbrot | 1000 | 0.104 | 0.191 | 0.093 | 0.093 | 10.530 |
| collatz | 1000000 | 0.296 | 0.281 | 0.270 | 0.162 | 17.909 |
| strings | 3000000 | 1.552 | 1.581 | 0.489 | 0.762 | 2.618 |
| sort | 3000000 | 0.418 | 0.380 | 0.395 | 0.370 | 7.380 |
| wordcount | 5000000 | 0.294 | 0.450 | 0.459 | 0.434 | 1.974 |
| bigint | 40000 | 0.144 | 0.149 | 0.175 | 0.131 | 0.360 |
| objects | 2000000 | 1.203 | 1.176 | 0.884 | 1.157 | 9.385 |

Fastest run and spread ((slowest - fastest) / median), per program:

| benchmark | tomato min (s) | spread | tomato-debug min (s) | spread | go min (s) | spread | rust min (s) | spread | python min (s) | spread |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| fib | 0.244 | 11% | 0.682 | 15% | 0.244 | 7% | 0.128 | 37% | 5.053 | 38% |
| sieve | 0.549 | 78% | 0.571 | 63% | 0.312 | 121% | 0.442 | 71% | 6.437 | 88% |
| matmul | 0.237 | 132% | 0.670 | 89% | 0.115 | 128% | 0.120 | 98% | 8.514 | 46% |
| mandelbrot | 0.099 | 57% | 0.186 | 48% | 0.091 | 15% | 0.092 | 2% | 9.795 | 30% |
| collatz | 0.286 | 42% | 0.278 | 43% | 0.262 | 36% | 0.160 | 9% | 16.665 | 67% |
| strings | 0.835 | 64% | 1.256 | 42% | 0.388 | 32% | 0.631 | 27% | 2.256 | 76% |
| sort | 0.272 | 51% | 0.335 | 34% | 0.379 | 18% | 0.302 | 62% | 6.677 | 52% |
| wordcount | 0.278 | 144% | 0.430 | 99% | 0.437 | 59% | 0.430 | 54% | 1.878 | 19% |
| bigint | 0.141 | 116% | 0.147 | 105% | 0.163 | 25% | 0.129 | 5% | 0.342 | 30% |
| objects | 1.015 | 28% | 1.002 | 36% | 0.283 | 84% | 0.922 | 39% | 7.993 | 45% |

sort, rust-radix: median 0.386 s, fastest 0.307 s, tomato ÷ rust-radix 1.08 (benchmarks/sort/sort_radix.rs; not in the tables above).

Tomato's time divided by each other language's time (below 1.0 Tomato is faster, above 1.0 it is slower):

| benchmark | tomato ÷ go | tomato ÷ rust | tomato ÷ python | tomato-debug ÷ go | tomato-debug ÷ rust | tomato-debug ÷ python |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| fib | 0.99 | 1.84 | 0.05 | 2.74 | 5.10 | 0.13 |
| sieve | 1.03 | 0.99 | 0.12 | 1.18 | 1.13 | 0.14 |
| matmul | 1.92 | 1.98 | 0.03 | 5.42 | 5.58 | 0.07 |
| mandelbrot | 1.13 | 1.12 | 0.01 | 2.06 | 2.06 | 0.02 |
| collatz | 1.10 | 1.83 | 0.02 | 1.04 | 1.74 | 0.02 |
| strings | 3.17 | 2.04 | 0.59 | 3.23 | 2.07 | 0.60 |
| sort | 1.06 | 1.13 | 0.06 | 0.96 | 1.03 | 0.05 |
| wordcount | 0.64 | 0.68 | 0.15 | 0.98 | 1.04 | 0.23 |
| bigint | 0.82 | 1.10 | 0.40 | 0.85 | 1.13 | 0.41 |
| objects | 1.36 | 1.04 | 0.13 | 1.33 | 1.02 | 0.13 |
