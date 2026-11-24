// Benchmark: big integers. Computes n! by multiplying one small number at a time. Prints n! mod 1000000007.
// The C++ library has no big integers, so this multiplies a vector of 64-bit words by hand (no library to install).
#include <cstdint>
#include <iostream>
#include <string>
#include <vector>

int main(int, char **argv) {
    std::uint64_t n = std::stoull(argv[1]);
    std::vector<std::uint64_t> product{1};
    for (std::uint64_t i = 2; i <= n; i++) {
        unsigned __int128 carry = 0;
        for (auto &word : product) {
            carry += static_cast<unsigned __int128>(word) * i;
            word = static_cast<std::uint64_t>(carry);
            carry >>= 64;
        }
        if (carry) product.push_back(static_cast<std::uint64_t>(carry));
    }
    unsigned __int128 rest = 0;
    for (auto word = product.rbegin(); word != product.rend(); ++word) rest = ((rest << 64) | *word) % 1000000007u;
    std::cout << static_cast<std::uint64_t>(rest) << '\n';
}
