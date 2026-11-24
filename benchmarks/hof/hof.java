// Benchmark: function values. Calls one of four functions chosen from an array n times (each result feeds the next), then
// runs map and filter with lambdas and sorts with a key function over a list of n / 4 numbers. Prints three checksums.
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.function.LongUnaryOperator;

class hof {
    static long f0(long x) { return (x * 3 + 1) % 1000003; }
    static long f1(long x) { return (x + 7919) % 1000003; }
    static long f2(long x) { return x * x % 1000003; }
    static long f3(long x) { return (x ^ 12345) % 1000003; }

    static long applyTwice(LongUnaryOperator f, long x) {
        return f.applyAsLong(f.applyAsLong(x));
    }

    public static void main(String[] args) {
        long n = Long.parseLong(args[0]);
        LongUnaryOperator[] table = {hof::f0, hof::f1, hof::f2, hof::f3};
        long x = 1;
        for (long i = 0; i < n; i++) x = table[(int) (i % 4)].applyAsLong(x + i);
        System.out.println(x);
        long y = 0;
        for (long i = 0; i < n; i++) y = (y + applyTwice(table[(int) (i % 4)], i)) % 1000000007L;
        System.out.println(y);
        int m = (int) (n / 4);
        List<Long> odd = new ArrayList<>();
        for (int i = 0; i < m; i++) {
            long v = (long) i * 7919 % 100003;
            long sq = v * v % 1009;
            if (sq % 2 == 1) odd.add(sq);
        }
        LongUnaryOperator key = v -> v % 997 * 1000 + v % 1000;
        odd.sort(Comparator.comparingLong(v -> key.applyAsLong(v)));  // List.sort is stable
        long z = 0;
        for (int i = 0; i < odd.size(); i++) z = (z * 31 + odd.get(i)) % 1000000007L;
        System.out.println(odd.size() + " " + z);
    }
}
