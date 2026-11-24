// Benchmark: function values. Calls one of four functions chosen from a vector n times (each result feeds the next), then
// runs map and filter with lambdas and sorts with a key function over a vector of n / 4 numbers. Prints three checksums.
#include <algorithm>
#include <cstdint>
#include <functional>
#include <iostream>
#include <string>
#include <utility>
#include <vector>

using Fn = std::function<std::int64_t(std::int64_t)>;

static std::int64_t f0(std::int64_t x) { return (x * 3 + 1) % 1000003; }
static std::int64_t f1(std::int64_t x) { return (x + 7919) % 1000003; }
static std::int64_t f2(std::int64_t x) { return x * x % 1000003; }
static std::int64_t f3(std::int64_t x) { return (x ^ 12345) % 1000003; }

static std::int64_t apply_twice(const Fn &f, std::int64_t x) { return f(f(x)); }

int main(int, char **argv) {
    std::int64_t n = std::stoll(argv[1]);
    std::vector<Fn> table = {f0, f1, f2, f3};
    std::int64_t x = 1;
    for (std::int64_t i = 0; i < n; i++) x = table[i % 4](x + i);
    std::cout << x << '\n';
    std::int64_t y = 0;
    for (std::int64_t i = 0; i < n; i++) y = (y + apply_twice(table[i % 4], i)) % 1000000007;
    std::cout << y << '\n';
    std::int64_t m = n / 4;
    Fn square_mod = [](std::int64_t v) { return v * v % 1009; };
    Fn sort_key = [](std::int64_t v) { return v % 997 * 1000 + v % 1000; };
    std::vector<std::pair<std::int64_t, std::int64_t>> odd;   // (key, value)
    for (std::int64_t i = 0; i < m; i++) {
        std::int64_t v = square_mod(i * 7919 % 100003);
        if (v % 2 == 1) odd.emplace_back(sort_key(v), v);
    }
    std::stable_sort(odd.begin(), odd.end(), [](const auto &a, const auto &b) { return a.first < b.first; });
    std::int64_t z = 0;
    for (const auto &item : odd) z = (z * 31 + item.second) % 1000000007;
    std::cout << odd.size() << ' ' << z << '\n';
}
