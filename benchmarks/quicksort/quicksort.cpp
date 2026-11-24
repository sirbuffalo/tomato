// Benchmark: a hand-written quicksort (recursive, Hoare partition, middle pivot, insertion sort for short ranges) on n
// pseudo-random integers from a linear congruential generator. Prints a position-weighted checksum of the sorted vector.
#include <cstdint>
#include <iostream>
#include <string>
#include <vector>

static void insertion_sort(std::vector<std::int64_t> &values, std::int64_t low, std::int64_t high) {
    for (std::int64_t i = low + 1; i <= high; i++) {
        std::int64_t x = values[i], j = i - 1;
        while (j >= low && values[j] > x) {
            values[j + 1] = values[j];
            j--;
        }
        values[j + 1] = x;
    }
}

static void quicksort(std::vector<std::int64_t> &values, std::int64_t low, std::int64_t high) {
    while (high - low > 16) {
        std::int64_t pivot = values[(low + high) / 2], i = low, j = high;
        while (i <= j) {
            while (values[i] < pivot) i++;
            while (values[j] > pivot) j--;
            if (i <= j) {
                std::swap(values[i], values[j]);
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

int main(int, char **argv) {
    std::int64_t n = std::stoll(argv[1]), seed = 12345;
    std::vector<std::int64_t> values(n);
    for (std::int64_t i = 0; i < n; i++) {
        seed = (seed * 1103515245 + 12345) % 2147483648;
        values[i] = seed;
    }
    quicksort(values, 0, n - 1);
    std::int64_t checksum = 0;
    for (std::int64_t i = 0; i < n; i++) checksum = (checksum + (i % 1000 + 1) * values[i]) % 1000000007;
    std::cout << checksum << '\n';
}
