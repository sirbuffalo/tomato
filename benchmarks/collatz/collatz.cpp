// Benchmark: longest Collatz chain for a start below n, no caching. Prints the start and the chain length.
#include <cstdint>
#include <iostream>
#include <string>

int main(int, char **argv) {
    std::int64_t n = std::stoll(argv[1]), best_start = 1, best_length = 1;
    for (std::int64_t start = 1; start < n; start++) {
        std::int64_t x = start, length = 1;
        while (x != 1) {
            if (x % 2 == 0) x /= 2;
            else x = 3 * x + 1;
            length++;
        }
        if (length > best_length) {
            best_length = length;
            best_start = start;
        }
    }
    std::cout << best_start << ' ' << best_length << '\n';
}
