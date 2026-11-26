/* Compare magnitude multiplication (schoolbook, Karatsuba, squaring, uneven lengths) with a plain 32-bit schoolbook product. */
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
    puts("ok");
}
