// Benchmark: sieve of Eratosthenes. Prints how many primes are <= n.
class sieve {
    public static void main(String[] args) {
        int n = Integer.parseInt(args[0]);
        boolean[] composite = new boolean[n + 1];
        int count = 0;
        for (int i = 2; i <= n; i++) {
            if (composite[i]) continue;
            count++;
            for (long j = (long) i * i; j <= n; j += i) composite[(int) j] = true;
        }
        System.out.println(count);
    }
}
