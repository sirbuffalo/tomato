# Benchmark: text building and parsing. Joins n numbers into one comma-separated string, splits it and adds them up.
# Prints the text length and the sum.
import sys

n = int(sys.argv[1])
parts = [str(i * 7 % 1000) for i in range(n)]
text = ','.join(parts)
total = 0
for piece in text.split(','):
    total += int(piece)
print(len(text), total)
