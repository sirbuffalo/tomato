# Benchmark: binary trees. Builds and checks many complete binary trees of growing depth (millions of small objects made
# and freed), while one long-lived tree stays in memory. Prints the node counts the way the Benchmarks Game does.
import sys


class Node:
    def __init__(self, left, right):
        self.left = left
        self.right = right


def build(depth):
    if depth == 0:
        return Node(None, None)
    return Node(build(depth - 1), build(depth - 1))


def check(node):
    if node.left is None or node.right is None:
        return 1
    return 1 + check(node.left) + check(node.right)


n = int(sys.argv[1])
min_depth = 4
max_depth = n
if max_depth < min_depth + 2:
    max_depth = min_depth + 2
print(f'stretch tree of depth {max_depth + 1} check: {check(build(max_depth + 1))}')
long_lived = build(max_depth)
depth = min_depth
while depth <= max_depth:
    iterations = 1 << (max_depth - depth + min_depth)
    total = 0
    for i in range(iterations):
        total += check(build(depth))
    print(f'{iterations} trees of depth {depth} check: {total}')
    depth += 2
print(f'long lived tree of depth {max_depth} check: {check(long_lived)}')
