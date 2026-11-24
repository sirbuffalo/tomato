// Benchmark: spectral norm of an infinite matrix, cut to n x n (float arithmetic in nested loops, function calls).
// Ten rounds of the power method; prints the norm times 1e9, cut to a whole number.
function a(i, j) {
  return 1.0 / (Math.floor((i + j) * (i + j + 1) / 2) + i + 1);
}

function timesA(n, v, out) {
  for (let i = 0; i < n; i++) {
    let s = 0.0;
    for (let j = 0; j < n; j++) s += a(i, j) * v[j];
    out[i] = s;
  }
}

function timesATransposed(n, v, out) {
  for (let i = 0; i < n; i++) {
    let s = 0.0;
    for (let j = 0; j < n; j++) s += a(j, i) * v[j];
    out[i] = s;
  }
}

function timesAtA(n, v, out, tmp) {
  timesA(n, v, tmp);
  timesATransposed(n, tmp, out);
}

const n = Number(process.argv[2]);
const u = new Float64Array(n).fill(1.0);
const v = new Float64Array(n);
const tmp = new Float64Array(n);
for (let round = 0; round < 10; round++) {
  timesAtA(n, u, v, tmp);
  timesAtA(n, v, u, tmp);
}
let vbv = 0.0;
let vv = 0.0;
for (let i = 0; i < n; i++) {
  vbv += u[i] * v[i];
  vv += v[i] * v[i];
}
console.log(String(Math.trunc(Math.sqrt(vbv / vv) * 1000000000.0)));
