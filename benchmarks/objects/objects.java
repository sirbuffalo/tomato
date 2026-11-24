// Benchmark: objects and method calls. Makes n particles, steps each one 10 times, prints the sum of their positions.
import java.util.ArrayList;

class objects {
    static class Particle {
        long x, v;

        Particle(long x, long v) {
            this.x = x;
            this.v = v;
        }

        void step(long round) {
            x = (x + v * round) % 1000003;
        }
    }

    public static void main(String[] args) {
        int n = Integer.parseInt(args[0]);
        ArrayList<Particle> particles = new ArrayList<>();
        for (int i = 0; i < n; i++) particles.add(new Particle(i, i % 13 + 1));
        for (int round = 1; round <= 10; round++) {
            for (Particle p : particles) p.step(round);
        }
        long total = 0;
        for (Particle p : particles) total += p.x;
        System.out.println(total);
    }
}
