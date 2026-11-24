// Benchmark: checksums over bytes. Makes n pseudo-random bytes with a linear congruential generator, then computes the
// table-driven CRC-32 (polynomial 0xEDB88320) over them four times (each pass starts from the previous result) and the
// Adler-32 once. Prints both. Bitwise operators and lookups in a 256-entry table.
using System;

static class Program {
    static void Main(string[] args) {
        int n = int.Parse(args[0]);
        long[] table = new long[256];
        for (int i = 0; i < 256; i++) {
            long c = i;
            for (int k = 0; k < 8; k++) {
                if ((c & 1) == 1) c = 3988292384L ^ (c >> 1);
                else c = c >> 1;
            }
            table[i] = c;
        }
        long seed = 1;
        int[] data = new int[n];
        for (int i = 0; i < n; i++) {
            seed = (seed * 1103515245L + 12345) % 2147483648L;
            data[i] = (int)(seed / 65536 % 256);
        }
        long crc = 4294967295L;
        for (int rounds = 0; rounds < 4; rounds++) {
            foreach (int b in data) crc = table[(int)((crc ^ b) & 255)] ^ (crc >> 8);
        }
        crc = crc ^ 4294967295L;
        long a = 1, b2 = 0;
        foreach (int b in data) {
            a = (a + b) % 65521;
            b2 = (b2 + a) % 65521;
        }
        Console.WriteLine($"{crc} {b2 * 65536 + a}");
    }
}
