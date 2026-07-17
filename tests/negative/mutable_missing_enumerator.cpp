// Expect: "enum value not covered"
//
// The array-form delegating sugar, same proof as mutable_duplicate_key.cpp:
// rejection text is total_map's own, verbatim.
#include <emap/mutable_total_map.h>

#include <array>

enum class Color { Red, Green, Blue, Count };

constexpr emap::mutable_total_map m{std::array{
    emap::entry{Color::Red, 1},
    emap::entry{Color::Green, 2}, // Blue is missing
}};

int main() {}
