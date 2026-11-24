// Benchmark: sieve of Eratosthenes. Prints how many primes are <= n.
using System;

static class Program {
    static void Main(string[] args) {
        int n = int.Parse(args[0]);
        bool[] composite = new bool[n + 1];
        int count = 0;
        for (int i = 2; i <= n; i++) {
            if (composite[i]) continue;
            count++;
            for (long j = (long)i * i; j <= n; j += i) composite[j] = true;
        }
        Console.WriteLine(count);
    }
}
