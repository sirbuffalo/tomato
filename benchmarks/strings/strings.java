// Benchmark: text building and parsing. Joins n numbers into one comma-separated string, splits it and adds them up.
// Prints the text length and the sum.
class strings {
    public static void main(String[] args) {
        int n = Integer.parseInt(args[0]);
        String[] parts = new String[n];
        for (int i = 0; i < n; i++) parts[i] = String.valueOf(i * 7 % 1000);
        String text = String.join(",", parts);
        long total = 0;
        for (String piece : text.split(",")) total += Integer.parseInt(piece);
        System.out.println(text.length() + " " + total);
    }
}
