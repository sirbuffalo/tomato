// Benchmark: sort n pseudo-random integers (a linear congruential generator). Prints a position-weighted checksum.
#include <algorithm>
#include <cstdint>
#include <iostream>
#include <string>
#include <vector>

int main(int, char **argv) {
    std::int64_t n = std::stoll(argv[1]), seed = 12345;
    std::vector<std::int64_t> values(n);
    for (std::int64_t i = 0; i < n; i++) {
        seed = (seed * 1103515245 + 12345) % 2147483648;
        values[i] = seed;
    }
    std::sort(values.begin(), values.end());
    std::int64_t checksum = 0;
    for (std::int64_t i = 0; i < n; i++) checksum = (checksum + (i % 1000 + 1) * values[i]) % 1000000007;
    std::cout << checksum << '\n';
}
