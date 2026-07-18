// Expect: "duplicate value"
//
// Under the DEFAULT identity projection the values are their own ids, and two
// rows carry equal values. The keys are fine — this is the id check firing,
// after total_map's key checks all passed.
#include <emap/keyed_map.h>

enum class Gem { Ruby, Jade, Opal, Count };

constexpr emap::keyed_map m{
    emap::entry{Gem::Ruby, 11},
    emap::entry{Gem::Jade, 11},
    emap::entry{Gem::Opal, 33},
};

int main() {}
