/* Generates the case tables inside runtime/tomato_rt.c (case_upper_rows / case_lower_rows) from the C library's Unicode
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

static int delta(wint_t (*f)(wint_t), int cp) { return (int)f((wint_t)cp) - cp; }

static void emit(const char *name, wint_t (*f)(wint_t)) {
    printf("static const int32_t %s[][4] = {\n", name);
    for (int cp = 0x80; cp < 0x20000;) {
        int d = delta(f, cp);
        if (d == 0) { cp++; continue; }
        /* a row with step 2 (capital and small letters taking turns) leaves the code points in between unchanged, so it
         * may only cover them when they really map to themselves */
        int step = delta(f, cp + 1) == 0 && delta(f, cp + 2) == d ? 2 : 1, last = cp;
        while (delta(f, last + step) == d && (step == 1 || delta(f, last + 1) == 0)) last += step;
        printf("    {0x%X, 0x%X, %d, %d},\n", cp, last, d, step);
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
