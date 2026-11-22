# Benchmark: sort n pseudo-random integers (a linear congruential generator). Prints a position-weighted checksum.
import sys

n = int(sys.argv[1])
seed = 12345
values = [0] * n
for i in range(n):
    seed = (seed * 1103515245 + 12345) % 2147483648
    values[i] = seed
ordered = sorted(values)
checksum = 0
for i in range(n):
    checksum = (checksum + (i % 1000 + 1) * ordered[i]) % 1000000007
print(checksum)
