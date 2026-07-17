// Expect: "duplicate enum key"
//
// The delegating authoring sugar must report through total_map's validation —
// mutable_total_map performs no checking of its own, and this proves the
// delegation actually reaches make_perm rather than skipping it.
#include <emap/mutable_total_map.h>

enum class Color { Red, Green, Blue, Count };

constexpr emap::mutable_total_map m{
    emap::entry{Color::Red, 1},
    emap::entry{Color::Red, 2},
    emap::entry{Color::Blue, 3},
};

int main() {}
