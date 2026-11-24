// Benchmark: function values. Calls one of four functions chosen from an array n times (each result feeds the next), then
// runs map and filter with callbacks and sorts with a key function over an array of n / 4 numbers. Prints three checksums.
// The C library has no map or filter, so those are small loops over function pointers; the sort is a stable one (qsort is
// not stable, so equal keys are ordered by position).
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

typedef int64_t (*Fn)(int64_t);

static int64_t f0(int64_t x) { return (x * 3 + 1) % 1000003; }
static int64_t f1(int64_t x) { return (x + 7919) % 1000003; }
static int64_t f2(int64_t x) { return x * x % 1000003; }
static int64_t f3(int64_t x) { return (x ^ 12345) % 1000003; }

static int64_t apply_twice(Fn f, int64_t x) { return f(f(x)); }

static int64_t square_mod(int64_t v) { return v * v % 1009; }
static int64_t sort_key(int64_t v) { return v % 997 * 1000 + v % 1000; }
static int is_odd(int64_t v) { return v % 2 == 1; }

typedef struct { int64_t key, value, index; } Keyed;

static int compare(const void *a, const void *b) {
    const Keyed *x = a, *y = b;
    if (x->key != y->key) return x->key < y->key ? -1 : 1;
    return (x->index > y->index) - (x->index < y->index);
}

int main(int argc, char **argv) {
    (void)argc;
    int64_t n = atoll(argv[1]);
    Fn table[4] = {f0, f1, f2, f3};
    int64_t x = 1;
    for (int64_t i = 0; i < n; i++) x = table[i % 4](x + i);
    printf("%lld\n", (long long)x);
    int64_t y = 0;
    for (int64_t i = 0; i < n; i++) y = (y + apply_twice(table[i % 4], i)) % 1000000007;
    printf("%lld\n", (long long)y);
    int64_t m = n / 4;
    int64_t *xs = malloc((size_t)(m + 1) * sizeof *xs), *squares = malloc((size_t)(m + 1) * sizeof *squares);
    Keyed *odd = malloc((size_t)(m + 1) * sizeof *odd);
    for (int64_t i = 0; i < m; i++) xs[i] = i * 7919 % 100003;
    for (int64_t i = 0; i < m; i++) squares[i] = square_mod(xs[i]);
    int64_t count = 0;
    for (int64_t i = 0; i < m; i++)
        if (is_odd(squares[i])) {
            odd[count].value = squares[i];
            odd[count].key = sort_key(squares[i]);
            odd[count].index = count;
            count++;
        }
    qsort(odd, (size_t)count, sizeof *odd, compare);
    int64_t z = 0;
    for (int64_t i = 0; i < count; i++) z = (z * 31 + odd[i].value) % 1000000007;
    printf("%lld %lld\n", (long long)count, (long long)z);
    free(xs);
    free(squares);
    free(odd);
}
