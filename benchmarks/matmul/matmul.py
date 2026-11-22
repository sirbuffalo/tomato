# Benchmark: integer matrix multiply, n x n, nested loops. Prints the sum of all entries of C = A * B.
import sys

n = int(sys.argv[1])
a = [[(i * j + 1) % 10 for j in range(n)] for i in range(n)]
b = [[(i + j) % 10 for j in range(n)] for i in range(n)]
total = 0
for i in range(n):
    row = a[i]
    for j in range(n):
        acc = 0
        for k in range(n):
            acc += row[k] * b[k][j]
        total += acc
print(total)
