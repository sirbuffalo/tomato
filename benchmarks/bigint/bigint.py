# Benchmark: big integers. Computes n! by multiplying one small number at a time. Prints n! mod 1000000007.
import sys

n = int(sys.argv[1])
product = 1
for i in range(2, n + 1):
    product *= i
print(product % 1000000007)
