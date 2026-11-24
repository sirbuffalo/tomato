// Benchmark: Dijkstra's shortest paths on an n x n grid of pseudo-random step costs (1..9), from the top-left corner, with a
// hand-written binary min-heap of encoded (distance, cell) numbers. Prints the distance to the far corner and the sum
// of all distances.
class dijkstra {
    static long[] heap = new long[16];

    static int push(int size, long key) {
        if (size == heap.length) heap = java.util.Arrays.copyOf(heap, size * 2);
        int i = size;
        while (i > 0) {
            int parent = (i - 1) / 2;
            if (heap[parent] <= key) break;
            heap[i] = heap[parent];
            i = parent;
        }
        heap[i] = key;
        return size + 1;
    }

    // removes the smallest key (the caller has read heap[0]) and returns the new size
    static int pop(int size) {
        size--;
        long key = heap[size];
        int i = 0;
        while (true) {
            int child = 2 * i + 1;
            if (child >= size) break;
            if (child + 1 < size && heap[child + 1] < heap[child]) child++;
            if (heap[child] >= key) break;
            heap[i] = heap[child];
            i = child;
        }
        heap[i] = key;
        return size;
    }

    public static void main(String[] args) {
        int n = Integer.parseInt(args[0]);
        long seed = 2024;
        int cells = n * n;
        long[] cost = new long[cells];
        for (int i = 0; i < cells; i++) {
            seed = (seed * 1103515245L + 12345) % 2147483648L;
            cost[i] = seed / 65536 % 9 + 1;
        }
        long infinity = 1000000000;
        long[] dist = new long[cells];
        java.util.Arrays.fill(dist, infinity);
        int size = 0;
        dist[0] = 0;
        size = push(size, 0);
        while (size > 0) {
            long top = heap[0];
            size = pop(size);
            long d = top / cells;
            int cell = (int) (top % cells);
            if (d > dist[cell]) continue;
            int y = cell / n;
            int x = cell % n;
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
        long total = 0;
        for (long d : dist) total += d;
        System.out.println(dist[cells - 1] + " " + total);
    }
}
