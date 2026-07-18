// Expect: "enum counts differ"
//
// A property of the TYPES, not of any rows — instantiating the type is
// enough (sizeof forces it), no construction is attempted. This is also the
// case emap::bijective cannot answer `false` for: the class-scope
// static_assert fires outside any immediate context, so a probe is a hard
// error — which is exactly what this test pins.
#include <emap/bijection.h>

enum class Port { A, B, C, Count };
enum class Duo { D0, D1, Count };

static_assert(sizeof(emap::bijection<Port, Duo>) > 0);

int main() {}
