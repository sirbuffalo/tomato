// Benchmark: k-nucleotide counting. Makes a pseudo-random DNA string of n letters (A, C, G, T) with a linear congruential
// generator, then counts every substring of length 1, 2, 4, 6 and 12 in an unordered_map. For each length prints the number
// of different substrings, the highest count and the sum of the squares of the counts.
#include <cstdint>
#include <iostream>
#include <string>
#include <unordered_map>

int main(int, char **argv) {
    std::int64_t n = std::stoll(argv[1]), seed = 31337;
    const char letters[] = "ACGT";
    std::string dna;
    for (std::int64_t i = 0; i < n; i++) {
        seed = (seed * 1103515245 + 12345) % 2147483648;
        dna.push_back(letters[seed / 65536 % 4]);
    }
    for (std::int64_t k : {1, 2, 4, 6, 12}) {
        std::unordered_map<std::string, std::int64_t> counts;
        for (std::int64_t i = 0; i < n - k + 1; i++) counts[dna.substr(i, k)]++;
        std::int64_t most = 0, squares = 0;
        for (const auto &entry : counts) {
            std::int64_t c = entry.second;
            if (c > most) most = c;
            squares += c * c;
        }
        std::cout << k << ' ' << counts.size() << ' ' << most << ' ' << squares << '\n';
    }
}
