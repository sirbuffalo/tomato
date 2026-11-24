// Benchmark: big integers. Computes n! by multiplying one small number at a time. Prints n! mod 1000000007.
import java.math.BigInteger;

class bigint {
    public static void main(String[] args) {
        int n = Integer.parseInt(args[0]);
        BigInteger product = BigInteger.ONE;
        for (int i = 2; i <= n; i++) product = product.multiply(BigInteger.valueOf(i));
        System.out.println(product.mod(BigInteger.valueOf(1000000007)));
    }
}
