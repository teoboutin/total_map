// Expect: "duplicate enum key"
//
// Red appears twice; Blue is therefore also uncovered, but the duplicate check
// runs first and is what fires.
#include <emap/total_map.h>

enum class Color { Red, Green, Blue, Count };

constexpr emap::total_map m{
    emap::entry{Color::Red, 1},
    emap::entry{Color::Red, 2},
    emap::entry{Color::Blue, 3},
};

int main() {}
