# Benchmark: n queens. Counts the ways to place n queens on an n x n board so that none attacks another (backtracking,
# recursion, lists of bools for the columns and the two diagonals).
import sys


def place(n, row, cols, diag1, diag2):
    if row == n:
        return 1
    count = 0
    for c in range(n):
        d1 = row + c
        d2 = row - c + n - 1
        if cols[c] or diag1[d1] or diag2[d2]:
            continue
        cols[c] = True
        diag1[d1] = True
        diag2[d2] = True
        count += place(n, row + 1, cols, diag1, diag2)
        cols[c] = False
        diag1[d1] = False
        diag2[d2] = False
    return count


n = int(sys.argv[1])
print(place(n, 0, [False] * n, [False] * (2 * n), [False] * (2 * n)))
