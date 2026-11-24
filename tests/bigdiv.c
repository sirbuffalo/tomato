/* Compare magnitude division with independent bit-at-a-time long division. */
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
    puts("ok");
}
