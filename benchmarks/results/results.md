# Benchmark results

Machine: Apple M1, 8 cores, 8 GB, macOS 27.2.1 (Darwin 27.2.0). Tomato v0.48. Median of 7 runs (3 for Python); load average before 2.95 2.73 2.64, after 2.44 2.72 2.67.

| benchmark | input | tomato (s) | tomato-debug (s) | go (s) | rust (s) | python (s) |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| fib | 38 | 0.220 | 0.407 | 0.138 | 0.126 | 8.479 |
| sieve | 20000000 | 0.446 | 0.754 | 0.054 | 0.053 | 4.401 |
| matmul | 400 | 0.370 | 0.777 | 0.058 | 0.064 | 7.809 |
| mandelbrot | 1000 | 0.127 | 0.129 | 0.093 | 0.090 | 9.544 |
| collatz | 1000000 | 0.526 | 1.551 | 0.195 | 0.139 | 15.125 |
| strings | 3000000 | 0.484 | 0.555 | 0.131 | 0.106 | 0.948 |
| sort | 3000000 | 1.167 | 1.998 | 0.243 | 0.079 | 2.559 |
| wordcount | 5000000 | 0.581 | 0.664 | 0.230 | 0.324 | 1.465 |
| bigint | 40000 | 0.224 | 0.220 | 0.066 | 0.423 | 0.651 |
| objects | 2000000 | 0.329 | 0.518 | 0.092 | 0.056 | 6.639 |

Ratio to Rust (1.0 = as fast as Rust; higher is slower):

| benchmark | tomato | tomato-debug | go | rust | python |
| --- | ---: | ---: | ---: | ---: | ---: |
| fib | 1.8 | 3.2 | 1.1 | 1.0 | 67.5 |
| sieve | 8.4 | 14.1 | 1.0 | 1.0 | 82.5 |
| matmul | 5.7 | 12.1 | 0.9 | 1.0 | 121.3 |
| mandelbrot | 1.4 | 1.4 | 1.0 | 1.0 | 105.7 |
| collatz | 3.8 | 11.1 | 1.4 | 1.0 | 108.6 |
| strings | 4.6 | 5.2 | 1.2 | 1.0 | 8.9 |
| sort | 14.8 | 25.4 | 3.1 | 1.0 | 32.5 |
| wordcount | 1.8 | 2.1 | 0.7 | 1.0 | 4.5 |
| bigint | 0.5 | 0.5 | 0.2 | 1.0 | 1.5 |
| objects | 5.8 | 9.2 | 1.6 | 1.0 | 117.8 |
