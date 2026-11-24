// Benchmark: objects and method calls. Makes n particles, steps each one 10 times, prints the sum of their positions.
using System;
using System.Collections.Generic;

class Particle {
    public long X, V;

    public Particle(long x, long v) {
        X = x;
        V = v;
    }

    public void Step(long round) {
        X = (X + V * round) % 1000003;
    }
}

static class Program {
    static void Main(string[] args) {
        int n = int.Parse(args[0]);
        var particles = new List<Particle>();
        for (int i = 0; i < n; i++) particles.Add(new Particle(i, i % 13 + 1));
        for (int round = 1; round <= 10; round++) {
            foreach (Particle p in particles) p.Step(round);
        }
        long total = 0;
        foreach (Particle p in particles) total += p.X;
        Console.WriteLine(total);
    }
}
