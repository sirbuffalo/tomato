# Benchmark: reverse complement of DNA text. Makes a pseudo-random sequence of n letters (A, C, G, T) with a linear
# congruential generator, writes it as FASTA lines of 60 letters, reads the lines back, joins them, builds the reverse
# complement, and wraps it again. Prints the number of lines and a checksum over every 7th letter of the result.
import sys

n = int(sys.argv[1])
seed = 2718
letters = ['A', 'C', 'G', 'T']
parts = []
for i in range(n):
    seed = (seed * 1103515245 + 12345) % 2147483648
    parts.append(letters[seed // 65536 % 4])
dna = ''.join(parts)
lines = []
for start in range(0, n, 60):
    lines.append(dna[start:start + 60])
text = ''.join(lines)
complement = {'A': 'T', 'C': 'G', 'G': 'C', 'T': 'A'}
out = []
i = len(text) - 1
while i >= 0:
    out.append(complement[text[i]])
    i -= 1
rc = ''.join(out)
wrapped = []
for start in range(0, len(rc), 60):
    wrapped.append(rc[start:start + 60])
checksum = 0
for line in wrapped:
    for k in range(0, len(line), 7):
        checksum = (checksum * 131 + ord(line[k])) % 1000000007
print(len(wrapped), checksum)
