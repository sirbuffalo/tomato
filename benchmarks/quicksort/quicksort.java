// Benchmark: a hand-written quicksort (recursive, Hoare partition, middle pivot, insertion sort for short ranges) on n
// pseudo-random integers from a linear congruential generator. Prints a position-weighted checksum of the sorted array.
class quicksort {
    static void insertionSort(long[] values, int low, int high) {
        for (int i = low + 1; i <= high; i++) {
            long x = values[i];
            int j = i - 1;
            while (j >= low && values[j] > x) {
                values[j + 1] = values[j];
                j--;
            }
            values[j + 1] = x;
        }
    }

    static void quicksort(long[] values, int low, int high) {
        while (high - low > 16) {
            long pivot = values[(low + high) / 2];
            int i = low;
            int j = high;
            while (i <= j) {
                while (values[i] < pivot) i++;
                while (values[j] > pivot) j--;
                if (i <= j) {
                    long t = values[i];
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
        insertionSort(values, low, high);
    }

    public static void main(String[] args) {
        int n = Integer.parseInt(args[0]);
        long seed = 12345;
        long[] values = new long[n];
        for (int i = 0; i < n; i++) {
            seed = (seed * 1103515245L + 12345) % 2147483648L;
            values[i] = seed;
        }
        quicksort(values, 0, n - 1);
        long checksum = 0;
        for (int i = 0; i < n; i++) checksum = (checksum + (i % 1000 + 1) * values[i]) % 1000000007L;
        System.out.println(checksum);
    }
}
