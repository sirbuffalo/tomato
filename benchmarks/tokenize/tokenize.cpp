// Benchmark: a hand-written tokenizer (no regular expressions). Makes n pseudo-random tokens of source-like text (names,
// whole numbers and punctuation), joins them, then scans the text one character at a time and classifies the tokens.
// Prints the number of names, numbers and symbols, the sum of the numbers and the total length of the names.
#include <cstdint>
#include <iostream>
#include <string>

static bool is_alpha(char c) { return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z'); }
static bool is_digit(char c) { return c >= '0' && c <= '9'; }

int main(int, char **argv) {
    std::int64_t n = std::stoll(argv[1]), seed = 555;
    const std::string words[] = {"alpha", "beta", "gamma", "delta", "count", "total", "index", "value"};
    const std::string symbols[] = {"+", "-", "*", "/", "=", "(", ")", ";"};
    std::string text;
    for (std::int64_t i = 0; i < n; i++) {
        seed = (seed * 1103515245 + 12345) % 2147483648;
        std::int64_t kind = seed / 65536 % 4;
        seed = (seed * 1103515245 + 12345) % 2147483648;
        std::int64_t pick = seed / 65536;
        if (kind == 0) text += words[pick % 8] + ' ';
        else if (kind == 1) text += std::to_string(pick % 100000) + ' ';
        else if (kind == 2) text += symbols[pick % 8];
        else text += words[pick % 8] + std::to_string(pick / 8 % 100) + ' ';
    }
    std::int64_t names = 0, numbers = 0, syms = 0, number_sum = 0, name_length = 0, value = 0;
    bool in_name = false, in_number = false;
    for (char ch : text) {
        if (is_alpha(ch) || (in_name && is_digit(ch))) {
            if (!in_name) {
                in_name = true;
                names++;
            }
            name_length++;
        } else if (is_digit(ch)) {
            if (!in_number) {
                in_number = true;
                numbers++;
                value = 0;
            }
            value = value * 10 + ch - 48;
        } else {
            if (in_number) number_sum += value;
            in_name = in_number = false;
            if (ch != ' ') syms++;
        }
    }
    if (in_number) number_sum += value;
    std::cout << names << ' ' << numbers << ' ' << syms << ' ' << number_sum << ' ' << name_length << '\n';
}
