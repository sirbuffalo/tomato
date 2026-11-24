// Benchmark: big integers. Computes n! by multiplying one small number at a time. Prints n! mod 1000000007.
// The C library has no big integers, so this multiplies an array of 64-bit words by hand (no library to install).
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv) {
    (void)argc;
    uint64_t n = strtoull(argv[1], NULL, 10);
    size_t capacity = 16, words = 1;
    uint64_t *product = malloc(capacity * sizeof *product);
    product[0] = 1;
    for (uint64_t i = 2; i <= n; i++) {
        unsigned __int128 carry = 0;
        for (size_t k = 0; k < words; k++) {
            carry += (unsigned __int128)product[k] * i;
            product[k] = (uint64_t)carry;
            carry >>= 64;
        }
        if (carry) {
            if (words == capacity) product = realloc(product, (capacity *= 2) * sizeof *product);
            product[words++] = (uint64_t)carry;
        }
    }
    unsigned __int128 rest = 0;
    for (size_t k = words; k-- > 0; ) rest = ((rest << 64) | product[k]) % 1000000007u;
    printf("%llu\n", (unsigned long long)rest);
    free(product);
}
