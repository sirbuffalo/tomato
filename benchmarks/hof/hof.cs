// Benchmark: function values. Calls one of four functions chosen from an array n times (each result feeds the next), then
// runs map and filter with lambdas and sorts with a key function over a list of n / 4 numbers. Prints three checksums.
using System;
using System.Collections.Generic;
using System.Linq;

static class Program {
    static long F0(long x) { return (x * 3 + 1) % 1000003; }
    static long F1(long x) { return (x + 7919) % 1000003; }
    static long F2(long x) { return x * x % 1000003; }
    static long F3(long x) { return (x ^ 12345) % 1000003; }

    static long ApplyTwice(Func<long, long> f, long x) {
        return f(f(x));
    }

    static void Main(string[] args) {
        long n = long.Parse(args[0]);
        Func<long, long>[] table = { F0, F1, F2, F3 };
        long x = 1;
        for (long i = 0; i < n; i++) x = table[(int)(i % 4)](x + i);
        Console.WriteLine(x);
        long y = 0;
        for (long i = 0; i < n; i++) y = (y + ApplyTwice(table[(int)(i % 4)], i)) % 1000000007L;
        Console.WriteLine(y);
        int m = (int)(n / 4);
        var odd = new List<long>();
        for (int i = 0; i < m; i++) {
            long v = (long)i * 7919 % 100003;
            long sq = v * v % 1009;
            if (sq % 2 == 1) odd.Add(sq);
        }
        Func<long, long> key = v => v % 997 * 1000 + v % 1000;
        var ordered = odd.OrderBy(key).ToList();  // OrderBy is stable
        long z = 0;
        for (int i = 0; i < ordered.Count; i++) z = (z * 31 + ordered[i]) % 1000000007L;
        Console.WriteLine($"{ordered.Count} {z}");
    }
}
