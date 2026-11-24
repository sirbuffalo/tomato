// Benchmark: edit distance (Levenshtein) by dynamic programming. Makes two pseudo-random strings of n letters (a..d) with a
// linear congruential generator and fills the table row by row (two rows kept). Prints the distance.
#include <cstdint>
#include <iostream>
#include <numeric>
#include <string>
#include <vector>

int main(int, char **argv) {
    std::int64_t n = std::stoll(argv[1]), seed = 42;
    const char letters[] = "abcd";
    std::string s, t;
    for (std::int64_t i = 0; i < n; i++) {
        seed = (seed * 1103515245 + 12345) % 2147483648;
        s.push_back(letters[seed / 65536 % 4]);
        seed = (seed * 1103515245 + 12345) % 2147483648;
        t.push_back(letters[seed / 65536 % 4]);
    }
    std::vector<std::int64_t> prev(n + 1), cur(n + 1, 0);
    std::iota(prev.begin(), prev.end(), 0);
    for (std::int64_t i = 1; i <= n; i++) {
        cur[0] = i;
        char si = s[i - 1];
        for (std::int64_t j = 1; j <= n; j++) {
            std::int64_t cost = si == t[j - 1] ? 0 : 1;
            std::int64_t best = prev[j - 1] + cost;
            std::int64_t up = prev[j] + 1;
            if (up < best) best = up;
            std::int64_t left = cur[j - 1] + 1;
            if (left < best) best = left;
            cur[j] = best;
        }
        std::swap(prev, cur);
    }
    std::cout << prev[n] << '\n';
}
