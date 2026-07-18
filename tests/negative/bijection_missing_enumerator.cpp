// Expect: "enum value not covered"
//
// Key-side failures are DELEGATED: the sugar builds the total_map first, so
// the diagnostic is total_map's own, verbatim.
#include <emap/bijection.h>

enum class Port { A, B, C, Count };
enum class Pin { P0, P1, P2, Count };

constexpr emap::bijection<Port, Pin> m{
    emap::entry{Port::A, Pin::P0},
    emap::entry{Port::B, Pin::P1},
};

int main() {}
