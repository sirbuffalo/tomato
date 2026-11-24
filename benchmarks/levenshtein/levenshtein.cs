// Benchmark: edit distance (Levenshtein) by dynamic programming. Makes two pseudo-random strings of n letters (a..d) with a
// linear congruential generator and fills the table row by row (two rows kept). Prints the distance.
using System;
using System.Text;

static class Program {
    static void Main(string[] args) {
        int n = int.Parse(args[0]);
        long seed = 42;
        string letters = "abcd";
        var firstParts = new StringBuilder();
        var secondParts = new StringBuilder();
        for (int i = 0; i < n; i++) {
            seed = (seed * 1103515245L + 12345) % 2147483648L;
            firstParts.Append(letters[(int)(seed / 65536 % 4)]);
            seed = (seed * 1103515245L + 12345) % 2147483648L;
            secondParts.Append(letters[(int)(seed / 65536 % 4)]);
        }
        string s = firstParts.ToString();
        string t = secondParts.ToString();
        long[] prev = new long[n + 1];
        for (int i = 0; i <= n; i++) prev[i] = i;
        long[] cur = new long[n + 1];
        for (int i = 1; i <= n; i++) {
            cur[0] = i;
            char si = s[i - 1];
            for (int j = 1; j <= n; j++) {
                long cost = 1;
                if (si == t[j - 1]) cost = 0;
                long best = prev[j - 1] + cost;
                long up = prev[j] + 1;
                if (up < best) best = up;
                long left = cur[j - 1] + 1;
                if (left < best) best = left;
                cur[j] = best;
            }
            long[] swap = prev;
            prev = cur;
            cur = swap;
        }
        Console.WriteLine(prev[n]);
    }
}
