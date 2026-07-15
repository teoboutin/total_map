// Expect: "enum key >= enum_count_v<E>"
//
// The row count is correct (M == N == 3), so the count check passes; the
// Count sentinel used as a live key (3) is what trips the range check.
#include <emap/total_map.h>

enum class Color { Red, Green, Blue, Count };

constexpr emap::total_map m{
    emap::entry{Color::Red, 1},
    emap::entry{Color::Green, 2},
    emap::entry{Color::Count, 3},
};

int main() {}
