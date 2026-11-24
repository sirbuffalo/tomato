// Benchmark: reverse complement of DNA text. Makes a pseudo-random sequence of n letters (A, C, G, T) with a linear
// congruential generator, writes it as FASTA lines of 60 letters, reads the lines back, joins them, builds the reverse
// complement, and wraps it again. Prints the number of lines and a checksum over every 7th letter of the result.
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const char *letters = "ACGT";

static char complement(char c) {
    switch (c) {
        case 'A': return 'T';
        case 'C': return 'G';
        case 'G': return 'C';
        default: return 'A';
    }
}

// wraps text into lines of 60 letters, each ending in a newline; returns the buffer and sets *lines
static char *wrap(const char *text, size_t length, int64_t *lines) {
    char *out = malloc(length + length / 60 + 2);
    size_t at = 0;
    *lines = 0;
    for (size_t start = 0; start < length; start += 60) {
        size_t len = length - start < 60 ? length - start : 60;
        memcpy(out + at, text + start, len);
        at += len;
        out[at++] = '\n';
        (*lines)++;
    }
    out[at] = 0;
    return out;
}

int main(int argc, char **argv) {
    (void)argc;
    int64_t n = atoll(argv[1]), seed = 2718;
    char *dna = malloc((size_t)n + 1);
    for (int64_t i = 0; i < n; i++) {
        seed = (seed * 1103515245 + 12345) % 2147483648;
        dna[i] = letters[seed / 65536 % 4];
    }
    int64_t line_count;
    char *fasta = wrap(dna, (size_t)n, &line_count);
    // read the lines back and join them
    char *text = malloc((size_t)n + 1);
    size_t length = 0;
    for (char *p = fasta; *p;) {
        char *end = strchr(p, '\n');
        memcpy(text + length, p, (size_t)(end - p));
        length += (size_t)(end - p);
        p = end + 1;
    }
    char *rc = malloc(length + 1);
    for (size_t i = 0; i < length; i++) rc[i] = complement(text[length - 1 - i]);
    char *wrapped = wrap(rc, length, &line_count);
    int64_t checksum = 0;
    for (char *p = wrapped; *p;) {
        char *end = strchr(p, '\n');
        for (char *q = p; q < end; q += 7) checksum = (checksum * 131 + (unsigned char)*q) % 1000000007;
        p = end + 1;
    }
    printf("%lld %lld\n", (long long)line_count, (long long)checksum);
    free(dna);
    free(fasta);
    free(text);
    free(rc);
    free(wrapped);
}
