// Benchmark: k-nucleotide counting. Makes a pseudo-random DNA string of n letters (A, C, G, T) with a linear congruential
// generator, then counts every substring of length 1, 2, 4, 6 and 12 in a Dictionary. For each length prints the number of
// different substrings, the highest count and the sum of the squares of the counts.
using System;
using System.Collections.Generic;
using System.Text;

static class Program {
    static void Main(string[] args) {
        int n = int.Parse(args[0]);
        long seed = 31337;
        string letters = "ACGT";
        var parts = new StringBuilder();
        for (int i = 0; i < n; i++) {
            seed = (seed * 1103515245L + 12345) % 2147483648L;
            parts.Append(letters[(int)(seed / 65536 % 4)]);
        }
        string dna = parts.ToString();
        foreach (int k in new int[] { 1, 2, 4, 6, 12 }) {
            var counts = new Dictionary<string, long>();
            for (int i = 0; i < n - k + 1; i++) {
                string key = dna.Substring(i, k);
                counts.TryGetValue(key, out long count);
                counts[key] = count + 1;
            }
            long most = 0;
            long squares = 0;
            foreach (long c in counts.Values) {
                if (c > most) most = c;
                squares += c * c;
            }
            Console.WriteLine($"{k} {counts.Count} {most} {squares}");
        }
    }
}
