// Benchmark: word counting in a HashMap. Counts n generated words ("w0".."w5002"), then prints a weighted checksum.
import java.util.HashMap;

class wordcount {
    public static void main(String[] args) {
        long n = Long.parseLong(args[0]);
        HashMap<String, Long> counts = new HashMap<>();
        for (long i = 0; i < n; i++) {
            String word = "w" + (i * 7919 % 5003);
            counts.put(word, counts.getOrDefault(word, 0L) + 1);
        }
        long checksum = 0;
        for (int k = 0; k < 5003; k++) checksum += (k + 1) * counts.getOrDefault("w" + k, 0L);
        System.out.println(counts.size() + " " + checksum);
    }
}
