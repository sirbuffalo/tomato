// Benchmark: a hand-written quicksort (recursive, Hoare partition, middle pivot, insertion sort for short ranges) on n
// pseudo-random integers from a linear congruential generator. Prints a position-weighted checksum of the sorted array.
// The LCG product needs 61 bits, more than a JavaScript number holds exactly, so Math.imul keeps its low 32 bits, which is
// all that the mod 2^31 (the & 0x7fffffff) looks at.
function insertionSort(values, low, high) {
  for (let i = low + 1; i <= high; i++) {
    const x = values[i];
    let j = i - 1;
    while (j >= low && values[j] > x) {
      values[j + 1] = values[j];
      j -= 1;
    }
    values[j + 1] = x;
  }
}

function quicksort(values, low, high) {
  while (high - low > 16) {
    const pivot = values[(low + high) >> 1];
    let i = low;
    let j = high;
    while (i <= j) {
      while (values[i] < pivot) i += 1;
      while (values[j] > pivot) j -= 1;
      if (i <= j) {
        const t = values[i];
        values[i] = values[j];
        values[j] = t;
        i += 1;
        j -= 1;
      }
    }
    // recurse into the smaller part, loop on the larger one
    if (j - low < high - i) {
      quicksort(values, low, j);
      low = i;
    } else {
      quicksort(values, i, high);
      high = j;
    }
  }
  insertionSort(values, low, high);
}

const n = Number(process.argv[2]);
let seed = 12345;
const values = new Int32Array(n);
for (let i = 0; i < n; i++) {
  seed = (Math.imul(seed, 1103515245) + 12345) & 0x7fffffff;
  values[i] = seed;
}
quicksort(values, 0, n - 1);
let checksum = 0;
for (let i = 0; i < n; i++) checksum = (checksum + (i % 1000 + 1) * values[i]) % 1000000007;
console.log(String(checksum));
