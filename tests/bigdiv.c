/* Compare magnitude division with independent bit-at-a-time long division, and check long divisions (Burnikel-Ziegler) by
 * multiplying back: u = q v + r with r < v. A low recursion threshold makes short numbers take the recursive path too. */
#define DIV_DC_T 6
#include "../runtime/tomato_rt.c"
const int32_t tomato_kinds[8];
const int32_t *const tomato_offsets[8];
int64_t tomato_parents[8];
const char *tomato_class_names[8];
int32_t tomato_exc_seen;
void tomato_call_drop(void *o) { (void)o; }

#define N 80
static uint64_t seed = 1;
static uint32_t rnd(void) {
    seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17;
    return (uint32_t)seed;
}
static void check(uint32_t *u, int un, uint32_t *v, int vn) {
    uint32_t q[N] = {0}, r[N] = {0}, eq[N] = {0}, er[N + 1] = {0};
    mag_divmod(u, un, v, vn, q, r);
    for (int bit = un * 32; bit-- > 0;) {
        uint32_t carry = (u[bit / 32] >> (bit % 32)) & 1;
        for (int i = 0; i <= vn; i++) {
            uint32_t next = er[i] >> 31; er[i] = (er[i] << 1) | carry; carry = next;
        }
        if (er[vn] || mag_cmp(er, vn, v, vn) >= 0) {
            uint64_t borrow = 0;
            for (int i = 0; i < vn; i++) {
                uint64_t sub = (uint64_t)v[i] + borrow;
                borrow = er[i] < sub; er[i] = (uint32_t)(er[i] - sub);
            }
            er[vn] -= (uint32_t)borrow;
            eq[bit / 32] |= (uint32_t)1 << (bit % 32);
        }
    }
    if (memcmp(q, eq, (size_t)un * 4) || memcmp(r, er, (size_t)vn * 4)) {
        fprintf(stderr, "division mismatch: un=%d vn=%d seed=%llu\n", un, vn, (unsigned long long)seed); exit(1);
    }
}
#define M 1500
/* the stress patterns: random, all ones, a lone top bit, B^k - 1 with zeros below, and dividends just below a multiple */
static void fill(uint32_t *d, int n, int k) {
    for (int i = 0; i < n; i++) d[i] = rnd();
    switch (k % 6) {
    case 1: for (int i = 0; i < n; i++) d[i] = UINT32_MAX; break;
    case 2: for (int i = 0; i < n; i++) d[i] = 0; d[n - 1] = (uint32_t)1 << (rnd() % 32); break;
    case 3: for (int i = 0; i < n / 2; i++) d[i] = 0; break;
    case 4: for (int i = n / 3; i < n - 1; i++) d[i] = UINT32_MAX; break;
    }
    if (d[n - 1] == 0) d[n - 1] = 1;
}
static void check_long(const uint32_t *u0, int un, const uint32_t *v0, int vn) {
    uint32_t *u = malloc((size_t)un * 4), *v = malloc((size_t)vn * 4), *q = malloc((size_t)un * 4), *r = malloc((size_t)vn * 4);
    uint32_t *back = calloc((size_t)(un + vn + 1), 4);
    memcpy(u, u0, (size_t)un * 4); memcpy(v, v0, (size_t)vn * 4);
    mag_divmod(u, un, v, vn, q, r);
    int64_t qn = un, rn = vn;
    while (qn > 0 && q[qn - 1] == 0) qn--;
    while (rn > 0 && r[rn - 1] == 0) rn--;
    if (qn) mag_mul(q, qn, v, vn, back);
    mag_add_in(back, un + vn + 1, r, rn);
    int64_t bn = un + vn + 1;
    while (bn > 0 && back[bn - 1] == 0) bn--;
    if (mag_cmp(r, rn, v, vn) >= 0 || mag_cmp(back, bn, u, un) != 0) {
        fprintf(stderr, "long division mismatch: un=%d vn=%d seed=%llu\n", un, vn, (unsigned long long)seed); exit(1);
    }
    free(u); free(v); free(q); free(r); free(back);
}
int main(void) {
    uint32_t u[N], v[N];
    /* (B^2 + 1) * B - 1, B = 2^64: the leading estimate is one too high
     * even after the second-word check, so division must add the divisor back. */
    uint32_t addback_u[] = { UINT32_MAX, UINT32_MAX, 0, 0, 0, 0, 1 };
    uint32_t addback_v[] = { 1, 0, 0, 0, 1 };
    check(addback_u, 7, addback_v, 5);
    for (int k = 0; k < 20000; k++) {
        int un = 1 + rnd() % N, vn = 1 + rnd() % N;
        for (int i = 0; i < un; i++) u[i] = rnd();
        for (int i = 0; i < vn; i++) v[i] = rnd();
        /* Exercise normalization shifts, all-one words, powers of two and equality. */
        if (k % 4 == 0) v[vn - 1] = (uint32_t)1 << (k % 32);
        if (k % 7 == 0) for (int i = 0; i < vn; i++) v[i] = UINT32_MAX;
        if (k % 11 == 0) { un = vn; memcpy(u, v, (size_t)vn * 4); }
        u[un - 1] |= 1; v[vn - 1] |= 1;
        check(u, un, v, vn);
    }
    static uint32_t lu[2 * M + 2], lv[M];
    for (int k = 0; k < 1500; k++) {
        int vn = 1 + (int)(rnd() % M), un = vn + (int)(rnd() % (k % 3 ? M : 40));
        if (k % 5 == 0) un = 2 * vn - (int)(rnd() % 3);            /* the balanced 2n/n case */
        fill(lv, vn, k); fill(lu, un, k / 6 + 1);
        if (k % 7 == 0) {                                              /* u = q v + (v - 1): the largest remainder */
            int qn = un - vn > 0 ? un - vn : 1;
            uint32_t *p = calloc((size_t)(qn + vn + 1), 4);
            fill(lu, qn, k);
            mag_mul(lu, qn, lv, vn, p);
            uint32_t one[1] = {1}, *vm = malloc((size_t)vn * 4);
            mag_sub(lv, vn, one, 1, vm);
            mag_add_in(p, qn + vn + 1, vm, vn);
            un = qn + vn + 1;
            while (un > 1 && p[un - 1] == 0) un--;
            memcpy(lu, p, (size_t)un * 4);
            free(p); free(vm);
        }
        check_long(lu, un, lv, vn);
    }
    puts("ok");
}
