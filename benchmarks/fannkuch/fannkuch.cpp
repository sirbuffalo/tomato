// Benchmark: fannkuch-redux. Goes through all permutations of 0..n-1 and flips the prefix of each (as many cards as the
// first card says) until the first card is 0. Prints the alternating-sign checksum of the flip counts and the maximum.
#include <cstdint>
#include <iostream>
#include <numeric>
#include <string>
#include <vector>

int main(int, char **argv) {
    std::int64_t n = std::stoll(argv[1]);
    std::vector<std::int64_t> perm1(n), perm(n, 0), count(n, 0);
    std::iota(perm1.begin(), perm1.end(), 0);
    std::int64_t max_flips = 0, checksum = 0, perm_count = 0, r = n;
    bool done = false;
    while (!done) {
        while (r != 1) {
            count[r - 1] = r;
            r--;
        }
        for (std::int64_t i = 0; i < n; i++) perm[i] = perm1[i];
        std::int64_t flips = 0, k = perm[0];
        while (k != 0) {
            std::int64_t i = 0, j = k;
            while (i < j) {
                std::swap(perm[i], perm[j]);
                i++;
                j--;
            }
            flips++;
            k = perm[0];
        }
        if (flips > max_flips) max_flips = flips;
        if (perm_count % 2 == 0) checksum += flips;
        else checksum -= flips;
        while (true) {
            if (r == n) {
                done = true;
                break;
            }
            std::int64_t p0 = perm1[0];
            for (std::int64_t i = 0; i < r; i++) perm1[i] = perm1[i + 1];
            perm1[r] = p0;
            count[r]--;
            if (count[r] > 0) break;
            r++;
        }
        perm_count++;
    }
    std::cout << checksum << '\n';
    std::cout << "Pfannkuchen(" << n << ") = " << max_flips << '\n';
}
