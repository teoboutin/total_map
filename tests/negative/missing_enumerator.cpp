// Expect: "enum value not covered"
//
// The headline guarantee: omit a row and it does not compile. Blue has no row,
// so it reaches the coverage loop uncovered.
//
// This is also the case that named the whole design: with an `M != N` check in
// front, this table reported "input row count != enum_count_v<E>" and lectured
// about `Count` sentinels and stale counts, while the coverage check that
// actually describes the mistake was unreachable.
#include <emap/total_map.h>

enum class Color { Red, Green, Blue, Count };

constexpr emap::total_map m{
    emap::entry{Color::Red, 1},
    emap::entry{Color::Green, 2},
    // Blue omitted
};

int main() {}
