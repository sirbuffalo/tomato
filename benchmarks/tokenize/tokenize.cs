// Benchmark: a hand-written tokenizer (no regular expressions). Makes n pseudo-random tokens of source-like text (names,
// whole numbers and punctuation), joins them, then scans the text one character at a time and classifies the tokens.
// Prints the number of names, numbers and symbols, the sum of the numbers and the total length of the names.
using System;
using System.Text;

static class Program {
    static void Main(string[] args) {
        int n = int.Parse(args[0]);
        long seed = 555;
        string[] words = { "alpha", "beta", "gamma", "delta", "count", "total", "index", "value" };
        string[] symbols = { "+", "-", "*", "/", "=", "(", ")", ";" };
        var pieces = new StringBuilder();
        for (int i = 0; i < n; i++) {
            seed = (seed * 1103515245L + 12345) % 2147483648L;
            long kind = seed / 65536 % 4;
            seed = (seed * 1103515245L + 12345) % 2147483648L;
            long pick = seed / 65536;
            if (kind == 0) pieces.Append(words[(int)(pick % 8)]).Append(' ');
            else if (kind == 1) pieces.Append(pick % 100000).Append(' ');
            else if (kind == 2) pieces.Append(symbols[(int)(pick % 8)]);
            else pieces.Append(words[(int)(pick % 8)]).Append(pick / 8 % 100).Append(' ');
        }
        string text = pieces.ToString();
        long names = 0, numbers = 0, syms = 0, numberSum = 0, nameLength = 0;
        bool inName = false, inNumber = false;
        long value = 0;
        for (int p = 0; p < text.Length; p++) {
            char ch = text[p];
            bool alpha = (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z');
            bool digit = ch >= '0' && ch <= '9';
            if (alpha || (inName && digit)) {
                if (!inName) {
                    inName = true;
                    names++;
                }
                nameLength++;
            } else if (digit) {
                if (!inNumber) {
                    inNumber = true;
                    numbers++;
                    value = 0;
                }
                value = value * 10 + ch - 48;
            } else {
                if (inNumber) numberSum += value;
                inName = false;
                inNumber = false;
                if (ch != ' ') syms++;
            }
        }
        if (inNumber) numberSum += value;
        Console.WriteLine($"{names} {numbers} {syms} {numberSum} {nameLength}");
    }
}
