// Benchmark: sort n pseudo-random integers (a linear congruential generator). Prints a position-weighted checksum.
// The product needs 61 bits, more than a JavaScript number holds exactly, so Math.imul keeps its low 32 bits, which is all
// that `% 2147483648` looks at. A typed array sorts by number (a plain array would need a compare function and is slower).
const n = Number(process.argv[2]);
let seed = 12345;
const values = new Float64Array(n);
for (let i = 0; i < n; i++) {
  seed = (Math.imul(seed, 1103515245) + 12345) & 0x7fffffff;
  values[i] = seed;
}
const ordered = values.slice().sort();
let checksum = 0;
for (let i = 0; i < n; i++) checksum = (checksum + (i % 1000 + 1) * ordered[i]) % 1000000007;
console.log(String(checksum));
