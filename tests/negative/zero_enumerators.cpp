// Expect: "was read as having zero enumerators"
//
// `Count` is a REAL enumerator at position 0, not a trailing sentinel, so the
// default trait reads Count == 0 and concludes the enum is empty.
#include <emap/total_map.h>

enum class Agg { Count, Sum, Avg };

int force = sizeof(emap::total_map<Agg, int>);

int main() {}
