// Benchmark: sieve of Eratosthenes. Prints how many primes are <= n.
// A Uint8Array is JavaScript's array of small flags, like Go's []bool and Rust's Vec<bool>.
const n: number = Number(process.argv[2]);
const composite: Uint8Array = new Uint8Array(n + 1);
let count: number = 0;
for (let i = 2; i <= n; i++) {
  if (composite[i]) continue;
  count++;
  for (let j = i * i; j <= n; j += i) composite[j] = 1;
}
console.log(String(count));
