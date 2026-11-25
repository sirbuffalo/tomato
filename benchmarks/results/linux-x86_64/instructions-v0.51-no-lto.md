# Instructions executed (deterministic, under Valgrind in a Linux arm64 VM)

Tomato v0.51 (release mode). valgrind-3.26.0 callgrind, Linux 7.0.0-43-generic x86_64, 128 cores. clang version 21.1.8, go1.27.4, rustc 1.100.0, Python 3.14.4. Every program ran 2 times; inputs are the counting inputs from sizes.txt.

These are INSTRUCTIONS EXECUTED by the whole process (startup included), not cycles. Valgrind has no pipeline model, so this says nothing about M1 cycles; it is the same on a busy machine and on an idle one.

| benchmark | input | tomato | go | rust | python |
| --- | --- | ---: | ---: | ---: | ---: |
| fib | 32 | 342.05 M | 102.98 M | 67.27 M | 3377.85 M |
| sieve | 1000000 | 98.31 M | 23.13 M | 24.62 M | 2494.05 M |
| matmul | 150 | 387.34 M | 56.06 M | 55.40 M | 5541.22 M |
| mandelbrot | 250 | 102.55 M | 38.47 M | 29.28 M | 7512.64 M |
| collatz | 50000 | 70.77 M | 53.28 M | 46.12 M | 8544.57 M |
| strings | 150000 | 127.67 M | 106.30 M | 94.27 M | 570.79 M |
| sort | 150000 | 71.10 M | 50.53 M | 35.86 M | 1025.52 M |
| wordcount | 250000 | 185.51 M | 192.67 M | 240.66 M | 933.62 M |
| bigint | 10000 | 100.44 M | 64.10 M | 74.73 M | 368.87 M |
| objects | 100000 | 147.90 M | 97.17 M | 56.45 M | 1959.24 M |

Tomato's instructions divided by each other language's (below 1.0 Tomato executes fewer instructions, above 1.0 more):

| benchmark | tomato ÷ go | tomato ÷ rust | tomato ÷ python |
| --- | ---: | ---: | ---: |
| fib | 3.32 | 5.09 | 0.10 |
| sieve | 4.25 | 3.99 | 0.04 |
| matmul | 6.91 | 6.99 | 0.07 |
| mandelbrot | 2.67 | 3.50 | 0.01 |
| collatz | 1.33 | 1.53 | 0.01 |
| strings | 1.20 | 1.35 | 0.22 |
| sort | 1.41 | 1.98 | 0.07 |
| wordcount | 0.96 | 0.77 | 0.20 |
| bigint | 1.57 | 1.34 | 0.27 |
| objects | 1.52 | 2.62 | 0.08 |

Run-to-run difference, (largest - smallest) / smallest over 2 runs, in percent:

| benchmark | tomato | go | rust | python |
| --- | ---: | ---: | ---: | ---: |
| fib | 0.0000 | 0.0017 | 0.0000 | 0.0000 |
| sieve | 0.0000 | 0.0030 | 0.0000 | 0.0000 |
| matmul | 0.0000 | 0.1649 | 0.0000 | 0.0000 |
| mandelbrot | 0.0000 | 0.1329 | 0.0000 | 0.0000 |
| collatz | 0.0000 | 0.1759 | 0.0000 | 0.0000 |
| strings | 0.0000 | 0.1136 | 0.0000 | 0.0000 |
| sort | 0.0000 | 0.1841 | 0.0000 | 0.0000 |
| wordcount | 0.0000 | 0.0735 | 0.0081 | 0.0000 |
| bigint | 0.0000 | 0.1204 | 0.0000 | 0.0000 |
| objects | 0.0000 | 2.9111 | 0.0000 | 0.0000 |
