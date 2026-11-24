// Benchmark: naive recursive Fibonacci. Prints fib(n).
class fib {
    static long fib(long n) {
        if (n < 2) return n;
        return fib(n - 1) + fib(n - 2);
    }

    public static void main(String[] args) {
        System.out.println(fib(Long.parseLong(args[0])));
    }
}
