// Benchmark: checksums over bytes. Makes n pseudo-random bytes with a linear congruential generator, then computes the
// table-driven CRC-32 (polynomial 0xEDB88320) over them four times (each pass starts from the previous result) and the
// Adler-32 once. Prints both. Bitwise operators and lookups in a 256-entry table.
#include <array>
#include <cstdint>
#include <iostream>
#include <string>
#include <vector>

int main(int, char **argv) {
    std::int64_t n = std::stoll(argv[1]), seed = 1;
    std::array<std::int64_t, 256> table{};
    for (std::int64_t i = 0; i < 256; i++) {
        std::int64_t c = i;
        for (int k = 0; k < 8; k++) c = (c & 1) == 1 ? (3988292384 ^ (c >> 1)) : (c >> 1);
        table[i] = c;
    }
    std::vector<std::int64_t> data(n);
    for (std::int64_t i = 0; i < n; i++) {
        seed = (seed * 1103515245 + 12345) % 2147483648;
        data[i] = seed / 65536 % 256;
    }
    std::int64_t crc = 4294967295;
    for (int rounds = 0; rounds < 4; rounds++)
        for (std::int64_t b : data) crc = table[(crc ^ b) & 255] ^ (crc >> 8);
    crc = crc ^ 4294967295;
    std::int64_t a = 1, b2 = 0;
    for (std::int64_t b : data) {
        a = (a + b) % 65521;
        b2 = (b2 + a) % 65521;
    }
    std::cout << crc << ' ' << b2 * 65536 + a << '\n';
}
