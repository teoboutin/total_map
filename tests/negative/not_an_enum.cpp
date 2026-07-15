// Expect: "E must be an enum type"
//
// sizeof forces instantiation. A pointer declaration would NOT instantiate the
// class, no static_assert would fire, and this file would compile cleanly --
// a negative test passing for entirely the wrong reason.
#include <emap/total_map.h>

struct NotAnEnum {
    int x;
};

int force = sizeof(emap::total_map<NotAnEnum, int>);

int main() {}
