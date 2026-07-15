// Compiled by every consumer path. Proves the header is reachable and a table
// actually builds through the packaged target.
#include <emap/total_map.h>

enum class Color { Red, Green, Blue, Count };

constexpr emap::total_map styles{
    emap::entry{Color::Red, 1},
    emap::entry{Color::Green, 2},
    emap::entry{Color::Blue, 3},
};
static_assert(styles[Color::Green] == 2);

int main() { return 0; }
