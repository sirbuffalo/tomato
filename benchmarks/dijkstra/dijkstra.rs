// Benchmark: Dijkstra's shortest paths on an n x n grid of pseudo-random step costs (1..9), from the top-left corner, with a
// hand-written binary min-heap of encoded (distance, cell) numbers. Prints the distance to the far corner and the sum
// of all distances.
fn push(heap: &mut Vec<u64>, size: usize, key: u64) -> usize {
    if size == heap.len() {
        heap.push(key);
    } else {
        heap[size] = key;
    }
    let mut i = size;
    while i > 0 {
        let parent = (i - 1) / 2;
        if heap[parent] <= key {
            break;
        }
        heap[i] = heap[parent];
        i = parent;
    }
    heap[i] = key;
    size + 1
}

fn pop(heap: &mut Vec<u64>, size: usize) -> usize {
    // removes the smallest key (the caller has read heap[0]) and returns the new size
    let size = size - 1;
    let key = heap[size];
    let mut i = 0;
    loop {
        let mut child = 2 * i + 1;
        if child >= size {
            break;
        }
        if child + 1 < size && heap[child + 1] < heap[child] {
            child += 1;
        }
        if heap[child] >= key {
            break;
        }
        heap[i] = heap[child];
        i = child;
    }
    heap[i] = key;
    size
}

fn main() {
    let n: usize = std::env::args().nth(1).unwrap().parse().unwrap();
    let mut seed: u64 = 2024;
    let mut cost = vec![0u64; n * n];
    for i in 0..n * n {
        seed = (seed * 1103515245 + 12345) % 2147483648;
        cost[i] = seed / 65536 % 9 + 1;
    }
    let cells = n * n;
    let infinity: u64 = 1000000000;
    let mut dist = vec![infinity; cells];
    let mut heap = vec![0u64; 16];
    let mut size = 0;
    dist[0] = 0;
    size = push(&mut heap, size, 0);
    while size > 0 {
        let top = heap[0];
        size = pop(&mut heap, size);
        let d = top / cells as u64;
        let cell = (top % cells as u64) as usize;
        if d > dist[cell] {
            continue;
        }
        let y = cell / n;
        let x = cell % n;
        if y > 0 && d + cost[cell - n] < dist[cell - n] {
            dist[cell - n] = d + cost[cell - n];
            size = push(&mut heap, size, dist[cell - n] * cells as u64 + (cell - n) as u64);
        }
        if y < n - 1 && d + cost[cell + n] < dist[cell + n] {
            dist[cell + n] = d + cost[cell + n];
            size = push(&mut heap, size, dist[cell + n] * cells as u64 + (cell + n) as u64);
        }
        if x > 0 && d + cost[cell - 1] < dist[cell - 1] {
            dist[cell - 1] = d + cost[cell - 1];
            size = push(&mut heap, size, dist[cell - 1] * cells as u64 + (cell - 1) as u64);
        }
        if x < n - 1 && d + cost[cell + 1] < dist[cell + 1] {
            dist[cell + 1] = d + cost[cell + 1];
            size = push(&mut heap, size, dist[cell + 1] * cells as u64 + (cell + 1) as u64);
        }
    }
    let mut total: u64 = 0;
    for d in &dist {
        total += d;
    }
    println!("{} {}", dist[cells - 1], total);
}
