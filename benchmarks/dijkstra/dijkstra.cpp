// Benchmark: Dijkstra's shortest paths on an n x n grid of pseudo-random step costs (1..9), from the top-left corner, with a
// binary min-heap (std::priority_queue) of encoded (distance, cell) numbers. Prints the distance to the far corner and the
// sum of all distances.
#include <cstdint>
#include <functional>
#include <iostream>
#include <queue>
#include <string>
#include <vector>

int main(int, char **argv) {
    std::int64_t n = std::stoll(argv[1]), seed = 2024, cells = n * n, infinity = 1000000000;
    std::vector<std::int64_t> cost(cells), dist(cells, infinity);
    for (std::int64_t i = 0; i < cells; i++) {
        seed = (seed * 1103515245 + 12345) % 2147483648;
        cost[i] = seed / 65536 % 9 + 1;
    }
    std::priority_queue<std::int64_t, std::vector<std::int64_t>, std::greater<std::int64_t>> heap;
    dist[0] = 0;
    heap.push(0);
    auto relax = [&](std::int64_t d, std::int64_t next) {
        if (d + cost[next] < dist[next]) {
            dist[next] = d + cost[next];
            heap.push(dist[next] * cells + next);
        }
    };
    while (!heap.empty()) {
        std::int64_t top = heap.top();
        heap.pop();
        std::int64_t d = top / cells, cell = top % cells;
        if (d > dist[cell]) continue;
        std::int64_t y = cell / n, x = cell % n;
        if (y > 0) relax(d, cell - n);
        if (y < n - 1) relax(d, cell + n);
        if (x > 0) relax(d, cell - 1);
        if (x < n - 1) relax(d, cell + 1);
    }
    std::int64_t total = 0;
    for (std::int64_t d : dist) total += d;
    std::cout << dist[cells - 1] << ' ' << total << '\n';
}
