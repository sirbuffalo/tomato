# Instructions executed (deterministic, under Valgrind in a Linux arm64 VM)

Tomato v0.50 (release mode). valgrind-3.22.0 callgrind, Linux 6.8.0-147-generic aarch64, 4 cores. Ubuntu clang version 18.1.3, go1.27.4, rustc 1.100.0, Python 3.12.3. Every program ran 2 times; inputs are the counting inputs from sizes.txt.

These are INSTRUCTIONS EXECUTED by the whole process (startup included), not cycles. Valgrind has no pipeline model, so this says nothing about M1 cycles; it is the same on a busy machine and on an idle one.

| benchmark | input | tomato | go | rust | python |
| --- | --- | ---: | ---: | ---: | ---: |
| fib | 32 | 127.02 M | 109.99 M | 58.82 M | 3621.11 M |
| sieve | 1000000 | 42.64 M | 23.17 M | 25.50 M | 2706.06 M |
| matmul | 150 | 131.45 M | 52.41 M | 55.18 M | 6299.18 M |
| mandelbrot | 250 | 106.74 M | 28.73 M | 25.87 M | 7349.68 M |
| collatz | 50000 | 123.51 M | 36.46 M | 36.02 M | 8697.59 M |
| strings | 150000 | 140.44 M | 98.79 M | 87.82 M | 725.59 M |
| sort | 150000 | 55.15 M | 48.58 M | 26.95 M | 1178.30 M |
| wordcount | 250000 | 191.76 M | 189.16 M | 244.58 M | 1004.80 M |
| bigint | 10000 | 83.23 M | 41.12 M | 87.60 M | 214.74 M |
| objects | 100000 | 116.29 M | 79.23 M | 50.52 M | 2283.65 M |

Tomato's instructions divided by each other language's (below 1.0 Tomato executes fewer instructions, above 1.0 more):

| benchmark | tomato ÷ go | tomato ÷ rust | tomato ÷ python |
| --- | ---: | ---: | ---: |
| fib | 1.15 | 2.16 | 0.04 |
| sieve | 1.84 | 1.67 | 0.02 |
| matmul | 2.51 | 2.38 | 0.02 |
| mandelbrot | 3.72 | 4.13 | 0.01 |
| collatz | 3.39 | 3.43 | 0.01 |
| strings | 1.42 | 1.60 | 0.19 |
| sort | 1.14 | 2.05 | 0.05 |
| wordcount | 1.01 | 0.78 | 0.19 |
| bigint | 2.02 | 0.95 | 0.39 |
| objects | 1.47 | 2.30 | 0.05 |

Run-to-run difference, (largest - smallest) / smallest over 2 runs, in percent:

| benchmark | tomato | go | rust | python |
| --- | ---: | ---: | ---: | ---: |
| fib | 0.0000 | 0.0031 | 0.0000 | 0.0000 |
| sieve | 0.0000 | 0.0602 | 0.0000 | 0.0000 |
| matmul | 0.0000 | 0.0084 | 0.0000 | 0.0000 |
| mandelbrot | 0.0000 | 0.0176 | 0.0000 | 0.0000 |
| collatz | 0.0000 | 0.0032 | 0.0000 | 0.0000 |
| strings | 0.0000 | 0.0762 | 0.0000 | 0.0000 |
| sort | 0.0000 | 0.1010 | 0.0000 | 0.0000 |
| wordcount | 0.0000 | 0.0190 | 0.0071 | 0.0000 |
| bigint | 0.0000 | 0.0243 | 0.0000 | 0.0000 |
| objects | 0.0000 | 0.1551 | 0.0000 | 0.0000 |
