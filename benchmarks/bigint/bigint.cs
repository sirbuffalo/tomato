// Benchmark: big integers. Computes n! by multiplying one small number at a time. Prints n! mod 1000000007.
using System;
using System.Numerics;

static class Program {
    static void Main(string[] args) {
        int n = int.Parse(args[0]);
        BigInteger product = BigInteger.One;
        for (int i = 2; i <= n; i++) product *= i;
        Console.WriteLine(product % 1000000007);
    }
}
