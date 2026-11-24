// Benchmark: Dijkstra's shortest paths on an n x n grid of pseudo-random step costs (1..9), from the top-left corner, with a
// hand-written binary min-heap of encoded (distance, cell) numbers. Prints the distance to the far corner and the sum
// of all distances.
// The LCG product needs 61 bits, more than a JavaScript number holds exactly, so Math.imul keeps its low 32 bits, which is
// all that the mod 2^31 (the & 0x7fffffff) looks at.
function push(heap: number[], size: number, key: number): number {
  if (size === heap.length) heap.push(key);
  else heap[size] = key;
  let i = size;
  while (i > 0) {
    const parent = (i - 1) >> 1;
    if (heap[parent] <= key) break;
    heap[i] = heap[parent];
    i = parent;
  }
  heap[i] = key;
  return size + 1;
}

// removes the smallest key (the caller has read heap[0]) and returns the new size
function pop(heap: number[], size: number): number {
  size -= 1;
  const key = heap[size];
  let i = 0;
  while (true) {
    let child = 2 * i + 1;
    if (child >= size) break;
    if (child + 1 < size && heap[child + 1] < heap[child]) child += 1;
    if (heap[child] >= key) break;
    heap[i] = heap[child];
    i = child;
  }
  heap[i] = key;
  return size;
}

const n: number = Number(process.argv[2]);
let seed: number = 2024;
const cells = n * n;
const cost: Int32Array = new Int32Array(cells);
for (let i = 0; i < cells; i++) {
  seed = (Math.imul(seed, 1103515245) + 12345) & 0x7fffffff;
  cost[i] = (seed >> 16) % 9 + 1;
}
const infinity = 1000000000;
const dist: Int32Array = new Int32Array(cells).fill(infinity);
const heap: number[] = new Array(16).fill(0);
let size: number = 0;
dist[0] = 0;
size = push(heap, size, 0);
while (size > 0) {
  const top = heap[0];
  size = pop(heap, size);
  const d = Math.floor(top / cells);
  const cell = top % cells;
  if (d > dist[cell]) continue;
  const y = Math.floor(cell / n);
  const x = cell % n;
  if (y > 0 && d + cost[cell - n] < dist[cell - n]) {
    dist[cell - n] = d + cost[cell - n];
    size = push(heap, size, dist[cell - n] * cells + cell - n);
  }
  if (y < n - 1 && d + cost[cell + n] < dist[cell + n]) {
    dist[cell + n] = d + cost[cell + n];
    size = push(heap, size, dist[cell + n] * cells + cell + n);
  }
  if (x > 0 && d + cost[cell - 1] < dist[cell - 1]) {
    dist[cell - 1] = d + cost[cell - 1];
    size = push(heap, size, dist[cell - 1] * cells + cell - 1);
  }
  if (x < n - 1 && d + cost[cell + 1] < dist[cell + 1]) {
    dist[cell + 1] = d + cost[cell + 1];
    size = push(heap, size, dist[cell + 1] * cells + cell + 1);
  }
}
let total = 0;
for (let i = 0; i < cells; i++) total += dist[i];
console.log(dist[cells - 1] + " " + total);
