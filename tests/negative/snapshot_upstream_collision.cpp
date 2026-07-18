// Expect: "values collide under projection"
//
// There is no negative test OF join — it cannot fail; its signature is its
// proof. This case shows WHERE a collision actually surfaces: upstream, at
// keyed_map construction, with keyed_map's own slot-naming diagnostic,
// before join is ever reached.
#include <emap/snapshot_map.h>

enum class Jack { J0, J1, Count };
enum class Amp { Lo, Hi, Count };

struct Patch {
    int wire;
};
struct Conf {
    int gain;
};

constexpr emap::keyed_map<Jack, Patch, &Patch::wire> kPatches{
    emap::entry{Jack::J0, Patch{7}},
    emap::entry{Jack::J1, Patch{7}},
};

// Never reached: the error above is the point.
constexpr emap::bijection kLink{
    emap::entry{Jack::J0, Amp::Lo},
    emap::entry{Jack::J1, Amp::Hi},
};
constexpr emap::total_map kConfs{
    emap::entry{Amp::Lo, Conf{1}},
    emap::entry{Amp::Hi, Conf{9}},
};
constexpr auto kSnap = emap::join(kPatches, kLink, kConfs);

int main() {}
