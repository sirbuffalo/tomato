// Benchmark: longest Collatz chain for a start below n, no caching. Prints the start and the chain length.
using System;

static class Program {
    static void Main(string[] args) {
        long n = long.Parse(args[0]);
        long bestStart = 1;
        long bestLength = 1;
        for (long start = 1; start < n; start++) {
            long x = start;
            long length = 1;
            while (x != 1) {
                if (x % 2 == 0) x /= 2;
                else x = 3 * x + 1;
                length++;
            }
            if (length > bestLength) {
                bestLength = length;
                bestStart = start;
            }
        }
        Console.WriteLine($"{bestStart} {bestLength}");
    }
}
