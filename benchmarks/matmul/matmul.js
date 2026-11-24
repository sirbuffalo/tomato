// Benchmark: integer matrix multiply, n x n, nested loops. Prints the sum of all entries of C = A * B.
function main(n) {
  const a = [];
  const b = [];
  for (let i = 0; i < n; i++) {
    const ra = [];
    const rb = [];
    for (let j = 0; j < n; j++) {
      ra.push((i * j + 1) % 10);
      rb.push((i + j) % 10);
    }
    a.push(ra);
    b.push(rb);
  }
  let total = 0;
  for (let i = 0; i < n; i++) {
    const row = a[i];
    for (let j = 0; j < n; j++) {
      let acc = 0;
      for (let k = 0; k < n; k++) acc += row[k] * b[k][j];
      total += acc;
    }
  }
  console.log(String(total));
}

main(Number(process.argv[2]));
