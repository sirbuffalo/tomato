/* Compare magnitude multiplication (schoolbook, Karatsuba, squaring, uneven lengths) with a plain 32-bit schoolbook product, and
 * the number-theoretic transform product (ntt_mul, and mag_mul above NTT_MIN) with Karatsuba. */
#include "../runtime/tomato_rt.c"
const int32_t tomato_kinds[8];
const int32_t *const tomato_offsets[8];
int64_t tomato_parents[8];
const char *tomato_class_names[8];
int32_t tomato_exc_seen;
void tomato_call_drop(void *o) { (void)o; }

#define N 700
static uint64_t seed = 1;
static uint32_t rnd(void) {
    seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17;
    return (uint32_t)seed;
}
static void reference(const uint32_t *a, int an, const uint32_t *b, int bn, uint32_t *out) {
    memset(out, 0, (size_t)(an + bn) * 4);
    for (int i = 0; i < an; i++) {
        uint64_t carry = 0;
        for (int j = 0; j < bn; j++) {
            uint64_t t = (uint64_t)a[i] * b[j] + out[i + j] + carry;
            out[i + j] = (uint32_t)t; carry = t >> 32;
        }
        out[i + bn] = (uint32_t)carry;
    }
}
static void check(const uint32_t *a, int an, const uint32_t *b, int bn) {
    static uint32_t got[2 * N], want[2 * N];
    /* the operands and the result in their own allocations, so AddressSanitizer sees any access past them */
    uint32_t *x = malloc((size_t)an * 4), *y = a == b ? x : malloc((size_t)bn * 4), *r = calloc((size_t)(an + bn), 4);
    memcpy(x, a, (size_t)an * 4); if (y != x) memcpy(y, b, (size_t)bn * 4);
    mag_mul(x, an, y, bn, r);
    memcpy(got, r, (size_t)(an + bn) * 4);
    reference(a, an, b, bn, want);
    if (memcmp(got, want, (size_t)(an + bn) * 4)) {
        fprintf(stderr, "multiplication mismatch: an=%d bn=%d square=%d seed=%llu\n", an, bn, a == b, (unsigned long long)seed); exit(1);
    }
    free(r); if (y != x) free(y); free(x);
}
static void fill(uint32_t *d, int n, int k) {
    for (int i = 0; i < n; i++) d[i] = rnd();
    if (k % 5 == 0) for (int i = 0; i < n; i++) d[i] = UINT32_MAX;            /* every carry and borrow propagates */
    if (k % 7 == 0) for (int i = 0; i < n / 2; i++) d[i] = 0;                 /* a zero low half */
    if (k % 9 == 0) for (int i = n / 2; i < n - 1; i++) d[i] = 0;             /* a near-zero high half */
    d[n - 1] |= 1;
}
/* Karatsuba on both numbers zero-extended to the longer length (the transform product's reference) */
static void kara_ref(const uint32_t *a, int an, const uint32_t *b, int bn, uint32_t *out) {
    int n = an > bn ? an : bn;
    uint32_t *x = calloc(n, 4), *y = calloc(n, 4), *r = calloc(2 * n, 4), *s = malloc((size_t)(kara_scratch(n) + 2) * 4);
    memcpy(x, a, (size_t)an * 4); memcpy(y, b, (size_t)bn * 4);
    if (a == b) kara_sqr(x, n, r, s); else kara_mul(x, y, n, r, s);
    memcpy(out, r, (size_t)(an + bn) * 4);
    free(s); free(r); free(y); free(x);
}
static void check_ntt(const uint32_t *a, int an, const uint32_t *b, int bn, int through_mag_mul) {
    uint32_t *want = malloc((size_t)(an + bn) * 4), *got = calloc((size_t)(an + bn), 4);
    uint32_t *x = malloc((size_t)an * 4), *y = a == b ? x : malloc((size_t)bn * 4);     /* own allocations, for AddressSanitizer */
    memcpy(x, a, (size_t)an * 4); if (y != x) memcpy(y, b, (size_t)bn * 4);
    kara_ref(a, an, b, bn, want);
    if (through_mag_mul) mag_mul(x, an, y, bn, got); else ntt_mul(x, an, y, bn, got);
    if (memcmp(got, want, (size_t)(an + bn) * 4)) {
        fprintf(stderr, "transform product mismatch: an=%d bn=%d square=%d via=%s seed=%llu\n", an, bn, a == b, through_mag_mul ? "mag_mul" : "ntt_mul", (unsigned long long)seed); exit(1);
    }
    free(got); free(want); if (y != x) free(y); free(x);
}
static void ntt_tests(void) {
    enum { M = 40000 };
    uint32_t *a = malloc(M * 4), *b = malloc(M * 4);
    for (int k = 0; k < 120; k++) {
        /* ntt_mul takes any length; mag_mul uses it from NTT_MIN limbs in the shorter operand (a long other one in pieces) */
        static const int near[] = { 1, 2, 3, 4, 5, 63, 64, 65, 1023, 1024, 1025, 2047, 2048, 2049, 4095, 4096, 4097, 8191, 8192, 8193 };
        int an = k % 3 ? near[rnd() % 20] + (int)(rnd() % 3) : 1 + (int)(rnd() % 20000);
        int bn = k % 4 == 0 ? an : k % 4 == 1 ? near[rnd() % 20] + (int)(rnd() % 3) : 1 + (int)(rnd() % 20000);
        fill(a, an, k); fill(b, bn, k + 1);
        if (k % 2 == 0) check_ntt(a, an, a, an, 0);
        check_ntt(a, an, b, bn, 0);
    }
    for (int k = 0; k < 24; k++) {                 /* through mag_mul: around NTT_MIN, uneven, and a long b in pieces */
        int an = NTT_MIN - 2 + (int)(rnd() % 8) + (k % 3 == 0 ? (int)(rnd() % 3000) : 0);
        int bn = k % 4 == 0 ? an : k % 4 == 1 ? an + (int)(rnd() % 3) : an + (int)(rnd() % 30000);
        if (bn > M) bn = M;
        fill(a, an, k); fill(b, bn, k + 1);
        if (k % 4 == 0) check_ntt(a, an, a, an, 1);
        check_ntt(a, an, b, bn, 1);
    }
    free(b); free(a);
}
int main(void) {
    static uint32_t a[N], b[N];
    for (int k = 0; k < 6000; k++) {
        /* lengths around the thresholds and their doubles most of the time, else anything up to N */
        static const int near[] = { 1, 2, 3, 39, 40, 41, 63, 64, 65, 79, 80, 81, 127, 128, 129, 130, 131, 255, 257, 513 };
        int an = k % 3 ? near[rnd() % 20] + (int)(rnd() % 3) : 1 + (int)(rnd() % N);
        int bn = k % 4 == 0 ? an : k % 4 == 1 ? near[rnd() % 20] : 1 + (int)(rnd() % N);
        if (an > N) an = N;
        fill(a, an, k); fill(b, bn, k + 1);
        if (k % 2 == 0) check(a, an, a, an);     /* the same number: squaring */
        check(a, an, b, bn);
    }
    ntt_tests();
    puts("ok");
}
