// Benchmark: text building and parsing. Joins n numbers into one comma-separated string, splits it and adds them up.
// Prints the text length and the sum. The pieces are string_views of the text, which is the usual way to split in C++.
#include <charconv>
#include <cstdint>
#include <iostream>
#include <string>
#include <string_view>
#include <vector>

int main(int, char **argv) {
    std::int64_t n = std::stoll(argv[1]);
    std::vector<std::string> parts;
    for (std::int64_t i = 0; i < n; i++) parts.push_back(std::to_string(i * 7 % 1000));
    std::string text;
    for (std::size_t i = 0; i < parts.size(); i++) {
        if (i > 0) text += ',';
        text += parts[i];
    }
    std::vector<std::string_view> pieces;
    std::string_view rest = text;
    for (std::size_t at; (at = rest.find(',')) != std::string_view::npos; rest.remove_prefix(at + 1)) pieces.push_back(rest.substr(0, at));
    pieces.push_back(rest);
    std::int64_t total = 0;
    for (std::string_view piece : pieces) {
        std::int64_t value = 0;
        std::from_chars(piece.data(), piece.data() + piece.size(), value);
        total += value;
    }
    std::cout << text.size() << ' ' << total << '\n';
}
