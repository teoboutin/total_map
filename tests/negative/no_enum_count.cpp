// Expect: "could not determine the number of enumerators"
//
// Dir has no trailing `Count` sentinel and no emap::enum_count specialization,
// so N is undiscoverable.
#include <emap/total_map.h>

enum class Dir { North, East, South, West };

int force = sizeof(emap::total_map<Dir, int>);

int main() {}
