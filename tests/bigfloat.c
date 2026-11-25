/* Tests of the floats of any size in runtime/tomato_rt.c (docs/bigfloat-runtime.md). The runtime is included, so its static
 * functions and its count of big numbers are in reach.
 *   clang -O1 -g -fsanitize=address,undefined -o bigfloat tests/bigfloat.c -lm && ./bigfloat [rounds] [seed]
 * checks fixed cases, then `rounds` random cases of everything against an exact reference: the whole numbers below (Nat),
 * which are schoolbook and share no code with the runtime. Nothing is printed but failures and a last line.
 *   ./bigfloat --eval   reads "op x y" lines and writes the results, for a comparison with another implementation. A float is
 *   written MANTISSA:EXPONENT, a whole number in hex times a power of two in decimal: 3:-1 is 1.5. */
#include "../runtime/tomato_rt.c"
const int32_t tomato_kinds[8] = { [5] = 1 | 8192, [6] = 2 | 8192, [7] = 3 | 8192 };
static const int32_t float_object_offsets[] = { -1, -1, 16, -1 };
const int32_t *const tomato_offsets[8] = { [5] = float_object_offsets };
int64_t tomato_parents[8];
const char *tomato_class_names[8];
int32_t tomato_exc_seen;
void tomato_call_drop(void *o) { (void)o; }

typedef __int128 i128;
static int failures = 0;
static const char *what = "";
static void fail(const char *why) {
    if (failures++ < 20) fprintf(stderr, "FAIL %s: %s\n", what, why);
}

/* ---- random numbers (splitmix64) ---- */
static uint64_t seed = 1;
static uint64_t rnd(void) {
    uint64_t z = (seed += 0x9E3779B97F4A7C15ULL);
    z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ULL;
    z = (z ^ (z >> 27)) * 0x94D049BB133111EBULL;
    return z ^ (z >> 31);
}
static int64_t below(int64_t n) { return (int64_t)(rnd() % (uint64_t)n); }

/* ---- the reference: whole numbers of up to NAT limbs ---- */
#define NAT 900
typedef struct { int n; uint32_t d[NAT]; } Nat;
static void nat_set(Nat *r, uint64_t v) { r->n = 0; while (v) { r->d[r->n++] = (uint32_t)v; v >>= 32; } }
static void nat_copy(Nat *r, const Nat *a) { r->n = a->n; memcpy(r->d, a->d, (size_t)a->n * 4); }
static int nat_bits(const Nat *a) { return a->n == 0 ? 0 : a->n * 32 - __builtin_clz(a->d[a->n - 1]); }
static int nat_bit(const Nat *a, int k) { return k / 32 < a->n ? a->d[k / 32] >> (k % 32) & 1 : 0; }
static int nat_cmp(const Nat *a, const Nat *b) {
    if (a->n != b->n) return a->n < b->n ? -1 : 1;
    for (int i = a->n - 1; i >= 0; i--) if (a->d[i] != b->d[i]) return a->d[i] < b->d[i] ? -1 : 1;
    return 0;
}
static void nat_muladd(Nat *r, uint32_t m, uint32_t c) {        /* r = r * m + c */
    uint64_t t = c;
    for (int i = 0; i < r->n; i++) { t += (uint64_t)r->d[i] * m; r->d[i] = (uint32_t)t; t >>= 32; }
    if (t) r->d[r->n++] = (uint32_t)t;
    if (r->n > NAT - 8) { fprintf(stderr, "a reference number is too long\n"); exit(2); }
}
static uint32_t nat_div_small(Nat *r, uint32_t m) {             /* r = r / m, giving the remainder */
    uint64_t t = 0;
    for (int i = r->n - 1; i >= 0; i--) { t = t << 32 | r->d[i]; r->d[i] = (uint32_t)(t / m); t %= m; }
    while (r->n && r->d[r->n - 1] == 0) r->n--;
    return (uint32_t)t;
}
static void nat_shl(Nat *r, int k) {
    if (r->n == 0) return;
    int w = k / 32;
    if (r->n + w > NAT - 8) { fprintf(stderr, "a reference number is too long\n"); exit(2); }
    memmove(r->d + w, r->d, (size_t)r->n * 4);
    memset(r->d, 0, (size_t)w * 4);
    r->n += w;
    nat_muladd(r, (uint32_t)1 << (k % 32), 0);
}
static void nat_add(Nat *r, const Nat *b) {
    uint64_t t = 0;
    for (int i = 0; i < r->n || i < b->n || t; i++) {
        t += (uint64_t)(i < r->n ? r->d[i] : 0) + (i < b->n ? b->d[i] : 0);
        if (i >= r->n) r->n = i + 1;
        r->d[i] = (uint32_t)t; t >>= 32;
    }
}
static void nat_sub(Nat *r, const Nat *b) {                      /* r >= b */
    int64_t t = 0;
    for (int i = 0; i < r->n; i++) { t += (int64_t)r->d[i] - (i < b->n ? b->d[i] : 0); r->d[i] = (uint32_t)t; t >>= 32; }
    while (r->n && r->d[r->n - 1] == 0) r->n--;
}
static void nat_mul(Nat *r, const Nat *a, const Nat *b) {       /* r is another number */
    static Nat t;
    r->n = 0;
    for (int i = b->n - 1; i >= 0; i--) { nat_shl(r, 32); nat_copy(&t, a); nat_muladd(&t, b->d[i], 0); nat_add(r, &t); }
}
static void nat_divmod(const Nat *a, const Nat *b, Nat *q, Nat *r) { /* bit by bit */
    q->n = r->n = 0;
    for (int i = nat_bits(a) - 1; i >= 0; i--) {
        nat_muladd(r, 2, (uint32_t)nat_bit(a, i));
        nat_muladd(q, 2, 0);
        if (nat_cmp(r, b) >= 0) { nat_sub(r, b); if (q->n == 0) q->n = 1, q->d[0] = 0; q->d[0] |= 1; }
    }
}
static void nat_pow(Nat *r, uint32_t b, int k) { nat_set(r, 1); while (k-- > 0) nat_muladd(r, b, 0); }

/* a float as a sign, a whole number of 53 bits and the exponent of its top bit; M is 0 for zero */
typedef struct { int neg; uint64_t M; i128 E; } Val;

/* what a * 2^e rounds to (or a value just beyond a, when more is set) */
static Val ref_round(int neg, const Nat *a, i128 e, int more) {
    Val v = { neg, 0, 0 };
    int bits = nat_bits(a);
    if (bits == 0) return v;
    for (int i = 0; i < 53; i++) v.M = v.M << 1 | (uint64_t)(bits - 1 - i >= 0 ? nat_bit(a, bits - 1 - i) : 0);
    int half = bits > 53 ? nat_bit(a, bits - 54) : 0, rest = more;
    for (int i = bits - 55; i >= 0 && !rest; i--) rest = nat_bit(a, i);
    v.E = e + bits - 1;
    if (half && (rest || (v.M & 1))) v.M++;
    if (v.M >> 53) { v.M >>= 1; v.E++; }
    return v;
}

static i128 to_i128(int64_t x) {
    IntView a; int_view(x, &a);
    i128 r = 0;
    if (a.n > 4) { fail("an exponent of more than 128 bits"); return 0; }
    for (int64_t i = a.n - 1; i >= 0; i--) r = r << 32 | a.d[i];
    return a.sign < 0 ? -r : r;
}
static int64_t from_i128(i128 v) {
    unsigned __int128 u = v < 0 ? -(unsigned __int128)v : (unsigned __int128)v;
    uint32_t d[4] = { (uint32_t)u, (uint32_t)(u >> 32), (uint32_t)(u >> 64), (uint32_t)(u >> 96) };
    return int_make(v < 0 ? -1 : 1, d, 4);
}
static int64_t from_nat(const Nat *a, int neg) { return int_make(neg ? -1 : 1, a->d, a->n); }

/* the lowest bit set of a 53-bit mantissa decides whether a subnormal double holds the value */
static int is_double(uint64_t M, i128 E) {
    if (E > 1023 || E < -1074) return 0;
    return E >= -1022 || M % ((uint64_t)1 << (int)(-1022 - E)) == 0;
}
/* takes a float apart, and checks that it is canonical */
static Val value(int64_t w) {
    Val v = { 0, 0, 0 };
    int e = 1;
    double m;
    if (bf_boxed(w)) {
        m = bf_ptr(w)->m;
        v.E = to_i128(bf_ptr(w)->e);
        if (!(fabs(m) >= 1 && fabs(m) < 2)) fail("a box's mantissa is not from 1 to 2");
    } else {
        double d = bf_double(w);
        if (!isfinite(d)) { fail("a plain float is not finite"); return v; }
        m = frexp(d, &e) * 2;
        v.E = m == 0 ? 0 : e - 1;
    }
    v.neg = signbit(m) != 0;
    v.M = (uint64_t)ldexp(fabs(m), 52);
    if (bf_boxed(w) && is_double(v.M, v.E)) fail("a box holds a value that fits a double");
    return v;
}
/* the word of a value, made without the code under test */
static int64_t word(Val v) {
    double m = ldexp(v.neg ? -(double)v.M : (double)v.M, -52);
    if (v.M == 0) return bf_bits(v.neg ? -0.0 : 0.0);
    if (is_double(v.M, v.E)) return bf_bits(ldexp(m, (int)v.E));
    return bf_box(m, from_i128(v.E));
}
static void show(char *out, Val v) {
    char e[48]; int k = 47, n = v.E < 0; unsigned __int128 u = n ? -(unsigned __int128)v.E : (unsigned __int128)v.E;
    e[k] = 0; do { e[--k] = (char)('0' + (int)(u % 10)); u /= 10; } while (u);
    if (n) e[--k] = '-';
    sprintf(out, "%s%llx:%s(+52)", v.neg ? "-" : "", (unsigned long long)v.M, e + k);
}
/* compares a result (and frees it) with the expected value, after x and y, the operands */
static void expect(int64_t w, Val want, Val x, Val y) {
    Val got = value(w);
    if (got.neg != want.neg || got.M != want.M || (got.M != 0 && got.E != want.E)) {
        char b[4][80], msg[400];
        show(b[0], x); show(b[1], y); show(b[2], got); show(b[3], want);
        snprintf(msg, sizeof msg, "x %s y %s gives %s, not %s", b[0], b[1], b[2], b[3]);
        fail(msg);
    }
    tomato_bf_free(w);
}
/* the mask of operands given up: those are copied first, so that the caller frees its own in every case */
static int32_t mask(void) { return (int32_t)below(4); }
#define GIVE(x, m, bit) ((m) & (bit) ? tomato_bf_dup(x) : (x))

/* ---- random values ---- */
static uint64_t rnd_mant(void) {
    uint64_t top = (uint64_t)1 << 52, all = top | (rnd() >> 12);
    switch (below(6)) {
    case 0: return top | (rnd() >> 12 & (rnd() >> 12) & (rnd() >> 12));
    case 1: return top + (uint64_t)below(4);
    case 2: return 2 * top - 1 - (uint64_t)below(4);
    case 3: return top | (uint64_t)below(1 << 10) << 42;
    default: return all;
    }
}
static i128 rnd_base(void) {
    switch (below(8)) {
    case 0: return 1023; case 1: return -1074; case 2: return below(2) ? -1022 : -511; case 3: return 0;
    case 4: return below(4000) - 2000; case 5: return below(2000000) - 1000000;
    case 6: return ((i128)1 << (60 + below(5))) * (below(2) ? 1 : -1);
    default: return (((i128)1 << 100) + (i128)rnd()) * (below(2) ? 1 : -1);
    }
}
static Val rnd_val(i128 base) { Val v = { (int)below(2), rnd_mant(), base + below(140) - 70 }; return v; }
static void rnd_pair(Val *x, Val *y) {
    i128 base = rnd_base();
    *x = rnd_val(base);
    *y = rnd_val(below(3) ? base : rnd_base());
    if (below(40) == 0) x->M = 0;
    if (below(8) == 0) { y->M = x->M ? x->M : y->M; y->E = x->E; }                   /* cancellation */
    if (below(8) == 0) { y->E = x->E - 50 - below(8); }                              /* a tie, or nearly */
    if (below(8) == 0) { y->M = (uint64_t)1 << 52; y->E = x->E - 53 - below(3); }
}
static void rnd_nat(Nat *a, int maxbits) {
    if (below(5) == 0) {                                     /* halfway between two floats, or just off it */
        nat_set(a, rnd_mant() * 2 + 1);
        nat_shl(a, 1 + (int)below(maxbits));
        a->d[0] ^= (uint32_t)below(2);
        return;
    }
    int bits = (int)below(maxbits) + 1;
    a->n = (bits + 31) / 32;
    uint64_t sparse = rnd() % 3;
    for (int i = 0; i < a->n; i++) a->d[i] = sparse == 0 ? (uint32_t)rnd() : sparse == 1 ? 0 : 0xFFFFFFFFu;
    if (sparse) a->d[below(a->n)] ^= (uint32_t)1 << below(32);
    a->d[a->n - 1] |= 1;
    if (bits % 32) a->d[a->n - 1] &= ((uint32_t)1 << (bits % 32)) - 1;
    while (a->n && a->d[a->n - 1] == 0) a->n--;
}

/* ---- arithmetic ---- */
static Val ref_add(Val x, Val y) {
    static Nat a, b;
    if (x.M == 0 || y.M == 0) {
        if (x.M == 0 && y.M == 0) x.neg = x.neg && y.neg;
        return x.M ? x : y.M ? y : x;
    }
    if (x.E < y.E) { Val t = x; x = y; y = t; }
    if (x.E - y.E > 200) { y.E = x.E - 200; y.M = (uint64_t)1 << 52; }       /* far below the last place either way */
    nat_set(&a, x.M); nat_shl(&a, (int)(x.E - y.E)); nat_set(&b, y.M);
    if (x.neg == y.neg) { nat_add(&a, &b); return ref_round(x.neg, &a, y.E - 52, 0); }
    int c = nat_cmp(&a, &b);
    if (c == 0) { Val z = { 0, 0, 0 }; return z; }
    if (c > 0) { nat_sub(&a, &b); return ref_round(x.neg, &a, y.E - 52, 0); }
    nat_sub(&b, &a);
    return ref_round(y.neg, &b, y.E - 52, 0);
}
static Val ref_div(Val x, Val y) {
    static Nat a, b, q, r;
    nat_set(&a, x.M); nat_shl(&a, 120); nat_set(&b, y.M);
    nat_divmod(&a, &b, &q, &r);
    return ref_round(x.neg != y.neg, &q, x.E - y.E - 120, r.n != 0);
}
static Val ref_floor(Val v) {
    static Nat a;
    Val zero = { 0, 0, 0 }, one = { 1, (uint64_t)1 << 52, 0 };
    if (v.M == 0 || v.E >= 52) return v;
    if (v.E < 0) return v.neg ? one : zero;
    int drop = (int)(52 - v.E);
    uint64_t t = v.M >> drop;
    if (v.neg && t << drop != v.M) t++;
    nat_set(&a, t);
    return ref_round(v.neg, &a, 0, 0);
}
static Val ref_mod(Val x, Val y) {
    Val r = x;
    if (x.M && x.E >= y.E) {
        static Nat a;
        uint64_t t = x.M % y.M;
        for (i128 d = x.E - y.E; d > 0; d--) t = t * 2 % y.M;
        nat_set(&a, t);
        r = ref_round(x.neg, &a, y.E - 52, 0);
    }
    return r.M && r.neg != y.neg ? ref_add(r, y) : r;
}
static int ref_cmp(Val x, Val y) {
    int sx = x.M == 0 ? 0 : x.neg ? -1 : 1, sy = y.M == 0 ? 0 : y.neg ? -1 : 1;
    if (sx != sy) return sx < sy ? -1 : 1;
    if (sx == 0) return 0;
    if (x.E != y.E) return x.E < y.E ? -sx : sx;
    return x.M == y.M ? 0 : x.M < y.M ? -sx : sx;
}
static void test_arithmetic(void) {
    Val x, y, n;
    rnd_pair(&x, &y);
    int64_t a = word(x), b = word(y);
    int32_t m = mask();
    static Nat p, q, r;
    what = "add"; expect(tomato_bf_add(GIVE(a, m, 1), GIVE(b, m, 2), m), ref_add(x, y), x, y);
    n = y; n.neg = !n.neg;
    what = "sub"; expect(tomato_bf_sub(GIVE(a, m, 1), GIVE(b, m, 2), m), ref_add(x, n), x, y);
    nat_set(&p, x.M); nat_set(&q, y.M); nat_mul(&r, &p, &q);
    what = "mul"; expect(tomato_bf_mul(GIVE(a, m, 1), GIVE(b, m, 2), m), ref_round(x.neg != y.neg, &r, x.E + y.E - 104, 0), x, y);
    what = "div"; expect(tomato_bf_div(GIVE(a, m, 1), GIVE(b, m, 2), m), ref_div(x, y), x, y);
    what = "floordiv"; expect(tomato_bf_floordiv(GIVE(a, m, 1), GIVE(b, m, 2), m), ref_floor(ref_div(x, y)), x, y);
    if (x.E - y.E < 3000) { what = "mod"; expect(tomato_bf_mod(GIVE(a, m, 1), GIVE(b, m, 2), m), ref_mod(x, y), x, y); }
    what = "cmp"; if (tomato_bf_cmp(GIVE(a, m, 1), GIVE(b, m, 2), m) != ref_cmp(x, y)) fail("wrong order");
    n = x; n.neg = !n.neg;
    what = "neg"; expect(tomato_bf_neg(GIVE(a, m, 1), m & 1), n, x, x);
    n.neg = 0;
    what = "abs"; expect(tomato_bf_abs(GIVE(a, m, 1), m & 1), n, x, x);
    what = "to_f64";
    if (tomato_bf_fits_f64(a) != (x.M == 0 || x.E <= 1023)) fail("wrong fit");
    /* a subnormal is the value rounded at the fixed place 2^-1074 */
    double d = tomato_bf_to_f64(a), want;
    if (x.M == 0) want = 0;
    else if (x.E > 1023) want = INFINITY;
    else if (x.E >= -1022) want = ldexp((double)x.M, (int)x.E - 52);
    else if (x.E < -1075) want = 0;
    else {
        int drop = (int)(-1022 - x.E);
        uint64_t t = x.M >> drop, rest = x.M & (((uint64_t)1 << drop) - 1), half = (uint64_t)1 << (drop - 1);
        if (rest > half || (rest == half && (t & 1))) t++;
        want = ldexp((double)t, -1074);
    }
    if (d != (x.neg ? -want : want) || (signbit(d) != 0) != x.neg) fail("wrong double");
    tomato_bf_free(a); tomato_bf_free(b);
}

/* ---- ints ---- */
static void test_ints(void) {
    static Nat a, b, q, r, t;
    rnd_nat(&a, below(2) ? 130 : 3000); rnd_nat(&b, below(2) ? 130 : 3000);
    int na = (int)below(2), nb = (int)below(2);
    int64_t x = from_nat(&a, na), y = from_nat(&b, nb);
    int32_t m = mask();
    Val zero = { 0, 0, 0 }, v = ref_round(na, &a, 0, 0);
    what = "from_int"; expect(tomato_bf_from_int(m & 1 ? tomato_int_dup(x) : x, m & 1), v, zero, zero);
    nat_copy(&t, &a); nat_shl(&t, 70 + nat_bits(&b));
    nat_divmod(&t, &b, &q, &r);
    what = "int_div";
    expect(tomato_bf_int_div(m & 1 ? tomato_int_dup(x) : x, m & 2 ? tomato_int_dup(y) : y, m), ref_round(na != nb, &q, -70 - nat_bits(&b), r.n != 0), zero, zero);
    /* a float near the int, moved by a few places or cut */
    what = "cmp_int";
    Val f = v;
    if (below(2)) f.M += (uint64_t)(below(3) - 1);
    if (below(8) == 0) f.E += below(3) - 1;
    if (below(8) == 0) f.neg = !f.neg;
    if (below(4) == 0) { f = rnd_val(rnd_base()); }
    if (f.M >> 53) { f.M >>= 1; f.E++; }
    if (f.M >> 52 == 0) { f.M = ((uint64_t)1 << 53) - 1; f.E--; }
    if (below(30) == 0) f.M = 0;
    int want;
    if (f.M == 0) want = na ? 1 : -1;
    else if (f.neg != na) want = f.neg ? -1 : 1;
    else if (f.E > 4000) want = 1; else if (f.E < -4000) want = -1;
    else {
        nat_set(&t, f.M); nat_copy(&q, &a);
        if (f.E >= 52) nat_shl(&t, (int)f.E - 52); else nat_shl(&q, (int)(52 - f.E));
        want = nat_cmp(&t, &q);
    }
    if (f.M && f.neg == na && f.neg) want = -want;
    int64_t w = word(f);
    int got = tomato_bf_cmp_int(GIVE(w, m, 1), m & 2 ? tomato_int_dup(x) : x, m);
    if (got != want) { char s[80]; show(s, f); fail(s); }
    /* the whole part */
    if (f.E < 6000) {
        what = "to_int";
        nat_set(&t, f.M);
        if (f.E >= 52) nat_shl(&t, (int)f.E - 52); else nat_set(&t, f.E < 0 ? 0 : f.M >> (52 - f.E));
        int64_t z = from_nat(&t, f.neg), g = tomato_bf_to_int(GIVE(w, m, 1), m & 1);
        if (tomato_int_cmp(z, g) != 0) fail("wrong whole part");
        tomato_int_free(z); tomato_int_free(g);
    }
    tomato_bf_free(w); tomato_int_free(x); tomato_int_free(y);
}

/* ---- fixed cases ---- */
static void test_fixed(void) {
    what = "mul";      /* the hardware rounds this product up to the smallest normal double */
    Val x = { 0, ((uint64_t)1 << 53) - 1, -512 }, y = { 0, (uint64_t)1 << 52, -511 }, z = x;
    z.E = -1023;
    expect(tomato_bf_mul(word(x), word(y), 3), z, x, y);
}

/* ---- text ---- */
/* compares d * 10^j with q * 2^e, exactly */
static int cmp_decimal(const Nat *d, int j, uint64_t q, int e) {
    static Nat a, b, p, t;
    nat_copy(&a, d); nat_set(&b, q);
    nat_pow(&p, 10, j < 0 ? -j : j);
    if (j < 0) { nat_mul(&t, &b, &p); nat_copy(&b, &t); } else { nat_mul(&t, &a, &p); nat_copy(&a, &t); }
    if (e < 0) nat_shl(&a, -e); else nat_shl(&b, e);
    return nat_cmp(&a, &b);
}
static int cmp_decimal_u(uint64_t d, int j, uint64_t q, int e) { static Nat a; nat_set(&a, d); return cmp_decimal(&a, j, q, e); }
/* the text's whole number of digits and its exponent of ten; 0 when it is not in the decimal form */
static int read_decimal(const char *s, uint64_t *d, int *j, int *neg) {
    int point = 0;
    *d = 0; *j = 0; *neg = *s == '-'; s += *neg;
    for (; (*s >= '0' && *s <= '9') || *s == '.'; s++) { if (*s == '.') point = 1; else { *d = *d * 10 + (uint64_t)(*s - '0'); *j -= point; } }
    if (*s != 'e') return 0;
    *j += atoi(s + 1);
    return 1;
}
static void test_print(void) {
    Val x = rnd_val(below(2) ? below(2) ? 1100 : -1100 : below(6000) - 3000);
    if (below(8) == 0) { x.E = -1030 - below(44); x.M &= ~(uint64_t)0 << (int)(-1022 - x.E); }        /* a subnormal double prints by the same rule */
    else if (is_double(x.M, x.E)) x.E += 2400;
    else if (below(4) == 0) {                                              /* a power of ten, or a float beside one */
        char t[20]; snprintf(t, sizeof t, "1e%lld", (long long)((309 + below(600)) * (below(2) ? 1 : -1)));
        int64_t ten = tomato_bf_literal(t);
        x = value(ten); tomato_bf_free(ten);
        x.M += (uint64_t)(below(3) - 1);
    }
    int64_t w = word(x);
    Str *s = tomato_bf_str(w);
    uint64_t d; int j, neg, e = (int)x.E - 54, low = x.M == (uint64_t)1 << 52 ? 1 : 2;
    what = "print";
    if (!read_decimal(s->data, &d, &j, &neg) || neg != x.neg) fail(s->data);
    else {
        if (cmp_decimal_u(d, j, 4 * x.M - (uint64_t)low, e) < 0 || cmp_decimal_u(d, j, 4 * x.M + 2, e) > 0) fail("does not read back");
        if (cmp_decimal_u(2 * d + 1, j, 8 * x.M, e) < 0 || cmp_decimal_u(2 * d - 1, j, 8 * x.M, e) > 0) fail("not the nearest");
        for (uint64_t c = d / 10 ? d / 10 - 1 : 0; c <= d / 10 + 1 && d >= 10; c++)
            if (c && cmp_decimal_u(2 * c + 1, j + 1, 8 * x.M, e) >= 0 && cmp_decimal_u(2 * c - 1, j + 1, 8 * x.M, e) <= 0 && cmp_decimal_u(c, j + 1, 4 * x.M - (uint64_t)low, e) > 0 && cmp_decimal_u(c, j + 1, 4 * x.M + 2, e) < 0) fail("not the shortest");
    }
    what = "print and read"; expect(tomato_bf_text(s), x, x, x);
    tomato_release(s); tomato_bf_free(w);
}
static void test_round_trip(int bits) {                                    /* an exponent of about so many bits */
    uint32_t d[300];
    int n = bits / 32 + 1;
    for (int i = 0; i < n; i++) d[i] = (uint32_t)rnd();
    Val v = { (int)below(2), rnd_mant(), 0 };
    int64_t x = bf_box(v.neg ? -ldexp((double)v.M, -52) : ldexp((double)v.M, -52), int_make(below(2) ? 1 : -1, d, n));
    Str *s = tomato_bf_str(x);
    int64_t y = tomato_bf_text(s);
    what = "print and read, big exponent";
    if (!bf_boxed(y) || tomato_bf_cmp(x, y, 0) != 0) fail(s->data);
    tomato_release(s); tomato_bf_free(x); tomato_bf_free(y);
}
/* checks that w is the float nearest to d * 10^j */
static void check_parse(const char *text, const Nat *d, int j) {
    Str *s = str_new(text, (int64_t)strlen(text));
    int64_t w = tomato_bf_text(s);
    Val v = value(w);
    if (d->n == 0) { if (v.M) fail(text); }
    else if (v.M == 0 || v.E > 8000 || v.E < -8000) fail(text);
    else {
        int e = (int)v.E - 54, low = v.M == (uint64_t)1 << 52 ? 1 : 2, even = !(v.M & 1);
        int a = cmp_decimal(d, j, 4 * v.M - (uint64_t)low, e), b = cmp_decimal(d, j, 4 * v.M + 2, e);
        if (a < 0 || b > 0 || (!even && (a == 0 || b == 0))) fail(text);
    }
    tomato_release(s); tomato_bf_free(w);
}
static void test_parse(void) {
    static char t[8000], u[8200];
    static Nat d, p, q;
    int j, n = 0;
    what = "parse";
    if (below(4) == 0) {                                                   /* halfway between two floats: every digit of it */
        int e = (int)below(800) + 900; if (below(2)) e = -e;
        nat_set(&d, rnd_mant() * 2 + 1);
        if (e >= 0) { nat_shl(&d, e); j = 0; } else { nat_pow(&p, 5, -e); nat_mul(&q, &d, &p); nat_copy(&d, &q); j = e; }
        nat_muladd(&d, 1000, 0); j -= 3;
        nat_set(&p, (uint64_t)below(2));
        if (below(2)) nat_add(&d, &p); else nat_sub(&d, &p);
    } else {
        d.n = 0;
        int k = (int)below(below(4) ? 25 : 120) + 1;
        while (k-- > 0) nat_muladd(&d, 10, (uint32_t)below(10));
        j = below(3) == 0 ? (int)below(40) - 330 : (int)below(1600) - 800;
    }
    nat_copy(&q, &d);
    do { t[n++] = (char)('0' + nat_div_small(&q, 10)); } while (q.n && n < 7990);
    for (int i = 0; i < n / 2; i++) { char c = t[i]; t[i] = t[n - 1 - i]; t[n - 1 - i] = c; }
    t[n] = 0;
    int cut = (int)below(n + 1);                                           /* where the point goes */
    snprintf(u, sizeof u, "%s%.*s.%se%s%d", below(2) ? "-" : "", cut, t, t + cut, below(2) && j + n - cut >= 0 ? "+" : "", j + n - cut);
    check_parse(u, &d, j);
}
static void reads(const char *text, const char *want) {                    /* want is NULL for text that is not a number */
    Str *s = str_new(text, (int64_t)strlen(text));
    int64_t w = tomato_bf_text(s);
    if (!want) { if (w != BF_NONE) { fail(text); tomato_bf_free(w); } }
    else if (w == BF_NONE) fail(text);
    else {
        Str *g = tomato_bf_str(w);
        if (strcmp(g->data, want)) { fail(text); fail(g->data); }
        tomato_release(g); tomato_bf_free(w);
    }
    tomato_release(s);
}
static void test_text_fixed(void) {
    what = "text";
    static const char *same[] = { "0.0", "-0.0", "1.5", "1e+400", "-1.5e+1000000", "1e-400", "5e-324", "1e-310", "1.7976931348623157e+308", "2.5e+12345678901234567890", "-3e-12345678901234567890123", "0x1.8p+1", NULL };
    for (int i = 0; same[i]; i++) if (same[i][1] != 'x') reads(same[i], same[i]);
    reads("1e400", "1e+400"); reads(" +1E400\n", "1e+400"); reads(".5e500", "5e+499"); reads("5.e500", "5e+500"); reads("0x1.8p+1", "3.0"); reads("-0x1p-2000", "-8.709809816217217e-603");
    reads("0x10p0", "16.0"); reads("0xap5000", "1.412467032139426e+1506"); reads("0e99999999999999999999999", "0.0"); reads("-0.000e-99999999999999999999999", "-0.0");
    reads("1e308", "1e+308"); reads("2e308", "2e+308"); reads("4.9406564584124654e-324", "4.9406564584124654e-324"); reads("-2.2250738585072e-308", "-2.2250738585072e-308"); reads("2.2250738585072014e-308", "2.2250738585072014e-308");
    static const char *bad[] = { "", " ", "-", ".", "e5", "1e", "1e+", "1e+-5", "1e5.0", "1 2", "0x", "0x1.8", "0x10", "0x.p1", "inf", "nan", "-inf", "infinity", "1..2", "1_0", "1e5x", "--1", "+-1", "1p5", "0x1e5", NULL };
    for (int i = 0; bad[i]; i++) reads(bad[i], NULL);
    reads("0x1.8p+1000000000000000000000", "8.222161132569742e+301029995663981195213");
}

/* ---- powers and roots ---- */
static void test_pow(void) {
    static Nat a, b, r, t;
    Val x = rnd_val(below(2) ? 2000 : below(3) ? -2000 : ((i128)1 << 80)), y = { 0, 0, 0 }, c;
    int n = (int)below(below(2) ? 20 : 150), j = 0;
    int64_t ny;
    if (below(2)) {                                                        /* x is c^(2^j), so x ** (n / 2^j) is c^n: exact, or a tie */
        uint64_t k = (uint64_t)below(60) * 2 + 3, m;
        j = (int)below(5); m = k;
        for (int i = 0; i < j; i++) m *= m;
        while (m >> 53 || (j == 4 && k > 9) || (j == 3 && k > 97)) { j--; m = k; for (int i = 0; i < j; i++) m *= m; }
        if (j == 0) x.neg = (int)below(2); else x.neg = 0;
        n = (int)below(40);
        x.E = (x.E >> j) * ((i128)1 << j); x.M = m;
        nat_set(&a, k); nat_set(&r, 1);
        for (int i = 0; i < n; i++) { nat_mul(&t, &r, &a); nat_copy(&r, &t); }
        c = ref_round(x.neg && n % 2, &r, (x.E >> j) * n, 0);
        nat_set(&b, m); x = ref_round(x.neg, &b, x.E, 0);
    } else {
        nat_set(&a, x.M); nat_set(&r, 1);
        for (int i = 0; i < n; i++) { nat_mul(&t, &r, &a); nat_copy(&r, &t); }
        c = ref_round(x.neg && n % 2, &r, (x.E - 52) * n, 0);
    }
    nat_set(&b, (uint64_t)n); y = ref_round(0, &b, -j, 0);
    what = "pow";
    ny = word(y);
    int32_t m = mask();
    int64_t w = word(x);
    if (tomato_bf_pow_check(w, ny)) fail("no value");
    else expect(tomato_bf_pow(GIVE(w, m, 1), ny, m), c, x, y);
    /* the square root r of x: (r - 1/2)^2 <= x <= (r + 1/2)^2 in units of r's last place */
    what = "sqrt";
    Val p = x; p.neg = 0;
    int64_t q = word(p), s = tomato_bf_math1(0, q, 0);
    Val v = value(s);
    nat_set(&a, 2 * v.M - 1); nat_mul(&t, &a, &a);
    nat_set(&b, p.M); int k = (int)(p.E - 2 * v.E) + 54;
    nat_shl(&b, k);
    if (k < 54 || k > 55 || nat_cmp(&t, &b) > 0) fail("too large");
    nat_set(&a, 2 * v.M + 1); nat_mul(&t, &a, &a);
    if (nat_cmp(&t, &b) < 0) fail("too small");
    tomato_bf_free(w); tomato_bf_free(q); tomato_bf_free(s);
}

/* ---- --eval ---- */
static int64_t eval_float(const char *s) {                                 /* MANTISSA:EXPONENT */
    int neg = *s == '-', ok;
    uint64_t m = strtoull(s + neg, NULL, 16);
    const char *e = strchr(s, ':') + 1;
    if (m == 0) return bf_bits(neg ? -0.0 : 0.0);
    return bf_round(bi_mul(tomato_int_from_u64((int64_t)m), bi(neg ? -1 : 1)), int_from_digits(e, (int64_t)strlen(e), &ok), 0);
}
static char result[1 << 16];
static void eval_show(int64_t w) {
    if (w == BF_NONE) { strcpy(result, "none"); return; }
    BigFloat b = bf_open(w);
    Str *e = tomato_int_str(b.e);
    if (b.m == 0) strcpy(result, signbit(b.m) ? "-0" : "0");
    else snprintf(result, sizeof result, "%s%llx:%s", b.m < 0 ? "-" : "", (unsigned long long)ldexp(fabs(b.m), 52), e->data);
    tomato_release(e); tomato_bf_free(w);
}
static void eval_text(Str *s) { snprintf(result, sizeof result, "%s", s->data); tomato_release(s); }
/* does what a line says: the operation and its operands. The result is MANTISSA:EXPONENT with the mantissa as 53 bits and the
 * exponent of its top bit, so 1.5 is 18000000000000:0 */
static int eval_line(char *line) {
    char *op = strtok(line, " \n"), *a = strtok(NULL, " \n"), *b = strtok(NULL, " \n"), *c = strtok(NULL, " \n");
    if (!strcmp(op, "read")) { eval_show(tomato_bf_literal(a)); return 1; }
    int64_t x = eval_float(a);
    if (!strcmp(op, "str")) eval_text(tomato_bf_str(x));
    else if (!strcmp(op, "round")) eval_show(tomato_bf_round(x, atoll(b), 0));
    else if (!strcmp(op, "format")) eval_text(tomato_bf_format(x, atoll(b), c[0]));
    else if (!strcmp(op, "math1")) eval_show(tomato_bf_math1(atoll(b), x, 0));
    else {
        int64_t y = eval_float(b);
        if (!strcmp(op, "add")) eval_show(tomato_bf_add(x, y, 0));
        else if (!strcmp(op, "mul")) eval_show(tomato_bf_mul(x, y, 0));
        else if (!strcmp(op, "div")) eval_show(tomato_bf_div(x, y, 0));
        else if (!strcmp(op, "mod")) eval_show(tomato_bf_mod(x, y, 0));
        else if (!strcmp(op, "pow")) eval_show(tomato_bf_pow(x, y, 0));
        else if (!strcmp(op, "check")) sprintf(result, "%d", (int)tomato_bf_pow_check(x, y));
        else if (!strcmp(op, "math2")) eval_show(tomato_bf_math2(atoll(c), x, y, 0));
        else { fprintf(stderr, "no operation '%s'\n", op); return 0; }
        tomato_bf_free(y);
    }
    tomato_bf_free(x);
    return 1;
}
static int eval(void) {
    static char line[1 << 20];
    while (fgets(line, sizeof line, stdin)) { if (!eval_line(line)) return 2; puts(result); }
    return live_bigs != 0;
}

/* Results computed with Python's decimal and fractions modules (140 digits), as --eval lines. The last ones are limits. */
static const char *const known[][2] = {
    { "mod 111e206b0d549b:539769209744951750095501 1fffffffffffff:785964202028698", "15526e23c40d61:785964202028750" },
    { "mod 13488f05e999f3:720742478599481663890697 12587b5c9bcf35:-1004107887971057", "10f6bc3f81140a:-1004107887971005" },
    { "mod 1ffffffffffffc:581841135758866873651156 10000000000003:297144916289151", "1c9d54419e2516:297144916289202" },
    { "mod 14363e00ed6b02:862167943407789325528597 1f600000000000:-25012499964441", "17000000000000:-25012499964391" },
    { "math1 10000000000002:-1 1", "1672c07a57ac44:3248660424278400" },
    { "math1 157ee0e00902c7:2 1", "10f30347e54797:34915983081671138" },
    { "math1 1ab2cde3151288:-41 17", "1347e4ea895058:4930" },
    { "math1 1ffffffffffffe:-39 12", "11558e956030ee:23636" },
    { "math1 10000000000002:0 17", "1f7ec8504bf6f2:6497320848556800" },
    { "math1 -1cda6cbd685167:-23 1", "185cb07a6ffc57:-1396750206" },
    { "math1 1ffffffffffffc:-40 1", "178d4cf9443f02:11818" },
    { "math1 -13640000000000:-16 11", "-1f9cd470ba2f9c:120150672986" },
    { "math1 10000000000002:-1 17", "1672c07a57ac44:3248660424278400" },
    { "math1 -1ffffffffffffd:-41 12", "13698232a51e39:5908" },
    { "math1 -1e9526d97e967b:-42 1", "12c540d26de53d:-2824" },
    { "math1 1ea596ed3a32a8:3 17", "19dd8855f32f15:99561157421634667" },
    { "math1 1ffffffffffffc:-862320 2", "-123d5be13fccde:19" },
    { "math1 1881edae2eb154:330455 3", "142c2e75eac312:18" },
    { "math1 1a580000000000:1084 15", "18a4db1bce5a9f:9" },
    { "math1 1fffffffffffff:-1171 4", "-1508d316861db2:8" },
    { "math1 19d00000000000:-85633523420008830 3", "-1303b3c6050915:56" },
    { "math1 1bb00000000000:-829646 2", "-118c6c632ee3fd:19" },
    { "math1 10000000000003:48952615377127865 18", "1e2319861b7dfe:54" },
    { "math1 1ffffffffffffe:810822 2", "11270f70a8a14f:19" },
    { "math1 1e200000000000:-231406 4", "-1100c3803eacdd:16" },
    { "math1 116c0000000000:839476 3", "199ed03ee34f99:19" },
    { "math1 -134b3fc26e7a42:525428 14", "-163b2f7172ff2f:18" },
    { "math1 1fffffffffffff:-162523473616232004 3", "-120b31e7c476f0:57" },
    { "pow 1ffffffffffffc:-1855 -1e8e250ed90475:-106", "10000000000254:0" },
    { "pow 1fffffffffffff:1464 1fffffffffffff:-12", "18bfb11c900013:3335918278672383" },
    { "pow 1ffffffffffffe:-57 -18ca8166d22876:-20", "174177fd98e823:26619173300" },
    { "pow 165e7e6472f1a3:1018351937528 130cbc0fef7928:-120", "10000000c3ac7e:0" },
    { "pow 1e883a5de00997:-116943636254 180b0cc7702420:-33", "11e363c1130a53:-92133621559222095" },
    { "pow 1a7299e8c14743:-727382204725 -10000000000003:-97", "103b1dff074a15:0" },
    { "pow 1988afd39630d6:-52 1218828c5c715f:-1", "11320217550af2:1717384747380978" },
    { "pow 1d58dc6b446806:-526126411647 1fffffffffffff:-36", "1d875e347ce86e:-68960441020465126" },
    { "pow 1ceaf4888564e8:-8841185382 -1e0400e064a114:-93", "10157849697f68:0" },
    { "pow 1e200000000000:-135430043413 10000000000003:-37", "1847597ce3425c:-4437771660823338" },
    { "pow 10000000000003:200248241948 -10000000000000:-93", "1e0ae7a909685b:-1" },
    { "pow 156d2a02f4b342:-909978050508 1fffffffffffff:-117", "1fffffeda48e50:-1" },
    { "pow 1fa6198d118e37:54 -10000000000003:-42", "13b98895e76be2:-109552" },
    { "pow 1fffffffffffff:579138840373 -19940000000000:-115", "1fffffdaa560db:-1" },
    { "str 10c5c7a6a3a450:-1122", "8.286754424630456e-323" },
    { "str -1ec66a95e761d1:10870", "-1.3604783099437678e+3288" },
    { "str 10000000000002:-3140", "2.6264757153343444e-930" },
    { "str 1ffffffffffffe:-1141", "3.015537389167764e-328" },
    { "str 1f480000000000:4426957972438366", "1.75878469392784e+1332647139247764" },
    { "str -10000000000000:6977892745035806", "-1.4910180342716721e+2100555022781870" },
    { "str 10000000000000:-1085", "1.0864618449742194e-311" },
    { "str 1ffffffffffffe:-19386", "1.5384869907193992e-5820" },
    { "read 7018159083e-681", "163ebc0d1eb718:-2230" },
    { "read 9033401e531", "10925fd3c786c2:1787" },
    { "read 287463319128452984153776020776e672", "1250b35007dcbc:2330" },
    { "read 654590454409103177646727204293557591836e-4664503738482553", "12932fed769b4f:-15495146017572198" },
    { "read 55624180578e-28409167937673468", "14e56bc011ea81:-94373213124530725" },
    { "read 592433721178155166160534468826372e-32448009095990462", "1d0730f873684d:-107789953039131292" },
    { "format 10c5c7a6a3a450:-2758 0 e", "3e-815" },
    { "format 1e000000000000:1555 0 g", "1e+484" },
    { "format 1ffffffffffffe:-2425 17 f", "0.00000000000000000" },
    { "format 19000000000000:-1302 0 f", "0" },
    { "format 17000000000000:2489 17 g", "1.1880284352687974e+765" },
    { "format 1b6246c8450070:-2056 0 e", "9e-604" },
    { "format 1c000000000000:-2864 1 f", "0.0" },
    { "format 17000000000000:-2495 6 g", "5.51224e-736" },
    { "format -1ffffffffffffd:-2034 6 g", "-4.56645e-597" },
    { "format -110755f5f554ed:-2958 2 f", "-0.00" },
    { "format 1d000000000000:-1213 0 f", "0" },
    { "format -1cd80000000000:-1589 37 f", "-0.0000000000000000000000000000000000000" },
    { "round 10c5c7a6a3a450:-2758 833", "10c5c7a6a3a450:-2706" },
    { "round -12000000000000:-2125 641", "-12000000000000:-2073" },
    { "round 1d000000000000:-1101 322", "1cffffe03b7de9:-1049" },
    { "round 10000000000002:1953 -574", "10000000000002:2005" },
    { "round -17000000000000:1150 -340", "-17000000000000:1202" },
    { "round 1ae80000000000:2579 -793", "0" },
    { "round 15000000000000:2028 -604", "15000000000000:2080" },
    { "round 19000000000000:2870 -875", "18fff320bf8428:2922" },
    /* powers halfway between two floats, cube roots the C library has wrong, digits that carry */
    { "pow 19:2000 17:-1", "152d02c7e14af6:23053" },
    { "pow 961:2000 13:-2", "143f9e0d2d93ec:9553" },
    { "pow 2386f26fc1:-6400 17:-4", "152d02c7e14af6:-9147" },
    { "pow 3:2000 22:0", "1d9fe779881944:68053" },
    { "pow 3:-2000 22:0", "1d9fe779881944:-67947" },
    { "pow 79:2000 f:-1", "1dae5ec28da7c6:15051" },
    { "pow d:1000 e:0", "1bfa0bc1a21bb2:14051" },
    { "math1 1ffffffffffffe:558676921510 19", "1fffffffffffff:186225640520" }, { "math1 -1ffffffffffffe:-639578497812 19", "-1965fea53d6e3c:-213192832587" },
    { "format 1b4ec7f91973ff:1276 3 e", "1.000e+400" }, { "format 1b4ec7f91973ff:1276 3 g", "1e+400" },
    { "format 16933d96533802:23201 3 e", "1.000e+7000" },
    /* limits: tiny and huge arguments of the math functions (5 sin .. 18 log1p, see tomato_math1) */
    { "math1 3:-2000 5", "18000000000000:-1999" }, { "math1 3:-2000 6", "10000000000000:0" }, { "math1 3:-2000 7", "18000000000000:-1999" },
    { "math1 -3:-2000 8", "-18000000000000:-1999" }, { "math1 3:-2000 9", "1921fb54442d18:0" }, { "math1 -3:-2000 10", "-18000000000000:-1999" },
    { "math1 3:-2000 11", "18000000000000:-1999" }, { "math1 3:-2000 12", "10000000000000:0" }, { "math1 3:-2000 13", "18000000000000:-1999" },
    { "math1 -3:-2000 14", "-18000000000000:-1999" }, { "math1 3:-2000 16", "18000000000000:-1999" }, { "math1 3:-2000 17", "18000000000000:-1999" },
    { "math1 3:-2000 18", "18000000000000:-1999" }, { "math1 -3:-2000 1", "10000000000000:0" }, { "math1 -3:2000 10", "-1921fb54442d18:0" },
    { "math1 -3:2000 13", "-10000000000000:0" }, { "math1 3:2000 13", "10000000000000:0" }, { "math1 -3:2000 17", "-10000000000000:0" },
    { "math1 1:3000 3", "17700000000000:11" }, { "math1 1:3000 19", "10000000000000:1000" }, { "math1 -1:-3000 19", "-10000000000000:-1000" },
    { "math2 3:2000 1:2000 1", "194c583ada5b53:2001" }, { "math2 3:2000 1:-2000 1", "18000000000000:2001" }, { "math2 0:0 -1:-2000 1", "10000000000000:-2000" },
    { "math2 1:-1074 1:-1074 1", "16a09e667f3bcd:-1074" }, { "math2 3:1023 3:1023 1", "10f876ccdf6cd9:1025" },
    { "math2 1:2000 1:2000 0", "1921fb54442d18:-1" }, { "math2 -1:2000 -1:2000 0", "-12d97c7f3321d2:1" }, { "math2 1:2000 1:-2000 0", "10000000000000:-4000" },
    { "math2 -1:2000 1:-2000 0", "1921fb54442d18:1" }, { "math2 1:-2000 -1:2000 0", "-1921fb54442d18:0" }, { "math2 0:0 1:2000 0", "1921fb54442d18:0" },
    { "math2 -1:2000 -0:0 0", "-1921fb54442d18:1" }, { "math2 1:1000 1:-1000 0", "10000000000000:-2000" },
    { "pow 1:1 1:10000", "10000000000000:@2^10000" }, { "pow -1:1 3:0", "-10000000000000:3" }, { "pow -3:2000 1:1", "12000000000000:4003" },
    { "pow -3:2000 -1:0", "-15555555555555:-2002" }, { "pow 1:0 1:2000", "10000000000000:0" }, { "pow -1:0 1:2000", "10000000000000:0" },
    { "pow 3:0 1:-2000", "10000000000000:0" }, { "pow 3:2000 0:0", "10000000000000:0" }, { "pow 0:0 1:2000", "0" }, { "pow -0:0 3:0", "-0" },
    { "pow 1:1 -433:0", "10000000000000:-1075" }, { "pow 1:1 -431:-1", "16a09e667f3bcd:-537" }, { "pow 1:2000 1:-1", "10000000000000:1000" }, { "pow 1:2000 -1:-3", "10000000000000:-250" },
    { "check 0:0 -1:0", "1" }, { "check 0:0 -1:2000", "1" }, { "check -0:0 1:-2000", "0" }, { "check -1:0 1:-1", "2" }, { "check -1:2000 1:-2000", "2" },
    { "check -1:2000 1:2000", "0" }, { "check -3:2000 -5:0", "0" }, { "check 3:2000 1:-1", "0" },
    { "round 1:-2000 5", "0" }, { "round -1:-2000 5", "-0" }, { "round 3:2000 5", "18000000000000:2001" }, { "round 3:2000 -2000", "0" },
    { "str 1:-1074", "4.9406564584124654e-324" }, { "str 0:0", "0.0" }, { "str -0:0", "-0.0" }, { "str 1:-1", "0.5" }, { "format 1:1024 0 g", "2e+308" }, { "format -1:-2000 2 f", "-0.00" },
    { NULL, NULL } };
#ifndef __wasi__
#include <sys/wait.h>
/* an operation that needs more memory than there can be stops the program with an error: checked in a child process */
static void test_too_big(void) {
    static const char *const cases[] = {
        "pow 10000000000000:-51 10000000000000:34359738316", "pow 3:0 10000000000000:34359738316", "math1 1:34359738316 1",
        "pow 10000000000000:-51 10000000000000:2147483640", NULL };
    for (int i = 0; cases[i]; i++) {
        what = cases[i];
        fflush(stdout); fflush(stderr);
        pid_t pid = fork();
        if (pid == 0) {
            char line[200];
            freopen("/dev/null", "w", stderr);
            strcpy(line, cases[i]);
            eval_line(line);
            _exit(0);
        }
        int status = 0;
        waitpid(pid, &status, 0);
        if (!WIFEXITED(status) || WEXITSTATUS(status) != 1) fail("did not stop with an error");
    }
}
#else
static void test_too_big(void) {}
#endif

static void test_known(void) {
    for (int i = 0; known[i][0]; i++) {
        char line[4000];
        what = known[i][0];
        strcpy(line, known[i][0]);
        eval_line(line);
        char *at = strchr(known[i][1], '@');                                /* the exponent is 2^10000 */
        if (at) {
            int64_t e = bi_one(10000), x = eval_float("1:1"), y = eval_float("1:10000"), r = tomato_bf_pow(x, y, 3);
            if (!bf_boxed(r) || bf_ptr(r)->m != 1 || tomato_int_cmp(bf_ptr(r)->e, e) != 0) fail("wrong");
            tomato_int_free(e); tomato_bf_free(r);
        } else if (strcmp(result, known[i][1])) { fail(result); fail(known[i][1]); }
    }
    what = "format, half to even";                                          /* 2^-1100 ends in ...25, 3 * 2^-1100 in ...75 */
    for (int i = 0; i < 2; i++) {
        char line[] = "format 1:-1100 1099 f";
        line[7] = (char)(i ? '3' : '1');
        eval_line(line);
        if (result[strlen(result) - 1] != (i ? '8' : '2')) fail("wrong last digit");
        sprintf(line, "format %d:-1100 %d e", 1 + 2 * i, 767 + i);
        eval_line(line);
        if (strchr(result, 'e')[-1] != (i ? '8' : '2')) fail("wrong last digit");
    }
    for (int i = 0; i < 2000; i++) {                                        /* doubles give what they gave */
        double x = ldexp((double)(int64_t)rnd(), (int)below(60) - 90), y = ldexp((double)(int64_t)rnd(), (int)below(10) - 68);
        int64_t op = below(20), a = bf_bits(x), b = bf_bits(y);
        double r = tomato_math1(op, x);
        what = "math1 of doubles";
        if (bf_normal(r) && tomato_bf_math1(op, a, 0) != bf_bits(r)) fail("not the C library's");
        what = "math2 of doubles";
        if (tomato_bf_math2(op & 1, a, b, 0) != bf_bits(tomato_math2(op & 1, x, y))) fail("not the C library's");
        what = "pow of doubles";
        if (tomato_bf_pow(bf_bits(fabs(x)), b, 0) != bf_bits(pow(fabs(x), y))) fail("not the C library's");
        what = "mod and floordiv of doubles";
        if (tomato_bf_mod(a, b, 0) != bf_bits(tomato_mod_f64(x, y)) || tomato_bf_floordiv(a, b, 0) != bf_bits(tomato_floor_div_f64(x, y))) fail("changed");
        Str *s = tomato_bf_str(a), *t = tomato_str_from_f64(x);
        what = "text of doubles";
        if (strcmp(s->data, t->data)) fail(s->data);
        tomato_release(s); tomato_release(t);
    }
}

/* A copied container must own an independent box, and every destruction path must free it. */
static void test_container_ownership(void) {
    what = "container ownership";
    List *a = tomato_list_new(6);
    *(int64_t *)tomato_list_push(a, 8) = tomato_bf_literal("1e400");
    List *b = tomato_list_slice(a, 0, 1, 1, 0, 3);
    List *c = tomato_list_concat(a, b, 3);
    List *repeat = tomato_list_repeat(a, 2, 3);
    tomato_list_extend(repeat, a, 3);
    tomato_release(a);
    if (tomato_bf_cmp(LIST_SLOT(b, 0, int64_t), LIST_SLOT(c, 0, int64_t), 0) != 0) fail("slice or concat copy");
    if (repeat->len != 3 || tomato_bf_cmp(LIST_SLOT(b, 0, int64_t), LIST_SLOT(repeat, 2, int64_t), 0) != 0) fail("repeat or extend copy");
    tomato_release(b);
    tomato_release(c);
    tomato_release(repeat);

    Dict *d = tomato_dict_new(7, 8, 0);
    *(int64_t *)tomato_dict_insert(d, 42, 0) = tomato_bf_literal("1e400");
    List *values = tomato_dict_values(d, 6, 8, 3);
    tomato_release(d);
    if (!tomato_bf_is_boxed(LIST_SLOT(values, 0, int64_t))) fail("dictionary value copy");
    tomato_release(values);

    Hdr *obj = tomato_alloc(24, 5);
    *(int64_t *)((char *)obj + 16) = tomato_bf_literal("1e400");
    tomato_release(obj);
    /* Cycle collection uses free_internals instead of destroy_one. */
    obj = tomato_alloc(24, 5);
    *(int64_t *)((char *)obj + 16) = tomato_bf_literal("1e400");
    free_internals(obj);
    *(int64_t *)((char *)obj + 16) = 0;
    tomato_release(obj);
}

int main(int argc, char **argv) {
    if (argc > 1 && !strcmp(argv[1], "--eval")) return eval();
    int64_t rounds = argc > 1 ? atoll(argv[1]) : 2000;
    if (argc > 2) seed = strtoull(argv[2], NULL, 10);
    test_fixed();
    test_text_fixed();
    test_known();
    test_too_big();
    test_container_ownership();
    for (int64_t i = 0; i < rounds; i++) { test_arithmetic(); test_ints(); if (i % 8 == 0) { test_print(); test_parse(); test_pow(); } if (i % 256 == 0) { test_round_trip((int)below(200)); test_round_trip(4000 + (int)below(200)); } }
    what = "memory";
    if (live_bigs != 0) fail("big numbers were never freed");
    if (failures) { fprintf(stderr, "%d failures\n", failures); return 1; }
    puts("ok");
    return 0;
}
