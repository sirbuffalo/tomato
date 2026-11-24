// Benchmark: fannkuch-redux. Goes through all permutations of 0..n-1 and flips the prefix of each (as many cards as the
// first card says) until the first card is 0. Prints the alternating-sign checksum of the flip counts and the maximum.
class fannkuch {
    public static void main(String[] args) {
        int n = Integer.parseInt(args[0]);
        int[] perm1 = new int[n];
        for (int i = 0; i < n; i++) perm1[i] = i;
        int[] perm = new int[n];
        int[] count = new int[n];
        long maxFlips = 0;
        long checksum = 0;
        long permCount = 0;
        int r = n;
        boolean done = false;
        while (!done) {
            while (r != 1) {
                count[r - 1] = r;
                r--;
            }
            for (int i = 0; i < n; i++) perm[i] = perm1[i];
            long flips = 0;
            int k = perm[0];
            while (k != 0) {
                int i = 0, j = k;
                while (i < j) {
                    int t = perm[i];
                    perm[i] = perm[j];
                    perm[j] = t;
                    i++;
                    j--;
                }
                flips++;
                k = perm[0];
            }
            if (flips > maxFlips) maxFlips = flips;
            if (permCount % 2 == 0) checksum += flips;
            else checksum -= flips;
            while (true) {
                if (r == n) {
                    done = true;
                    break;
                }
                int p0 = perm1[0];
                for (int i = 0; i < r; i++) perm1[i] = perm1[i + 1];
                perm1[r] = p0;
                count[r]--;
                if (count[r] > 0) break;
                r++;
            }
            permCount++;
        }
        System.out.println(checksum);
        System.out.println("Pfannkuchen(" + n + ") = " + maxFlips);
    }
}
