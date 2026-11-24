// Benchmark: naive recursive Fibonacci. Prints fib(n).
function fib(n) {
  if (n < 2) return n;
  return fib(n - 1) + fib(n - 2);
}

console.log(String(fib(Number(process.argv[2]))));
