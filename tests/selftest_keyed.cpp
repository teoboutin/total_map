// Compiles the keyed sibling's compile-time self-tests against YOUR compiler
// — and, because keyed_map.h includes total_map.h with the macro already
// defined, the flagship header's self-tests in the same TU.
//
//     c++ -std=c++20 -Iinclude -fsyntax-only tests/selftest_keyed.cpp
//
// Success is a clean compile; there is nothing to run.
#define TOTAL_MAP_SELFTEST
#include <emap/keyed_map.h>
int main() {}
