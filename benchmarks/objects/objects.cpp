// Benchmark: objects and method calls. Makes n particles, steps each one 10 times, prints the sum of their positions.
// The particles are separate heap objects (unique_ptr), like Tomato and Python objects.
#include <cstdint>
#include <iostream>
#include <memory>
#include <string>
#include <vector>

struct Particle {
    std::int64_t x, v;
    Particle(std::int64_t x, std::int64_t v) : x(x), v(v) {}
    void step(std::int64_t round) { x = (x + v * round) % 1000003; }
};

int main(int, char **argv) {
    std::int64_t n = std::stoll(argv[1]);
    std::vector<std::unique_ptr<Particle>> particles;
    for (std::int64_t i = 0; i < n; i++) particles.push_back(std::make_unique<Particle>(i, i % 13 + 1));
    for (std::int64_t round = 1; round <= 10; round++)
        for (auto &p : particles) p->step(round);
    std::int64_t total = 0;
    for (const auto &p : particles) total += p->x;
    std::cout << total << '\n';
}
