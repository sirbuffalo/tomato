// Benchmark: Conway's Game of Life on an n x n torus, 100 generations, from a pseudo-random start (about 1 cell in 3
// alive). Arrays of rows, neighbour counting with wrap-around. Prints the live cells at the end and a position checksum.
// The LCG product needs 61 bits, more than a JavaScript number holds exactly, so Math.imul keeps its low 32 bits, which is
// all that the mod 2^31 (the & 0x7fffffff) looks at.
const n: number = Number(process.argv[2]);
let seed: number = 99;
let grid: Uint8Array[] = [];
let nextGrid: Uint8Array[] = [];
for (let y = 0; y < n; y++) {
  const row = new Uint8Array(n);
  for (let x = 0; x < n; x++) {
    seed = (Math.imul(seed, 1103515245) + 12345) & 0x7fffffff;
    if ((seed >> 16) % 3 === 0) row[x] = 1;
  }
  grid.push(row);
  nextGrid.push(new Uint8Array(n));
}
for (let gen = 0; gen < 100; gen++) {
  for (let y = 0; y < n; y++) {
    const up = grid[(y + n - 1) % n];
    const mid = grid[y];
    const down = grid[(y + 1) % n];
    const out = nextGrid[y];
    for (let x = 0; x < n; x++) {
      const left = (x + n - 1) % n;
      const right = (x + 1) % n;
      const around = up[left] + up[x] + up[right] + mid[left] + mid[right] + down[left] + down[x] + down[right];
      if (around === 3 || (around === 2 && mid[x] === 1)) out[x] = 1;
      else out[x] = 0;
    }
  }
  const swap = grid;
  grid = nextGrid;
  nextGrid = swap;
}
let alive = 0;
let checksum = 0;
for (let y = 0; y < n; y++) {
  for (let x = 0; x < n; x++) {
    if (grid[y][x] === 1) {
      alive += 1;
      checksum = (checksum * 31 + y * n + x) % 1000000007;
    }
  }
}
console.log(alive + " " + checksum);
