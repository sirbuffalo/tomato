/* Generates the letter and digit tables inside runtime/tomato_rt.c (ctype_alpha_rows / ctype_digit_rows) from the Unicode
 * Character Database, version 16.0.0 (the one Python 3.14 uses, so isalpha and isdigit agree with it):
 *   curl -O https://www.unicode.org/Public/16.0.0/ucd/UnicodeData.txt
 *   clang -o gen tools/gen_ctype_table.c && ./gen UnicodeData.txt > table.txt, then paste the two arrays into the runtime.
 * A letter (isalpha) has the general category Lu, Ll, Lt, Lm or Lo; a digit (isdigit) has a digit value (field 7: Numeric_Type
 * Digit or Decimal, so U+00B2 SUPERSCRIPT TWO counts but U+00BD ONE HALF does not), as in Python. Each row is {first, last}, an
 * inclusive range of code points; ASCII is left out because the runtime checks it first. The C library is not used: glibc counts
 * other scripts' digits as letters, and the macOS tables are older. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_CP 0x110000
static unsigned char alpha[MAX_CP], digit[MAX_CP];

static void emit(const char *name, const unsigned char *set) {
    printf("static const int32_t %s[][2] = {\n", name);
    for (int cp = 0x80; cp < MAX_CP;) {
        if (!set[cp]) { cp++; continue; }
        int last = cp;
        while (last + 1 < MAX_CP && set[last + 1]) last++;
        printf("    {0x%X, 0x%X},\n", cp, last);
        cp = last + 1;
    }
    printf("};\n");
}

int main(int argc, char **argv) {
    if (argc != 2) { fprintf(stderr, "usage: gen UnicodeData.txt\n"); return 1; }
    FILE *f = fopen(argv[1], "r");
    if (!f) { perror(argv[1]); return 1; }
    char line[1024];
    long first = -1;                       /* the start of a <..., First> ... <..., Last> range */
    while (fgets(line, sizeof line, f)) {
        char *field[15] = {0};
        int n = 0;
        for (char *p = line; n < 15; n++) {
            field[n] = p;
            char *semi = strchr(p, ';');
            if (!semi) { n++; break; }
            *semi = 0;
            p = semi + 1;
        }
        if (n < 8) continue;
        long cp = strtol(field[0], NULL, 16);
        const char *cat = field[2];
        int is_alpha = cat[0] == 'L' && cat[1] && strchr("ultmo", cat[1]) != NULL;
        int is_digit = field[7][0] != 0;
        long from = cp;
        if (strstr(field[1], ", First>")) { first = cp; continue; }
        if (strstr(field[1], ", Last>")) from = first;
        for (long c = from; c <= cp; c++) {
            alpha[c] = (unsigned char)is_alpha;
            digit[c] = (unsigned char)is_digit;
        }
    }
    fclose(f);
    emit("ctype_alpha_rows", alpha);
    emit("ctype_digit_rows", digit);
    return 0;
}
