// Benchmark: 0/1 knapsack by dynamic programming over one row of capacities. n items with pseudo-random weights (1..60) and
// values (1..1000) from a linear congruential generator, capacity 5 * n. Prints the best total value.
#include <cstdint>
#include <iostream>
#include <string>
#include <vector>

int main(int, char **argv) {
    std::int64_t n = std::stoll(argv[1]), seed = 7;
    std::vector<std::int64_t> weights(n), values(n);
    for (std::int64_t i = 0; i < n; i++) {
        seed = (seed * 1103515245 + 12345) % 2147483648;
        weights[i] = seed / 65536 % 60 + 1;
        seed = (seed * 1103515245 + 12345) % 2147483648;
        values[i] = seed / 65536 % 1000 + 1;
    }
    std::int64_t capacity = 5 * n;
    std::vector<std::int64_t> best(capacity + 1, 0);
    for (std::int64_t i = 0; i < n; i++) {
        std::int64_t w = weights[i], v = values[i];
        for (std::int64_t c = capacity; c >= w; c--) {
            std::int64_t candidate = best[c - w] + v;
            if (candidate > best[c]) best[c] = candidate;
        }
    }
    std::cout << best[capacity] << '\n';
}
