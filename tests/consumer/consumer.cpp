// Compiled by every consumer path. Proves ALL FOUR headers are reachable and
// a table actually builds through the packaged target — and, at run time,
// that a proven table thaws into a live one that can drift and knows it, that
// a proven-keyed table answers a runtime lookup by id, and that a proven
// bijection answers a runtime single-slot inverse.
#include <emap/bijection.h>
#include <emap/keyed_map.h>
#include <emap/mutable_total_map.h>
#include <emap/total_map.h>

enum class Color { Red, Green, Blue, Count };

constexpr emap::total_map styles{
    emap::entry{Color::Red, 1},
    emap::entry{Color::Green, 2},
    emap::entry{Color::Blue, 3},
};
static_assert(styles[Color::Green] == 2);

constexpr emap::keyed_map keyed = styles; // promote: values proven distinct
static_assert(keyed.find(2) != nullptr);

enum class Lamp { Dark, Lit, Count };
enum class Mode { Off, On, Count };

constexpr emap::bijection modeLamp{
    emap::entry{Mode::Off, Lamp::Dark},
    emap::entry{Mode::On, Lamp::Lit},
};
static_assert(modeLamp.inverse()[Lamp::Lit] == Mode::On);

int main()
{
    // Runtime thaw + mutation: the capability the flagship type refuses.
    emap::mutable_total_map live = styles;
    live[Color::Red] = 7;
    // Runtime lookup by id: the capability the keyed proof licenses.
    const int* found = keyed.find(3);
    const bool ok = live[Color::Red] == 7 && live[Color::Green] == 2 && live != styles &&
                    found != nullptr && *found == 3 && keyed.find(9) == nullptr &&
                    modeLamp.inverse_at(Lamp::Dark) == Mode::Off;
    return ok ? 0 : 1;
}
