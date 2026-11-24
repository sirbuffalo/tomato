// Benchmark: word counting in a Dictionary. Counts n generated words ("w0".."w5002"), then prints a weighted checksum.
using System;
using System.Collections.Generic;

static class Program {
    static void Main(string[] args) {
        long n = long.Parse(args[0]);
        var counts = new Dictionary<string, long>();
        for (long i = 0; i < n; i++) {
            string word = $"w{i * 7919 % 5003}";
            counts.TryGetValue(word, out long count);
            counts[word] = count + 1;
        }
        long checksum = 0;
        for (int k = 0; k < 5003; k++) {
            counts.TryGetValue($"w{k}", out long count);
            checksum += (k + 1) * count;
        }
        Console.WriteLine($"{counts.Count} {checksum}");
    }
}
