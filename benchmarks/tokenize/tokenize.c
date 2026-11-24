// Benchmark: a hand-written tokenizer (no regular expressions). Makes n pseudo-random tokens of source-like text (names,
// whole numbers and punctuation), joins them, then scans the text one character at a time and classifies the tokens.
// Prints the number of names, numbers and symbols, the sum of the numbers and the total length of the names.
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct { char *data; size_t length, capacity; } Text;

static void append(Text *t, const char *s) {
    size_t len = strlen(s);
    if (t->length + len + 1 > t->capacity) {
        while (t->length + len + 1 > t->capacity) t->capacity = t->capacity ? t->capacity * 2 : 64;
        t->data = realloc(t->data, t->capacity);
    }
    memcpy(t->data + t->length, s, len + 1);
    t->length += len;
}

static int is_alpha(char c) { return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z'); }
static int is_digit(char c) { return c >= '0' && c <= '9'; }

int main(int argc, char **argv) {
    (void)argc;
    int64_t n = atoll(argv[1]), seed = 555;
    const char *words[] = {"alpha", "beta", "gamma", "delta", "count", "total", "index", "value"};
    const char *symbols[] = {"+", "-", "*", "/", "=", "(", ")", ";"};
    Text text = {0};
    char piece[64];
    for (int64_t i = 0; i < n; i++) {
        seed = (seed * 1103515245 + 12345) % 2147483648;
        int64_t kind = seed / 65536 % 4;
        seed = (seed * 1103515245 + 12345) % 2147483648;
        int64_t pick = seed / 65536;
        if (kind == 0) snprintf(piece, sizeof piece, "%s ", words[pick % 8]);
        else if (kind == 1) snprintf(piece, sizeof piece, "%lld ", (long long)(pick % 100000));
        else if (kind == 2) snprintf(piece, sizeof piece, "%s", symbols[pick % 8]);
        else snprintf(piece, sizeof piece, "%s%lld ", words[pick % 8], (long long)(pick / 8 % 100));
        append(&text, piece);
    }
    int64_t names = 0, numbers = 0, syms = 0, number_sum = 0, name_length = 0, value = 0;
    int in_name = 0, in_number = 0;
    for (size_t i = 0; i < text.length; i++) {
        char ch = text.data[i];
        if (is_alpha(ch) || (in_name && is_digit(ch))) {
            if (!in_name) {
                in_name = 1;
                names++;
            }
            name_length++;
        } else if (is_digit(ch)) {
            if (!in_number) {
                in_number = 1;
                numbers++;
                value = 0;
            }
            value = value * 10 + ch - 48;
        } else {
            if (in_number) number_sum += value;
            in_name = in_number = 0;
            if (ch != ' ') syms++;
        }
    }
    if (in_number) number_sum += value;
    printf("%lld %lld %lld %lld %lld\n", (long long)names, (long long)numbers, (long long)syms, (long long)number_sum, (long long)name_length);
    free(text.data);
}
