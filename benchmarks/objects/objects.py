# Benchmark: objects and method calls. Makes n particles, steps each one 10 times, prints the sum of their positions.
import sys


class Particle:
    def __init__(self, x, v):
        self.x = x
        self.v = v

    def step(self, round):
        self.x = (self.x + self.v * round) % 1000003


n = int(sys.argv[1])
particles = [Particle(i, i % 13 + 1) for i in range(n)]
for round in range(1, 11):
    for p in particles:
        p.step(round)
total = 0
for p in particles:
    total += p.x
print(total)
