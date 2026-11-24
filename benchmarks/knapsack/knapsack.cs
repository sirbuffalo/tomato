// Benchmark: 0/1 knapsack by dynamic programming over one row of capacities. n items with pseudo-random weights (1..60) and
// values (1..1000) from a linear congruential generator, capacity 5 * n. Prints the best total value.
using System;

static class Program {
    static void Main(string[] args) {
        int n = int.Parse(args[0]);
        long seed = 7;
        int[] weights = new int[n];
        long[] values = new long[n];
        for (int i = 0; i < n; i++) {
            seed = (seed * 1103515245L + 12345) % 2147483648L;
            weights[i] = (int)(seed / 65536 % 60 + 1);
            seed = (seed * 1103515245L + 12345) % 2147483648L;
            values[i] = seed / 65536 % 1000 + 1;
        }
        int capacity = 5 * n;
        long[] best = new long[capacity + 1];
        for (int i = 0; i < n; i++) {
            int w = weights[i];
            long v = values[i];
            for (int c = capacity; c >= w; c--) {
                long candidate = best[c - w] + v;
                if (candidate > best[c]) best[c] = candidate;
            }
        }
        Console.WriteLine(best[capacity]);
    }
}
