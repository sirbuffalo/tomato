// Benchmark: objects and method calls. Makes n particles, steps each one 10 times, prints the sum of their positions.
// The particles are separate heap objects (pointers), like Tomato and Python objects.
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

typedef struct { int64_t x, v; } Particle;

static void step(Particle *p, int64_t round) { p->x = (p->x + p->v * round) % 1000003; }

int main(int argc, char **argv) {
    (void)argc;
    int64_t n = atoll(argv[1]);
    size_t length = 0, capacity = 0;
    Particle **particles = NULL;
    for (int64_t i = 0; i < n; i++) {
        Particle *p = malloc(sizeof *p);
        p->x = i;
        p->v = i % 13 + 1;
        if (length == capacity) particles = realloc(particles, (capacity = capacity ? capacity * 2 : 4) * sizeof *particles);
        particles[length++] = p;
    }
    for (int64_t round = 1; round <= 10; round++)
        for (size_t k = 0; k < length; k++) step(particles[k], round);
    int64_t total = 0;
    for (size_t k = 0; k < length; k++) total += particles[k]->x;
    printf("%lld\n", (long long)total);
    for (size_t k = 0; k < length; k++) free(particles[k]);
    free(particles);
}
