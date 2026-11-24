// Benchmark: n queens. Counts the ways to place n queens on an n x n board so that none attacks another (backtracking,
// recursion, arrays of flags for the columns and the two diagonals).
function place(n: number, row: number, cols: boolean[], diag1: boolean[], diag2: boolean[]): number {
  if (row === n) return 1;
  let count: number = 0;
  for (let c = 0; c < n; c++) {
    const d1 = row + c;
    const d2 = row - c + n - 1;
    if (cols[c] || diag1[d1] || diag2[d2]) continue;
    cols[c] = true;
    diag1[d1] = true;
    diag2[d2] = true;
    count += place(n, row + 1, cols, diag1, diag2);
    cols[c] = false;
    diag1[d1] = false;
    diag2[d2] = false;
  }
  return count;
}

const n: number = Number(process.argv[2]);
console.log(String(place(n, 0, new Array(n).fill(false), new Array(2 * n).fill(false), new Array(2 * n).fill(false))));
