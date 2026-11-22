# Benchmark results

Machine: Apple M1, 8 cores, 8 GB, macOS 27.2.1 (Darwin 27.2.0). Tomato v0.46. Median of 7 runs (3 for Python); load average before 4.21 2.26 1.95, after 3.13 2.97 2.42.

| benchmark | input | tomato (s) | tomato-debug (s) | go (s) | rust (s) | python (s) |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| fib | 38 | 0.447 | 0.448 | 0.138 | 0.127 | 8.490 |
| sieve | 20000000 | 0.736 | 0.769 | 0.059 | 0.058 | 4.488 |
| matmul | 400 | 0.779 | 0.781 | 0.061 | 0.067 | 7.989 |
| mandelbrot | 1000 | 0.137 | 0.140 | 0.091 | 0.093 | 9.420 |
| collatz | 1000000 | 1.724 | 1.793 | 0.197 | 0.139 | 15.851 |
| strings | 3000000 | 0.563 | 0.569 | 0.132 | 0.109 | 0.988 |
| sort | 3000000 | 2.110 | 2.130 | 0.242 | 0.080 | 2.535 |
| wordcount | 5000000 | 0.658 | 0.673 | 0.239 | 0.334 | 1.504 |
| bigint | 40000 | 1.413 | 1.448 | 0.069 | 0.424 | 0.652 |
| objects | 2000000 | 2.749 | 2.730 | 0.096 | 0.057 | 6.750 |

Ratio to Rust (1.0 = as fast as Rust; higher is slower):

| benchmark | tomato | tomato-debug | go | rust | python |
| --- | ---: | ---: | ---: | ---: | ---: |
| fib | 3.5 | 3.5 | 1.1 | 1.0 | 66.8 |
| sieve | 12.8 | 13.4 | 1.0 | 1.0 | 77.9 |
| matmul | 11.6 | 11.6 | 0.9 | 1.0 | 118.6 |
| mandelbrot | 1.5 | 1.5 | 1.0 | 1.0 | 101.5 |
| collatz | 12.4 | 12.9 | 1.4 | 1.0 | 113.8 |
| strings | 5.2 | 5.2 | 1.2 | 1.0 | 9.1 |
| sort | 26.4 | 26.7 | 3.0 | 1.0 | 31.7 |
| wordcount | 2.0 | 2.0 | 0.7 | 1.0 | 4.5 |
| bigint | 3.3 | 3.4 | 0.2 | 1.0 | 1.5 |
| objects | 48.0 | 47.6 | 1.7 | 1.0 | 117.8 |
