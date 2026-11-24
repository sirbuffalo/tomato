# Benchmark: fannkuch-redux. Goes through all permutations of 0..n-1 and flips the prefix of each (as many cards as the
# first card says) until the first card is 0. Prints the alternating-sign checksum of the flip counts and the maximum.
import sys

n = int(sys.argv[1])
perm1 = list(range(n))
perm = [0] * n
count = [0] * n
max_flips = 0
checksum = 0
perm_count = 0
r = n
done = False
while not done:
    while r != 1:
        count[r - 1] = r
        r -= 1
    for i in range(n):
        perm[i] = perm1[i]
    flips = 0
    k = perm[0]
    while k != 0:
        i = 0
        j = k
        while i < j:
            t = perm[i]
            perm[i] = perm[j]
            perm[j] = t
            i += 1
            j -= 1
        flips += 1
        k = perm[0]
    if flips > max_flips:
        max_flips = flips
    if perm_count % 2 == 0:
        checksum += flips
    else:
        checksum -= flips
    while True:
        if r == n:
            done = True
            break
        p0 = perm1[0]
        for i in range(r):
            perm1[i] = perm1[i + 1]
        perm1[r] = p0
        count[r] -= 1
        if count[r] > 0:
            break
        r += 1
    perm_count += 1
print(checksum)
print(f'Pfannkuchen({n}) = {max_flips}')
