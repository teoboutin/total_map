// Expect: "values collide under projection"
//
// The two rows are legitimately DISTINCT values — it is the projection that
// fails to tell them apart, which is why this is a different diagnostic from
// duplicate_value: the fix is usually a better Proj, not different rows.
#include <emap/keyed_map.h>

enum class Gem { Ruby, Jade, Opal, Count };

struct Spec {
    int wireCode;
    int thickness;
};

constexpr emap::keyed_map<Gem, Spec, &Spec::wireCode> m{
    emap::entry{Gem::Ruby, Spec{7, 1}},
    emap::entry{Gem::Jade, Spec{7, 2}},
    emap::entry{Gem::Opal, Spec{12, 3}},
};

int main() {}
