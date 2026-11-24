// Benchmark: sort n pseudo-random integers (a linear congruential generator). Prints a position-weighted checksum.
import java.util.Arrays;

class sort {
    public static void main(String[] args) {
        int n = Integer.parseInt(args[0]);
        long seed = 12345;
        long[] values = new long[n];
        for (int i = 0; i < n; i++) {
            seed = (seed * 1103515245L + 12345) % 2147483648L;
            values[i] = seed;
        }
        Arrays.sort(values);
        long checksum = 0;
        for (int i = 0; i < n; i++) checksum = (checksum + (i % 1000 + 1) * values[i]) % 1000000007L;
        System.out.println(checksum);
    }
}
