// Benchmark: word counting in a hash table. Counts n generated words ("w0".."w5002"), then prints a weighted checksum.
// The C library has no growing hash table, so this has a small one of its own (FNV-1a, linear probing, doubling).
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct { char *word; uint64_t hash; int64_t count; } Entry;
static Entry *table;
static size_t capacity, used;

static uint64_t hash_of(const char *word) {
    uint64_t h = 1469598103934665603u;
    for (; *word; word++) h = (h ^ (unsigned char)*word) * 1099511628211u;
    return h;
}

static Entry *place(const char *word, uint64_t hash) {
    size_t i = hash & (capacity - 1);
    while (table[i].word && (table[i].hash != hash || strcmp(table[i].word, word) != 0)) i = (i + 1) & (capacity - 1);
    return &table[i];
}

static void grow(void) {
    Entry *old = table;
    size_t old_capacity = capacity;
    capacity = capacity ? capacity * 2 : 16;
    table = calloc(capacity, sizeof *table);
    for (size_t i = 0; i < old_capacity; i++)
        if (old[i].word) *place(old[i].word, old[i].hash) = old[i];
    free(old);
}

static int64_t *count_of(const char *word) {
    if (used * 4 >= capacity * 3) grow();
    uint64_t hash = hash_of(word);
    Entry *e = place(word, hash);
    if (!e->word) {
        size_t length = strlen(word) + 1;
        e->word = malloc(length);
        memcpy(e->word, word, length);
        e->hash = hash;
        used++;
    }
    return &e->count;
}

int main(int argc, char **argv) {
    (void)argc;
    int64_t n = atoll(argv[1]);
    char word[32];
    for (int64_t i = 0; i < n; i++) {
        snprintf(word, sizeof word, "w%lld", (long long)(i * 7919 % 5003));
        ++*count_of(word);
    }
    int64_t checksum = 0;
    size_t words = used;
    for (int64_t k = 0; k < 5003; k++) {
        snprintf(word, sizeof word, "w%lld", (long long)k);
        Entry *e = capacity ? place(word, hash_of(word)) : NULL;
        if (e && e->word) checksum += (k + 1) * e->count;
    }
    printf("%zu %lld\n", words, (long long)checksum);
    for (size_t i = 0; i < capacity; i++) free(table[i].word);
    free(table);
}
