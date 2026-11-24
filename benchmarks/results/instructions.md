# Instructions executed (deterministic, under Valgrind in a Linux arm64 VM)

Tomato v0.51 (release mode). valgrind-3.22.0 callgrind, Linux 6.8.0-147-generic aarch64, 4 cores. Ubuntu clang version 18.1.3, go1.27.4, rustc 1.100.0, Python 3.12.3. Every program ran 2 times; inputs are the counting inputs from sizes.txt.

These are INSTRUCTIONS EXECUTED by the whole process (startup included), not cycles. Valgrind has no pipeline model, so this says nothing about M1 cycles; it is the same on a busy machine and on an idle one.

| benchmark | input | tomato | go | rust | python |
| --- | --- | ---: | ---: | ---: | ---: |
| fib | 32 | 127.02 M | 109.99 M | 58.82 M | 3621.11 M |
| sieve | 1000000 | 44.63 M | 23.12 M | 25.50 M | 2706.06 M |
| matmul | 150 | 131.45 M | 52.42 M | 55.18 M | 6299.18 M |
| mandelbrot | 250 | 56.61 M | 28.82 M | 25.87 M | 7349.68 M |
| collatz | 50000 | 54.91 M | 36.45 M | 36.02 M | 8697.59 M |
| strings | 150000 | 116.52 M | 99.09 M | 87.82 M | 725.59 M |
| sort | 150000 | 53.65 M | 48.57 M | 26.95 M | 1178.30 M |
| wordcount | 250000 | 139.30 M | 189.09 M | 244.58 M | 1004.80 M |
| bigint | 10000 | 83.33 M | 41.06 M | 87.60 M | 214.74 M |
| objects | 100000 | 95.79 M | 79.32 M | 50.52 M | 2283.65 M |

Tomato's instructions divided by each other language's (below 1.0 Tomato executes fewer instructions, above 1.0 more):

| benchmark | tomato ÷ go | tomato ÷ rust | tomato ÷ python |
| --- | ---: | ---: | ---: |
| fib | 1.15 | 2.16 | 0.04 |
| sieve | 1.93 | 1.75 | 0.02 |
| matmul | 2.51 | 2.38 | 0.02 |
| mandelbrot | 1.96 | 2.19 | 0.01 |
| collatz | 1.51 | 1.52 | 0.01 |
| strings | 1.18 | 1.33 | 0.16 |
| sort | 1.10 | 1.99 | 0.05 |
| wordcount | 0.74 | 0.57 | 0.14 |
| bigint | 2.03 | 0.95 | 0.39 |
| objects | 1.21 | 1.90 | 0.04 |

Run-to-run difference, (largest - smallest) / smallest over 2 runs, in percent:

| benchmark | tomato | go | rust | python |
| --- | ---: | ---: | ---: | ---: |
| fib | 0.0000 | 0.0061 | 0.0000 | 0.0000 |
| sieve | 0.0000 | 0.1725 | 0.0000 | 0.0000 |
| matmul | 0.0000 | 0.1543 | 0.0000 | 0.0000 |
| mandelbrot | 0.0000 | 0.3064 | 0.0000 | 0.0000 |
| collatz | 0.0000 | 0.0090 | 0.0000 | 0.0000 |
| strings | 0.0000 | 0.3854 | 0.0000 | 0.0000 |
| sort | 0.0000 | 0.0555 | 0.0000 | 0.0000 |
| wordcount | 0.0000 | 0.0398 | 0.0052 | 0.0000 |
| bigint | 0.0000 | 0.1132 | 0.0000 | 0.0000 |
| objects | 0.0000 | 0.0527 | 0.0000 | 0.0000 |
