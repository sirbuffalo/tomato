/* Generates the case tables inside runtime/tomato_rt.c (tomato_case_upper / tomato_case_lower) from the C library's Unicode
 * simple case mapping: clang -o gen tools/gen_case_table.c && ./gen > table.txt, then paste the two arrays into the runtime.
 * Each row is {first, last, delta, step}: code points first, first+step, ... up to last map to code point + delta. */
#include <locale.h>
#include <stdio.h>
#include <wctype.h>

/* The macOS C library lacks the lowercase of four titlecase letters and is wrong for U+038D to U+038F; these follow UnicodeData.txt. */
static wint_t lower_fixed(wint_t c) {
    switch (c) {
    case 0x1C5: return 0x1C6;
    case 0x1C8: return 0x1C9;
    case 0x1CB: return 0x1CC;
    case 0x1F2: return 0x1F3;
    case 0x38D: return c;
    case 0x38E: return 0x3CD;
    case 0x38F: return 0x3CE;
    }
    return towlower(c);
}

static void emit(const char *name, wint_t (*f)(wint_t)) {
    printf("static const int32_t %s[][4] = {\n", name);
    int n = 0;
    for (int cp = 0x80; cp < 0x20000;) {
        int d = (int)f((wint_t)cp) - cp;
        if (d == 0) { cp++; continue; }
        int step = 1, last = cp;
        if ((int)f((wint_t)(cp + 1)) - (cp + 1) != d && (int)f((wint_t)(cp + 2)) - (cp + 2) == d) step = 2;
        while ((int)f((wint_t)(last + step)) - (last + step) == d) last += step;
        printf("    {0x%X, 0x%X, %d, %d},\n", cp, last, d, step);
        n++;
        cp = last + 1;
    }
    printf("};\n");
}

int main(void) {
    if (!setlocale(LC_CTYPE, "en_US.UTF-8")) { fprintf(stderr, "no UTF-8 locale\n"); return 1; }
    emit("case_upper_rows", towupper);
    emit("case_lower_rows", lower_fixed);
    return 0;
}
