cmake_minimum_required(VERSION 3.23)
project(consumer_bare LANGUAGES CXX)

# The README's "just copy include/emap/total_map.h into your project" path.
#
# There is deliberately NO find_package and NO add_subdirectory here: nothing
# from total_map's CMake package is used. The header is reached by an include
# directory alone, which is what that instruction promises.
#
# Honest scope: this proves the header is self-contained on a bare include path.
# It does not shell out to a raw compiler -- doing so would need per-vendor flag
# spellings (/Zs vs -fsyntax-only) and vcvars on PATH for MSVC, which tests the
# CI plumbing rather than the library.
add_executable(consumer_bare ${TOTAL_MAP_SOURCE_DIR}/tests/consumer/consumer.cpp)
target_include_directories(consumer_bare PRIVATE ${BARE_INCLUDE_DIR})
target_compile_features(consumer_bare PRIVATE cxx_std_20)
