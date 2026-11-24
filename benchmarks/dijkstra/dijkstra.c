// Benchmark: Dijkstra's shortest paths on an n x n grid of pseudo-random step costs (1..9), from the top-left corner, with a
// hand-written binary min-heap of encoded (distance, cell) numbers. Prints the distance to the far corner and the sum
// of all distances.
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

static int64_t *heap;
static int64_t heap_capacity = 16;

static int64_t push(int64_t size, int64_t key) {
    if (size == heap_capacity) {
        heap_capacity *= 2;
        heap = realloc(heap, (size_t)heap_capacity * sizeof *heap);
    }
    int64_t i = size;
    while (i > 0) {
        int64_t parent = (i - 1) / 2;
        if (heap[parent] <= key) break;
        heap[i] = heap[parent];
        i = parent;
    }
    heap[i] = key;
    return size + 1;
}

// removes the smallest key (the caller has read heap[0]) and returns the new size
static int64_t pop(int64_t size) {
    size--;
    int64_t key = heap[size], i = 0;
    while (1) {
        int64_t child = 2 * i + 1;
        if (child >= size) break;
        if (child + 1 < size && heap[child + 1] < heap[child]) child++;
        if (heap[child] >= key) break;
        heap[i] = heap[child];
        i = child;
    }
    heap[i] = key;
    return size;
}

int main(int argc, char **argv) {
    (void)argc;
    int64_t n = atoll(argv[1]), seed = 2024, cells = n * n, infinity = 1000000000;
    int64_t *cost = malloc((size_t)cells * sizeof *cost), *dist = malloc((size_t)cells * sizeof *dist);
    for (int64_t i = 0; i < cells; i++) {
        seed = (seed * 1103515245 + 12345) % 2147483648;
        cost[i] = seed / 65536 % 9 + 1;
        dist[i] = infinity;
    }
    heap = malloc((size_t)heap_capacity * sizeof *heap);
    int64_t size = 0;
    dist[0] = 0;
    size = push(size, 0);
    while (size > 0) {
        int64_t top = heap[0];
        size = pop(size);
        int64_t d = top / cells, cell = top % cells;
        if (d > dist[cell]) continue;
        int64_t y = cell / n, x = cell % n;
        if (y > 0 && d + cost[cell - n] < dist[cell - n]) {
            dist[cell - n] = d + cost[cell - n];
            size = push(size, dist[cell - n] * cells + cell - n);
        }
        if (y < n - 1 && d + cost[cell + n] < dist[cell + n]) {
            dist[cell + n] = d + cost[cell + n];
            size = push(size, dist[cell + n] * cells + cell + n);
        }
        if (x > 0 && d + cost[cell - 1] < dist[cell - 1]) {
            dist[cell - 1] = d + cost[cell - 1];
            size = push(size, dist[cell - 1] * cells + cell - 1);
        }
        if (x < n - 1 && d + cost[cell + 1] < dist[cell + 1]) {
            dist[cell + 1] = d + cost[cell + 1];
            size = push(size, dist[cell + 1] * cells + cell + 1);
        }
    }
    int64_t total = 0;
    for (int64_t i = 0; i < cells; i++) total += dist[i];
    printf("%lld %lld\n", (long long)dist[cells - 1], (long long)total);
    free(cost);
    free(dist);
    free(heap);
}
