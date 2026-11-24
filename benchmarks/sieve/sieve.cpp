// Benchmark: sieve of Eratosthenes. Prints how many primes are <= n.
// A vector of bytes: std::vector<bool> packs its flags into bits, which the other versions do not.
#include <cstdint>
#include <iostream>
#include <string>
#include <vector>

int main(int, char **argv) {
    std::int64_t n = std::stoll(argv[1]), count = 0;
    std::vector<std::uint8_t> composite(n + 1);
    for (std::int64_t i = 2; i <= n; i++) {
        if (composite[i]) continue;
        count++;
        for (std::int64_t j = i * i; j <= n; j += i) composite[j] = 1;
    }
    std::cout << count << '\n';
}
