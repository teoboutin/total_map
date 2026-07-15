// Expect: "duplicate enum key"
//
// Pins the "Right-sized" guarantee, which no longer has a check of its own: too
// many rows are rejected purely by pigeonhole. M = 4 keys cannot be distinct in
// [0, 3), so uniqueness (or range) necessarily fires first.
//
// Necessarily also a duplicate test -- that is the point, not an oversight.
// There is no way to write "too many rows, none duplicated, none out of range";
// the impossibility IS the guarantee. If someone re-adds an explicit count
// check, this still passes; if the uniqueness check breaks, this fails.
#include <emap/total_map.h>

enum class Color { Red, Green, Blue, Count };

constexpr emap::total_map m{
    emap::entry{Color::Red, 1},
    emap::entry{Color::Green, 2},
    emap::entry{Color::Blue, 3},
    emap::entry{Color::Red, 4}, // one row too many
};

int main() {}
