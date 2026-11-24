// Benchmark: checksums over bytes. Makes n pseudo-random bytes with a linear congruential generator, then computes the
// table-driven CRC-32 (polynomial 0xEDB88320) over them four times (each pass starts from the previous result) and the
// Adler-32 once. Prints both. Bitwise operators and lookups in a 256-entry table.
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv) {
    (void)argc;
    int64_t n = atoll(argv[1]), seed = 1;
    int64_t table[256];
    for (int64_t i = 0; i < 256; i++) {
        int64_t c = i;
        for (int k = 0; k < 8; k++) c = (c & 1) == 1 ? (3988292384 ^ (c >> 1)) : (c >> 1);
        table[i] = c;
    }
    int64_t *data = malloc((size_t)n * sizeof *data);
    for (int64_t i = 0; i < n; i++) {
        seed = (seed * 1103515245 + 12345) % 2147483648;
        data[i] = seed / 65536 % 256;
    }
    int64_t crc = 4294967295;
    for (int rounds = 0; rounds < 4; rounds++)
        for (int64_t i = 0; i < n; i++) crc = table[(crc ^ data[i]) & 255] ^ (crc >> 8);
    crc = crc ^ 4294967295;
    int64_t a = 1, b2 = 0;
    for (int64_t i = 0; i < n; i++) {
        a = (a + data[i]) % 65521;
        b2 = (b2 + a) % 65521;
    }
    printf("%lld %lld\n", (long long)crc, (long long)(b2 * 65536 + a));
    free(data);
}
