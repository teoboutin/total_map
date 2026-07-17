// Compiled by every consumer path. Proves BOTH headers are reachable and a
// table actually builds through the packaged target — and, at run time, that
// a proven table thaws into a live one that can drift and knows it.
#include <emap/mutable_total_map.h>
#include <emap/total_map.h>

enum class Color { Red, Green, Blue, Count };

constexpr emap::total_map styles{
    emap::entry{Color::Red, 1},
    emap::entry{Color::Green, 2},
    emap::entry{Color::Blue, 3},
};
static_assert(styles[Color::Green] == 2);

int main()
{
    // Runtime thaw + mutation: the capability the flagship type refuses.
    emap::mutable_total_map live = styles;
    live[Color::Red] = 7;
    const bool ok = live[Color::Red] == 7 && live[Color::Green] == 2 && live != styles;
    return ok ? 0 : 1;
}
