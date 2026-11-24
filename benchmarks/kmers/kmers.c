// Benchmark: k-nucleotide counting. Makes a pseudo-random DNA string of n letters (A, C, G, T) with a linear congruential
// generator, then counts every substring of length 1, 2, 4, 6 and 12 in a hash table. For each length prints the number of
// different substrings, the highest count and the sum of the squares of the counts.
// The C library has no growing hash table, so this has a small one of its own (FNV-1a, linear probing, doubling); its keys
// are offsets into the DNA string, so no substring is copied.
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct { int64_t start; uint64_t hash; int64_t count; } Entry;   // start < 0 marks an empty slot
static Entry *table;
static size_t capacity, used;
static const char *dna;
static int64_t k;

static uint64_t hash_of(const char *s) {
    uint64_t h = 1469598103934665603u;
    for (int64_t i = 0; i < k; i++) h = (h ^ (unsigned char)s[i]) * 1099511628211u;
    return h;
}

static Entry *place(const char *s, uint64_t hash) {
    size_t i = hash & (capacity - 1);
    while (table[i].start >= 0 && (table[i].hash != hash || memcmp(dna + table[i].start, s, (size_t)k) != 0)) i = (i + 1) & (capacity - 1);
    return &table[i];
}

static void grow(void) {
    Entry *old = table;
    size_t old_capacity = capacity;
    capacity = capacity ? capacity * 2 : 16;
    table = malloc(capacity * sizeof *table);
    for (size_t i = 0; i < capacity; i++) table[i].start = -1;
    for (size_t i = 0; i < old_capacity; i++)
        if (old[i].start >= 0) *place(dna + old[i].start, old[i].hash) = old[i];
    free(old);
}

int main(int argc, char **argv) {
    (void)argc;
    int64_t n = atoll(argv[1]), seed = 31337;
    const char letters[] = "ACGT";
    char *text = malloc((size_t)n + 1);
    for (int64_t i = 0; i < n; i++) {
        seed = (seed * 1103515245 + 12345) % 2147483648;
        text[i] = letters[seed / 65536 % 4];
    }
    text[n] = 0;
    dna = text;
    int64_t lengths[] = {1, 2, 4, 6, 12};
    for (int w = 0; w < 5; w++) {
        k = lengths[w];
        free(table);
        table = NULL;
        capacity = used = 0;
        for (int64_t i = 0; i < n - k + 1; i++) {
            if (used * 4 >= capacity * 3) grow();
            uint64_t hash = hash_of(dna + i);
            Entry *e = place(dna + i, hash);
            if (e->start < 0) {
                e->start = i;
                e->hash = hash;
                e->count = 0;
                used++;
            }
            e->count++;
        }
        int64_t most = 0, squares = 0;
        for (size_t i = 0; i < capacity; i++)
            if (table[i].start >= 0) {
                int64_t c = table[i].count;
                if (c > most) most = c;
                squares += c * c;
            }
        printf("%lld %zu %lld %lld\n", (long long)k, used, (long long)most, (long long)squares);
    }
    free(table);
    free(text);
}
