/* Compare the divide-and-conquer decimal conversion (str) with the plain 9-digits-a-pass loop over the whole number, and decimal
 * parsing by the round trip (with leading zeros too), on random, all-one, power-of-two and zero-half numbers of every size across
 * the first levels, numbers next to the powers of ten it splits by, and a few long ones whose products go through Karatsuba and
 * the transform. tests/run.sh also builds it with tiny cutoffs, so that small numbers go many levels deep. */
#include "../runtime/tomato_rt.c"
const int32_t tomato_kinds[8];
const int32_t *const tomato_offsets[8];
int64_t tomato_parents[8];
const char *tomato_class_names[8];
int32_t tomato_exc_seen;
void tomato_call_drop(void *o) { (void)o; }

static uint64_t seed = 1;
static uint32_t rnd(void) {
    seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17;
    return (uint32_t)seed;
}
static void fill(uint32_t *a, int64_t n, int kind) {
    for (int64_t i = 0; i < n; i++) a[i] = kind == 1 ? UINT32_MAX : kind == 2 ? 0 : rnd();
    if (kind == 2) a[n - 1] = (uint32_t)1 << (rnd() % 32);          /* a power of two */
    if (kind == 3) for (int64_t i = 0; i < n / 2; i++) a[i] = 0;      /* a zero low half */
    if (kind == 4) for (int64_t i = n / 2; i < n; i++) a[i] = 0;      /* leading zero limbs inside the operand */
}
/* str(x) against the plain loop over the whole number, and int(str(x)) == x */
static void check_dec(const uint32_t *a, int64_t n, int sign) {
    int64_t x = int_make(sign, a, n);
    IntView v; int_view(x, &v);
    char *want = malloc((size_t)v.n * 10 + 3);
    int64_t w = v.n * 10;
    dec_base(v.d, v.n, want + 1, w);
    int64_t pos = 1;
    while (pos < w && want[pos] == '0') pos++;
    if (v.n && v.sign < 0) want[--pos] = '-';
    Str *got = tomato_int_str(x);
    if (got->bytes != w + 1 - pos || memcmp(got->data, want + pos, (size_t)got->bytes)) {
        fprintf(stderr, "str mismatch: n=%lld seed=%llu\n", (long long)n, (unsigned long long)seed); exit(1);
    }
    int ok;
    int64_t back = int_from_digits(got->data, got->bytes, &ok);
    if (!ok || tomato_int_cmp(back, x) != 0) { fprintf(stderr, "parse mismatch: n=%lld seed=%llu\n", (long long)n, (unsigned long long)seed); exit(1); }
    /* the same digits with leading zeros parse to the same number */
    char *z = malloc((size_t)got->bytes + 40);
    int64_t zl = 0, neg = got->data[0] == '-';
    if (neg) z[zl++] = '-';
    for (int k = 0; k < 37; k++) z[zl++] = '0';
    memcpy(z + zl, got->data + neg, (size_t)(got->bytes - neg)); zl += got->bytes - neg;
    int64_t back2 = int_from_digits(z, zl, &ok);
    if (!ok || tomato_int_cmp(back2, x) != 0) { fprintf(stderr, "parse mismatch (leading zeros): n=%lld seed=%llu\n", (long long)n, (unsigned long long)seed); exit(1); }
    tomato_int_free(back); tomato_int_free(back2); tomato_int_free(x);
    tomato_release(got);
    free(want); free(z);
}
/* x = 10^e + d, d in -1 .. 1: the edges of the powers the conversion splits by */
static void check_pow10(int64_t e, int d) {
    int64_t x = int_mk_small(1);
    for (int64_t i = 0; i < e; i++) dec_set(&x, tomato_int_mul(x, int_mk_small(10)));
    dec_set(&x, tomato_int_add(x, int_mk_small(d)));
    IntView v; int_view(x, &v);
    check_dec(v.d, v.n, 1);
    tomato_int_free(x);
}

int main(int argc, char **argv) {
    int rounds = argc > 1 ? atoi(argv[1]) : 300;
    int64_t max = 600;
    uint32_t *a = malloc((size_t)max * 4);
    for (int64_t n = 1; n <= 4 * DEC_BASE_LIMBS + 40; n++) {      /* str and parse: every size across the first levels */
        fill(a, n, n % 5); check_dec(a, n, n % 3 ? 1 : -1);
    }
    for (int k = 0; k < rounds / 10; k++) {
        int64_t n = 1 + rnd() % (max - 1);
        fill(a, n, rnd() % 5); check_dec(a, n, rnd() % 2 ? 1 : -1);
    }
    for (int64_t e = 9; e <= 9 * 256; e *= 2) for (int d = -1; d <= 1; d++) { check_pow10(e, d); check_pow10(2 * e, d); }
    for (int64_t n = 2000; n <= 16000; n += 7000) {                 /* 16000: products through the transform */
        uint32_t *x = malloc((size_t)n * 4);
        fill(x, n, 0); check_dec(x, n, -1);
        fill(x, n, 1); check_dec(x, n, 1);
        fill(x, n, 2); check_dec(x, n, 1);
        free(x);
    }
    free(a);
    puts("ok");
}
