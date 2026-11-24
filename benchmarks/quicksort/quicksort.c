// Benchmark: a hand-written quicksort (recursive, Hoare partition, middle pivot, insertion sort for short ranges) on n
// pseudo-random integers from a linear congruential generator. Prints a position-weighted checksum of the sorted array.
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

static void insertion_sort(int64_t *values, int64_t low, int64_t high) {
    for (int64_t i = low + 1; i <= high; i++) {
        int64_t x = values[i], j = i - 1;
        while (j >= low && values[j] > x) {
            values[j + 1] = values[j];
            j--;
        }
        values[j + 1] = x;
    }
}

static void quicksort(int64_t *values, int64_t low, int64_t high) {
    while (high - low > 16) {
        int64_t pivot = values[(low + high) / 2], i = low, j = high;
        while (i <= j) {
            while (values[i] < pivot) i++;
            while (values[j] > pivot) j--;
            if (i <= j) {
                int64_t t = values[i];
                values[i] = values[j];
                values[j] = t;
                i++;
                j--;
            }
        }
        // recurse into the smaller part, loop on the larger one
        if (j - low < high - i) {
            quicksort(values, low, j);
            low = i;
        } else {
            quicksort(values, i, high);
            high = j;
        }
    }
    insertion_sort(values, low, high);
}

int main(int argc, char **argv) {
    (void)argc;
    int64_t n = atoll(argv[1]), seed = 12345;
    int64_t *values = malloc((size_t)n * sizeof *values);
    for (int64_t i = 0; i < n; i++) {
        seed = (seed * 1103515245 + 12345) % 2147483648;
        values[i] = seed;
    }
    quicksort(values, 0, n - 1);
    int64_t checksum = 0;
    for (int64_t i = 0; i < n; i++) checksum = (checksum + (i % 1000 + 1) * values[i]) % 1000000007;
    printf("%lld\n", (long long)checksum);
    free(values);
}
