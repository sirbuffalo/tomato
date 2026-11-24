// Benchmark: function values. Calls one of four functions chosen from an array n times (each result feeds the next), then
// runs map and filter with arrow functions and sorts with a key function over an array of n / 4 numbers. Prints three
// checksums.
// The LCG product needs 61 bits, more than a JavaScript number holds exactly, so Math.imul keeps its low 32 bits, which is
// all that the mod 2^31 (the & 0x7fffffff) looks at.
function f0(x) {
  return (x * 3 + 1) % 1000003;
}

function f1(x) {
  return (x + 7919) % 1000003;
}

function f2(x) {
  return x * x % 1000003;
}

function f3(x) {
  return (x ^ 12345) % 1000003;
}

function applyTwice(f, x) {
  return f(f(x));
}

const n = Number(process.argv[2]);
const table = [f0, f1, f2, f3];
let x = 1;
for (let i = 0; i < n; i++) x = table[i % 4](x + i);
console.log(String(x));
let y = 0;
for (let i = 0; i < n; i++) y = (y + applyTwice(table[i % 4], i)) % 1000000007;
console.log(String(y));
const m = Math.floor(n / 4);
const xs = [];
for (let i = 0; i < m; i++) xs.push(i * 7919 % 100003);
const squares = xs.map((v) => v * v % 1009);
const odd = squares.filter((v) => v % 2 === 1);
// a stable sort by key, like Tomato's sorted(key=...) (the key is computed once per element)
const keyed = odd.map((v) => [v % 997 * 1000 + v % 1000, v]);
keyed.sort((a, b) => a[0] - b[0]);
let z = 0;
for (let i = 0; i < keyed.length; i++) z = (z * 31 + keyed[i][1]) % 1000000007;
console.log(keyed.length + " " + z);
