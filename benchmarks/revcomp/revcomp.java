// Benchmark: reverse complement of DNA text. Makes a pseudo-random sequence of n letters (A, C, G, T) with a linear
// congruential generator, writes it as FASTA lines of 60 letters, reads the lines back, joins them, builds the reverse
// complement, and wraps it again. Prints the number of lines and a checksum over every 7th letter of the result.
import java.util.ArrayList;

class revcomp {
    static char complement(char c) {
        switch (c) {
            case 'A': return 'T';
            case 'C': return 'G';
            case 'G': return 'C';
            default: return 'A';
        }
    }

    public static void main(String[] args) {
        int n = Integer.parseInt(args[0]);
        long seed = 2718;
        String letters = "ACGT";
        StringBuilder parts = new StringBuilder();
        for (int i = 0; i < n; i++) {
            seed = (seed * 1103515245L + 12345) % 2147483648L;
            parts.append(letters.charAt((int) (seed / 65536 % 4)));
        }
        String dna = parts.toString();
        ArrayList<String> lines = new ArrayList<>();
        for (int start = 0; start < n; start += 60) lines.add(dna.substring(start, Math.min(start + 60, n)));
        StringBuilder joined = new StringBuilder();
        for (String line : lines) joined.append(line);
        String text = joined.toString();
        StringBuilder out = new StringBuilder();
        for (int i = text.length() - 1; i >= 0; i--) out.append(complement(text.charAt(i)));
        String rc = out.toString();
        ArrayList<String> wrapped = new ArrayList<>();
        for (int start = 0; start < rc.length(); start += 60) wrapped.add(rc.substring(start, Math.min(start + 60, rc.length())));
        long checksum = 0;
        for (String line : wrapped) {
            for (int k = 0; k < line.length(); k += 7) checksum = (checksum * 131 + line.charAt(k)) % 1000000007L;
        }
        System.out.println(wrapped.size() + " " + checksum);
    }
}
