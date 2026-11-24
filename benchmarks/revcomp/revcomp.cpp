// Benchmark: reverse complement of DNA text. Makes a pseudo-random sequence of n letters (A, C, G, T) with a linear
// congruential generator, writes it as FASTA lines of 60 letters, reads the lines back, joins them, builds the reverse
// complement, and wraps it again. Prints the number of lines and a checksum over every 7th letter of the result.
#include <cstdint>
#include <iostream>
#include <string>
#include <vector>

static char complement(char c) {
    switch (c) {
        case 'A': return 'T';
        case 'C': return 'G';
        case 'G': return 'C';
        default: return 'A';
    }
}

static std::vector<std::string> wrap(const std::string &text) {
    std::vector<std::string> lines;
    for (std::size_t start = 0; start < text.size(); start += 60) lines.push_back(text.substr(start, 60));
    return lines;
}

int main(int, char **argv) {
    std::int64_t n = std::stoll(argv[1]), seed = 2718;
    const char letters[] = "ACGT";
    std::string dna;
    for (std::int64_t i = 0; i < n; i++) {
        seed = (seed * 1103515245 + 12345) % 2147483648;
        dna.push_back(letters[seed / 65536 % 4]);
    }
    std::string text;
    for (const std::string &line : wrap(dna)) text += line;
    std::string rc;
    for (std::size_t i = text.size(); i-- > 0;) rc.push_back(complement(text[i]));
    std::vector<std::string> wrapped = wrap(rc);
    std::int64_t checksum = 0;
    for (const std::string &line : wrapped)
        for (std::size_t k = 0; k < line.size(); k += 7) checksum = (checksum * 131 + static_cast<unsigned char>(line[k])) % 1000000007;
    std::cout << wrapped.size() << ' ' << checksum << '\n';
}
