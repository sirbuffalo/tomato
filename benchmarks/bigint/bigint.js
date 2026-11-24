// Benchmark: big integers. Computes n! by multiplying one small number at a time. Prints n! mod 1000000007.
const n = Number(process.argv[2]);
let product = 1n;
for (let i = 2; i <= n; i++) product *= BigInt(i);
console.log(String(product % 1000000007n));
