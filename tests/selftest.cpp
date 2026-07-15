// Compiles this library's compile-time self-tests against YOUR compiler.
//
//     c++ -std=c++20 -Iinclude -fsyntax-only tests/selftest.cpp
//
// Success is a clean compile; there is nothing to run. The tests are
// static_asserts, so a failure is a compile error naming the broken guarantee.
// Copy this file into your own project to check the header against your
// toolchain — total_map leans on consteval, requires, and CTAD-driven
// substitution failure, and compilers can disagree there.
#define TOTAL_MAP_SELFTEST
#include <emap/total_map.h>
int main() {}
