# Benchmark: Dijkstra's shortest paths on an n x n grid of pseudo-random step costs (1..9), from the top-left corner, with a
# hand-written binary min-heap of encoded (distance, cell) numbers. Prints the distance to the far corner and the sum
# of all distances.
import sys


def push(heap, size, key):
    if size == len(heap):
        heap.append(key)
    else:
        heap[size] = key
    i = size
    while i > 0:
        parent = (i - 1) // 2
        if heap[parent] <= key:
            break
        heap[i] = heap[parent]
        i = parent
    heap[i] = key
    return size + 1


def pop(heap, size):
    # removes the smallest key (the caller has read heap[0]) and returns the new size
    size -= 1
    key = heap[size]
    i = 0
    while True:
        child = 2 * i + 1
        if child >= size:
            break
        if child + 1 < size and heap[child + 1] < heap[child]:
            child += 1
        if heap[child] >= key:
            break
        heap[i] = heap[child]
        i = child
    heap[i] = key
    return size


n = int(sys.argv[1])
seed = 2024
cost = [0] * (n * n)
for i in range(n * n):
    seed = (seed * 1103515245 + 12345) % 2147483648
    cost[i] = seed // 65536 % 9 + 1
cells = n * n
infinity = 1000000000
dist = [infinity] * cells
heap = [0] * 16
size = 0
dist[0] = 0
size = push(heap, size, 0)
while size > 0:
    top = heap[0]
    size = pop(heap, size)
    d = top // cells
    cell = top % cells
    if d > dist[cell]:
        continue
    y = cell // n
    x = cell % n
    if y > 0 and d + cost[cell - n] < dist[cell - n]:
        dist[cell - n] = d + cost[cell - n]
        size = push(heap, size, dist[cell - n] * cells + cell - n)
    if y < n - 1 and d + cost[cell + n] < dist[cell + n]:
        dist[cell + n] = d + cost[cell + n]
        size = push(heap, size, dist[cell + n] * cells + cell + n)
    if x > 0 and d + cost[cell - 1] < dist[cell - 1]:
        dist[cell - 1] = d + cost[cell - 1]
        size = push(heap, size, dist[cell - 1] * cells + cell - 1)
    if x < n - 1 and d + cost[cell + 1] < dist[cell + 1]:
        dist[cell + 1] = d + cost[cell + 1]
        size = push(heap, size, dist[cell + 1] * cells + cell + 1)
total = 0
for d in dist:
    total += d
print(dist[cells - 1], total)
