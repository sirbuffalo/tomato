// Benchmark: reverse complement of DNA text. Makes a pseudo-random sequence of n letters (A, C, G, T) with a linear
// congruential generator, writes it as FASTA lines of 60 letters, reads the lines back, joins them, builds the reverse
// complement, and wraps it again. Prints the number of lines and a checksum over every 7th letter of the result.
using System;
using System.Collections.Generic;
using System.Text;

static class Program {
    static char Complement(char c) {
        switch (c) {
            case 'A': return 'T';
            case 'C': return 'G';
            case 'G': return 'C';
            default: return 'A';
        }
    }

    static void Main(string[] args) {
        int n = int.Parse(args[0]);
        long seed = 2718;
        string letters = "ACGT";
        var parts = new StringBuilder();
        for (int i = 0; i < n; i++) {
            seed = (seed * 1103515245L + 12345) % 2147483648L;
            parts.Append(letters[(int)(seed / 65536 % 4)]);
        }
        string dna = parts.ToString();
        var lines = new List<string>();
        for (int start = 0; start < n; start += 60) lines.Add(dna.Substring(start, Math.Min(60, n - start)));
        var joined = new StringBuilder();
        foreach (string line in lines) joined.Append(line);
        string text = joined.ToString();
        var output = new StringBuilder();
        for (int i = text.Length - 1; i >= 0; i--) output.Append(Complement(text[i]));
        string rc = output.ToString();
        var wrapped = new List<string>();
        for (int start = 0; start < rc.Length; start += 60) wrapped.Add(rc.Substring(start, Math.Min(60, rc.Length - start)));
        long checksum = 0;
        foreach (string line in wrapped) {
            for (int k = 0; k < line.Length; k += 7) checksum = (checksum * 131 + line[k]) % 1000000007L;
        }
        Console.WriteLine($"{wrapped.Count} {checksum}");
    }
}
