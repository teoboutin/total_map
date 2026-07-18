// Expect: "enum value not covered"
//
// The authoring sugar delegates to total_map FIRST, so a bad row set is
// rejected with total_map's own diagnostics, verbatim — the id check is never
// reached. This is the delegation proof, mirroring the mutable_* cases.
#include <emap/keyed_map.h>

enum class Gem { Ruby, Jade, Opal, Count };

constexpr emap::keyed_map m{
    emap::entry{Gem::Ruby, 11},
    emap::entry{Gem::Jade, 22},
};

int main() {}
