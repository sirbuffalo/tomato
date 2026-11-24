// Benchmark: text building and parsing. Joins n numbers into one comma-separated string, splits it and adds them up.
// Prints the text length and the sum.
using System;

static class Program {
    static void Main(string[] args) {
        int n = int.Parse(args[0]);
        string[] parts = new string[n];
        for (int i = 0; i < n; i++) parts[i] = (i * 7 % 1000).ToString();
        string text = string.Join(",", parts);
        long total = 0;
        foreach (string piece in text.Split(',')) total += int.Parse(piece);
        Console.WriteLine($"{text.Length} {total}");
    }
}
