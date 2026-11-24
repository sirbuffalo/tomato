# Benchmark results

Machine: AMD Ryzen Threadripper 3990X 64-Core Processor, 128 cores, ,   (Linux 7.0.0-43-generic). Tomato v0.51. Median of 10 runs (10 for Python), all runs in one shuffled order (seed 1); load average before 77.33, 78.74, 77.45, after 73.50, 73.25, 74.13.

| benchmark | input | tomato (s) | tomato-debug (s) | go (s) | rust (s) | python (s) |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| fib | 38 | 0.721 | 0.649 | 0.271 | 0.141 | 5.158 |
| sieve | 20000000 | 1.511 | 1.540 | 1.563 | 1.527 | 10.963 |
| matmul | 400 | 0.808 | 0.731 | 0.373 | 0.126 | 18.443 |
| mandelbrot | 1000 | 0.305 | 0.194 | 0.099 | 0.095 | 16.060 |
| collatz | 1000000 | 0.284 | 0.290 | 0.273 | 0.163 | 26.222 |
| strings | 3000000 | 2.030 | 1.936 | 0.986 | 1.020 | 3.717 |
| sort | 3000000 | 0.518 | 0.567 | 0.539 | 0.549 | 8.855 |
| wordcount | 5000000 | 0.440 | 0.628 | 1.055 | 0.458 | 2.127 |
| bigint | 40000 | 0.164 | 0.141 | 0.449 | 0.134 | 0.361 |
| objects | 2000000 | 1.627 | 1.724 | 1.367 | 1.424 | 12.013 |

Fastest run and spread ((slowest - fastest) / median), per program:

| benchmark | tomato min (s) | spread | tomato-debug min (s) | spread | go min (s) | spread | rust min (s) | spread | python min (s) | spread |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| fib | 0.693 | 24% | 0.638 | 28% | 0.257 | 16% | 0.135 | 20% | 5.033 | 41% |
| sieve | 1.351 | 48% | 1.457 | 41% | 1.278 | 35% | 1.183 | 37% | 6.648 | 58% |
| matmul | 0.699 | 498% | 0.693 | 542% | 0.151 | 77% | 0.113 | 172% | 9.375 | 77% |
| mandelbrot | 0.187 | 43% | 0.188 | 65% | 0.098 | 52% | 0.092 | 57% | 9.717 | 117% |
| collatz | 0.275 | 28% | 0.261 | 18% | 0.267 | 33% | 0.161 | 7% | 17.268 | 84% |
| strings | 1.882 | 58% | 1.885 | 65% | 0.601 | 63% | 0.921 | 16% | 2.745 | 92% |
| sort | 0.498 | 27% | 0.459 | 63% | 0.442 | 47% | 0.449 | 74% | 7.773 | 92% |
| wordcount | 0.427 | 210% | 0.420 | 97% | 0.906 | 30% | 0.429 | 266% | 1.904 | 301% |
| bigint | 0.150 | 136% | 0.136 | 162% | 0.324 | 43% | 0.131 | 118% | 0.345 | 150% |
| objects | 1.436 | 39% | 1.444 | 39% | 1.314 | 21% | 1.341 | 32% | 10.919 | 54% |

sort, rust-radix: median 0.503 s, fastest 0.450 s, tomato ÷ rust-radix 1.03 (benchmarks/sort/sort_radix.rs; not in the tables above).

Tomato's time divided by each other language's time (below 1.0 Tomato is faster, above 1.0 it is slower):

| benchmark | tomato ÷ go | tomato ÷ rust | tomato ÷ python | tomato-debug ÷ go | tomato-debug ÷ rust | tomato-debug ÷ python |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| fib | 2.66 | 5.13 | 0.14 | 2.40 | 4.62 | 0.13 |
| sieve | 0.97 | 0.99 | 0.14 | 0.99 | 1.01 | 0.14 |
| matmul | 2.16 | 6.42 | 0.04 | 1.96 | 5.81 | 0.04 |
| mandelbrot | 3.07 | 3.21 | 0.02 | 1.95 | 2.04 | 0.01 |
| collatz | 1.04 | 1.74 | 0.01 | 1.06 | 1.78 | 0.01 |
| strings | 2.06 | 1.99 | 0.55 | 1.96 | 1.90 | 0.52 |
| sort | 0.96 | 0.94 | 0.06 | 1.05 | 1.03 | 0.06 |
| wordcount | 0.42 | 0.96 | 0.21 | 0.60 | 1.37 | 0.30 |
| bigint | 0.37 | 1.22 | 0.45 | 0.31 | 1.05 | 0.39 |
| objects | 1.19 | 1.14 | 0.14 | 1.26 | 1.21 | 0.14 |
