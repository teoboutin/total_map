// Expect: "enum value repeated"
//
// Distinct from total_map's `duplicate enum key`: the KEYS here are fine —
// it is the VALUES that are enumerators, and one is hit twice, so with
// equal counts another is necessarily missed.
#include <emap/bijection.h>

enum class Port { A, B, C, Count };
enum class Pin { P0, P1, P2, Count };

constexpr emap::bijection m{
    emap::entry{Port::A, Pin::P0},
    emap::entry{Port::B, Pin::P0},
    emap::entry{Port::C, Pin::P2},
};

int main() {}
