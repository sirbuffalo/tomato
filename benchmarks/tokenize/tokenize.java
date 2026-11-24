// Benchmark: a hand-written tokenizer (no regular expressions). Makes n pseudo-random tokens of source-like text (names,
// whole numbers and punctuation), joins them, then scans the text one character at a time and classifies the tokens.
// Prints the number of names, numbers and symbols, the sum of the numbers and the total length of the names.
class tokenize {
    public static void main(String[] args) {
        int n = Integer.parseInt(args[0]);
        long seed = 555;
        String[] words = {"alpha", "beta", "gamma", "delta", "count", "total", "index", "value"};
        String[] symbols = {"+", "-", "*", "/", "=", "(", ")", ";"};
        StringBuilder pieces = new StringBuilder();
        for (int i = 0; i < n; i++) {
            seed = (seed * 1103515245L + 12345) % 2147483648L;
            long kind = seed / 65536 % 4;
            seed = (seed * 1103515245L + 12345) % 2147483648L;
            long pick = seed / 65536;
            if (kind == 0) pieces.append(words[(int) (pick % 8)]).append(' ');
            else if (kind == 1) pieces.append(pick % 100000).append(' ');
            else if (kind == 2) pieces.append(symbols[(int) (pick % 8)]);
            else pieces.append(words[(int) (pick % 8)]).append(pick / 8 % 100).append(' ');
        }
        String text = pieces.toString();
        long names = 0, numbers = 0, syms = 0, numberSum = 0, nameLength = 0;
        boolean inName = false, inNumber = false;
        long value = 0;
        for (int p = 0; p < text.length(); p++) {
            char ch = text.charAt(p);
            boolean alpha = (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z');
            boolean digit = ch >= '0' && ch <= '9';
            if (alpha || (inName && digit)) {
                if (!inName) {
                    inName = true;
                    names++;
                }
                nameLength++;
            } else if (digit) {
                if (!inNumber) {
                    inNumber = true;
                    numbers++;
                    value = 0;
                }
                value = value * 10 + ch - 48;
            } else {
                if (inNumber) numberSum += value;
                inName = false;
                inNumber = false;
                if (ch != ' ') syms++;
            }
        }
        if (inNumber) numberSum += value;
        System.out.println(names + " " + numbers + " " + syms + " " + numberSum + " " + nameLength);
    }
}
