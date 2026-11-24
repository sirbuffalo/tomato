# Benchmark: function values. Calls one of four functions chosen from a list n times (each result feeds the next), then
# runs map and filter with lambdas and sorts with a key function over a list of n / 4 numbers. Prints three checksums.
import sys


def f0(x):
    return (x * 3 + 1) % 1000003


def f1(x):
    return (x + 7919) % 1000003


def f2(x):
    return x * x % 1000003


def f3(x):
    return (x ^ 12345) % 1000003


def apply_twice(f, x):
    return f(f(x))


n = int(sys.argv[1])
table = [f0, f1, f2, f3]
x = 1
for i in range(n):
    x = table[i % 4](x + i)
print(x)
y = 0
for i in range(n):
    y = (y + apply_twice(table[i % 4], i)) % 1000000007
print(y)
m = n // 4
xs = [i * 7919 % 100003 for i in range(m)]
squares = list(map(lambda v: v * v % 1009, xs))
odd = list(filter(lambda v: v % 2 == 1, squares))
ordered = sorted(odd, key=lambda v: v % 997 * 1000 + v % 1000)
z = 0
for i in range(len(ordered)):
    z = (z * 31 + ordered[i]) % 1000000007
print(len(ordered), z)
