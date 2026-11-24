// Benchmark: text building and parsing. Joins n numbers into one comma-separated string, splits it and adds them up.
// Prints the text length and the sum. Each number's text is its own allocation, like the strings of the other versions;
// the pieces are read in place (C has no split that copies).
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char **argv) {
    (void)argc;
    int64_t n = atoll(argv[1]);
    char **parts = malloc((size_t)n * sizeof *parts);
    size_t total_bytes = 1;
    for (int64_t i = 0; i < n; i++) {
        char buffer[24];
        int length = snprintf(buffer, sizeof buffer, "%lld", (long long)(i * 7 % 1000));
        parts[i] = malloc((size_t)length + 1);
        memcpy(parts[i], buffer, (size_t)length + 1);
        total_bytes += (size_t)length + 1;
    }
    char *text = malloc(total_bytes), *end = text;
    for (int64_t i = 0; i < n; i++) {
        if (i > 0) *end++ = ',';
        size_t length = strlen(parts[i]);
        memcpy(end, parts[i], length);
        end += length;
    }
    *end = '\0';
    int64_t total = 0;
    for (char *piece = text; ; ) {
        char *after;
        total += strtoll(piece, &after, 10);
        if (*after != ',') break;
        piece = after + 1;
    }
    printf("%lld %lld\n", (long long)(end - text), (long long)total);
    for (int64_t i = 0; i < n; i++) free(parts[i]);
    free(parts);
    free(text);
}
