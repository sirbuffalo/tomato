// Benchmark: sort n pseudo-random integers (a linear congruential generator). Prints a position-weighted checksum.
using System;

static class Program {
    static void Main(string[] args) {
        int n = int.Parse(args[0]);
        long seed = 12345;
        long[] values = new long[n];
        for (int i = 0; i < n; i++) {
            seed = (seed * 1103515245 + 12345) % 2147483648;
            values[i] = seed;
        }
        Array.Sort(values);
        long checksum = 0;
        for (int i = 0; i < n; i++) checksum = (checksum + (i % 1000 + 1) * values[i]) % 1000000007;
        Console.WriteLine(checksum);
    }
}
