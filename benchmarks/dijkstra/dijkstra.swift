// Benchmark: Dijkstra's shortest paths on an n x n grid of pseudo-random step costs (1..9), from the top-left corner, with a
// hand-written binary min-heap of encoded (distance, cell) numbers. Prints the distance to the far corner and the sum
// of all distances.
func push(_ heap: inout [Int], _ size: Int, _ key: Int) -> Int {
    if size == heap.count {
        heap.append(key)
    } else {
        heap[size] = key
    }
    var i = size
    while i > 0 {
        let parent = (i - 1) / 2
        if heap[parent] <= key { break }
        heap[i] = heap[parent]
        i = parent
    }
    heap[i] = key
    return size + 1
}

func pop(_ heap: inout [Int], _ size: Int) -> Int {
    // removes the smallest key (the caller has read heap[0]) and returns the new size
    let size = size - 1
    let key = heap[size]
    var i = 0
    while true {
        var child = 2 * i + 1
        if child >= size { break }
        if child + 1 < size && heap[child + 1] < heap[child] { child += 1 }
        if heap[child] >= key { break }
        heap[i] = heap[child]
        i = child
    }
    heap[i] = key
    return size
}

let n = Int(CommandLine.arguments[1])!
var seed = 2024
var cost = [Int](repeating: 0, count: n * n)
for i in 0..<(n * n) {
    seed = (seed * 1103515245 + 12345) % 2147483648
    cost[i] = seed / 65536 % 9 + 1
}
let cells = n * n
let infinity = 1000000000
var dist = [Int](repeating: infinity, count: cells)
var heap = [Int](repeating: 0, count: 16)
var size = 0
dist[0] = 0
size = push(&heap, size, 0)
while size > 0 {
    let top = heap[0]
    size = pop(&heap, size)
    let d = top / cells
    let cell = top % cells
    if d > dist[cell] { continue }
    let y = cell / n
    let x = cell % n
    if y > 0 && d + cost[cell - n] < dist[cell - n] {
        dist[cell - n] = d + cost[cell - n]
        size = push(&heap, size, dist[cell - n] * cells + cell - n)
    }
    if y < n - 1 && d + cost[cell + n] < dist[cell + n] {
        dist[cell + n] = d + cost[cell + n]
        size = push(&heap, size, dist[cell + n] * cells + cell + n)
    }
    if x > 0 && d + cost[cell - 1] < dist[cell - 1] {
        dist[cell - 1] = d + cost[cell - 1]
        size = push(&heap, size, dist[cell - 1] * cells + cell - 1)
    }
    if x < n - 1 && d + cost[cell + 1] < dist[cell + 1] {
        dist[cell + 1] = d + cost[cell + 1]
        size = push(&heap, size, dist[cell + 1] * cells + cell + 1)
    }
}
var total = 0
for d in dist { total += d }
print(dist[cells - 1], total)
