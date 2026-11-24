// Benchmark: word counting in an unordered_map. Counts n generated words ("w0".."w5002"), then prints a weighted checksum.
#include <cstdint>
#include <iostream>
#include <string>
#include <unordered_map>

int main(int, char **argv) {
    std::int64_t n = std::stoll(argv[1]);
    std::unordered_map<std::string, std::int64_t> counts;
    for (std::int64_t i = 0; i < n; i++) counts["w" + std::to_string(i * 7919 % 5003)]++;
    std::int64_t checksum = 0;
    for (std::int64_t k = 0; k < 5003; k++) {
        auto found = counts.find("w" + std::to_string(k));
        if (found != counts.end()) checksum += (k + 1) * found->second;
    }
    std::cout << counts.size() << ' ' << checksum << '\n';
}
