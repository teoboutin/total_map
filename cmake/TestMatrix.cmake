# Expands standards x NDEBUG into one selftest target per cell, from a single
# configure. Each cell is a compile of tests/selftest.cpp (static_asserts +
# `int main() {}`), so a cell costs ~1-2s and a whole job stays under a minute.
#
# This is the inner layer of the CI matrix. Doing it here rather than as ~138
# GitHub jobs keeps the cost proportional to the work (a job costs 30-60s of
# spin-up to do ~2s of compiling) and, more importantly, means
# `ctest --test-dir build` reproduces exactly what CI runs, locally.
function(total_map_add_test_matrix)
    foreach(std IN ITEMS 20 23 26)
        # Probe + flag spelling both come from CMake's own per-compiler
        # knowledge. Hand-spelling the flag was a real bug: clang-cl 20 does not
        # accept /std:c++23, warns "argument unused", and /WX promoted that to an
        # error -- while check_cxx_compiler_flag had passed, because an unused
        # argument is only a warning during the probe.
        if(NOT DEFINED CMAKE_CXX${std}_STANDARD_COMPILE_OPTION)
            message(STATUS "total_map: C++${std} unsupported by this compiler - skipping")
            continue()
        endif()

        foreach(mode IN ITEMS debug ndebug)
            set(target "selftest_cxx${std}_${mode}")
            add_executable(${target} ${CMAKE_CURRENT_SOURCE_DIR}/tests/selftest.cpp)
            target_link_libraries(${target} PRIVATE emap::total_map)
            set_target_properties(${target} PROPERTIES
                CXX_STANDARD ${std}
                CXX_STANDARD_REQUIRED ON
                CXX_EXTENSIONS OFF)

            if(mode STREQUAL "ndebug")
                target_compile_definitions(${target} PRIVATE NDEBUG)
            endif()

            if(MSVC)
                target_compile_options(${target} PRIVATE
                    /W4 /WX /permissive- /Zc:preprocessor /Zc:__cplusplus /diagnostics:caret)
            else()
                target_compile_options(${target} PRIVATE
                    -Wall -Wextra -Wpedantic -Werror)
            endif()

            add_test(NAME selftest.cxx${std}.${mode} COMMAND ${target})
        endforeach()
    endforeach()

    # Debug only - see tests/assert_death.cpp for why NDEBUG is not tested.
    add_executable(assert_death ${CMAKE_CURRENT_SOURCE_DIR}/tests/assert_death.cpp)
    target_link_libraries(assert_death PRIVATE emap::total_map)

    # Driven by a script rather than CTest's WILL_FAIL: an assert aborts via
    # SIGABRT, which CTest reports as an "Exception" and WILL_FAIL does not
    # invert. The driver also asserts the message, proving the ASSERT fired
    # rather than any other kind of death. See cmake/run_death_test.cmake.
    add_test(NAME assert_death
        COMMAND ${CMAKE_COMMAND}
            -DEXE=$<TARGET_FILE:assert_death>
            -DEXPECT=key out of range
            -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/run_death_test.cmake)
endfunction()
