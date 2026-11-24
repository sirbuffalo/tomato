// Benchmark: k-nucleotide counting. Makes a pseudo-random DNA string of n letters (A, C, G, T) with a linear congruential
// generator, then counts every substring of length 1, 2, 4, 6 and 12 in a hash map. For each length prints the number of
// different substrings, the highest count and the sum of the squares of the counts.
import java.util.HashMap;

class kmers {
    public static void main(String[] args) {
        int n = Integer.parseInt(args[0]);
        long seed = 31337;
        String letters = "ACGT";
        StringBuilder parts = new StringBuilder();
        for (int i = 0; i < n; i++) {
            seed = (seed * 1103515245L + 12345) % 2147483648L;
            parts.append(letters.charAt((int) (seed / 65536 % 4)));
        }
        String dna = parts.toString();
        for (int k : new int[] {1, 2, 4, 6, 12}) {
            HashMap<String, Long> counts = new HashMap<>();
            for (int i = 0; i < n - k + 1; i++) {
                String key = dna.substring(i, i + k);
                counts.put(key, counts.getOrDefault(key, 0L) + 1);
            }
            long most = 0;
            long squares = 0;
            for (long c : counts.values()) {
                if (c > most) most = c;
                squares += c * c;
            }
            System.out.println(k + " " + counts.size() + " " + most + " " + squares);
        }
    }
}
