// Compiles the snapshot sibling's compile-time self-tests against YOUR
// compiler — and, because snapshot_map.h includes keyed_map.h and
// bijection.h (and they include total_map.h) with the macro already
// defined, EVERY header's self-tests in one TU.
//
//     c++ -std=c++20 -Iinclude -fsyntax-only tests/selftest_snapshot.cpp
//
// Success is a clean compile; there is nothing to run.
#define TOTAL_MAP_SELFTEST
#include <emap/snapshot_map.h>
int main() {}
