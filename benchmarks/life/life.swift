// Benchmark: Conway's Game of Life on an n x n torus, 100 generations, from a pseudo-random start (about 1 cell in 3
// alive). Nested lists, neighbour counting with wrap-around. Prints the live cells at the end and a position checksum.
let n = Int(CommandLine.arguments[1])!
var seed = 99
var grid = [[Int]]()
var nextGrid = [[Int]]()
for _ in 0..<n {
    var row = [Int](repeating: 0, count: n)
    for x in 0..<n {
        seed = (seed * 1103515245 + 12345) % 2147483648
        if seed / 65536 % 3 == 0 { row[x] = 1 }
    }
    grid.append(row)
    nextGrid.append([Int](repeating: 0, count: n))
}
for _ in 0..<100 {
    for y in 0..<n {
        let up = grid[(y + n - 1) % n]
        let mid = grid[y]
        let down = grid[(y + 1) % n]
        var out = nextGrid[y]
        nextGrid[y] = []
        for x in 0..<n {
            let left = (x + n - 1) % n
            let right = (x + 1) % n
            let around = up[left] + up[x] + up[right] + mid[left] + mid[right] + down[left] + down[x] + down[right]
            if around == 3 || (around == 2 && mid[x] == 1) {
                out[x] = 1
            } else {
                out[x] = 0
            }
        }
        nextGrid[y] = out
    }
    let swap = grid
    grid = nextGrid
    nextGrid = swap
}
var alive = 0
var checksum = 0
for y in 0..<n {
    for x in 0..<n {
        if grid[y][x] == 1 {
            alive += 1
            checksum = (checksum * 31 + y * n + x) % 1000000007
        }
    }
}
print(alive, checksum)
