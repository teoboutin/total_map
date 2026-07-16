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

    # --- exceptions disabled ---------------------------------------------
    # The header must build with NO exception support. This is not hypothetical
    # portability box-ticking: it is the regression gate for a bug that made the
    # header UNUSABLE for any build passing -fno-exceptions (embedded, game,
    # LLVM/Chromium-style, and opted-in Emscripten). The checks in make_perm
    # used to be `throw`, and a throw-expression is ill-formed under
    # -fno-exceptions even where it is never taken -- so instantiating make_perm
    # failed and even a VALID table would not compile. See the emap::error block
    # in total_map.h.
    #
    # Compiling tests/selftest.cpp is the whole proof, because it asserts both
    # halves of the guarantee: valid tables construct (kBasic and friends), and
    # emap::buildable<> still yields true/false rather than a hard error (the
    # kMissing / kDuplicate / kOversized asserts).
    #
    # NOT MSVC (which sets MSVC=1 for clang-cl too): -fno-exceptions is a
    # GCC/Clang spelling, and MSVC has no clean equivalent -- omitting /EHsc
    # leaves throw compilable but with unwinding warnings, so it would not test
    # the same thing. check_cxx_compiler_flag is deliberately not used to probe:
    # clang-cl accepts unknown flags with only a warning, which the probe passes
    # (the same trap documented on the standards loop above).
    if(NOT MSVC)
        add_executable(selftest_no_exceptions ${CMAKE_CURRENT_SOURCE_DIR}/tests/selftest.cpp)
        target_link_libraries(selftest_no_exceptions PRIVATE emap::total_map)
        set_target_properties(selftest_no_exceptions PROPERTIES
            CXX_STANDARD 20
            CXX_STANDARD_REQUIRED ON
            CXX_EXTENSIONS OFF)
        target_compile_options(selftest_no_exceptions PRIVATE
            -fno-exceptions -Wall -Wextra -Wpedantic -Werror)
        add_test(NAME selftest.no_exceptions COMMAND selftest_no_exceptions)
    endif()

    # Debug only - see tests/assert_death.cpp for why NDEBUG is not tested.
    add_executable(assert_death ${CMAKE_CURRENT_SOURCE_DIR}/tests/assert_death.cpp)
    target_link_libraries(assert_death PRIVATE emap::total_map)

    # Driven by a script rather than CTest's WILL_FAIL: an assert aborts via
    # SIGABRT, which CTest reports as an "Exception" and WILL_FAIL does not
    # invert. The driver also asserts the message, proving the ASSERT fired
    # rather than any other kind of death. See cmake/run_death_test.cmake.
    #
    # The emulator must be forwarded: add_test() would apply it on its own, but
    # the driver runs the binary itself, so it has to be told. Semicolons are
    # escaped because an emulator may be a list (launcher + args), which would
    # otherwise split into separate arguments to `cmake -P`. Empty natively.
    set(death_emulator "")
    if(CMAKE_CROSSCOMPILING_EMULATOR)
        string(REPLACE ";" "\\;" escaped_emulator "${CMAKE_CROSSCOMPILING_EMULATOR}")
        set(death_emulator "-DEMULATOR=${escaped_emulator}")
    endif()

    add_test(NAME assert_death
        COMMAND ${CMAKE_COMMAND}
            -DEXE=$<TARGET_FILE:assert_death>
            -DEXPECT=key out of range
            ${death_emulator}
            -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/run_death_test.cmake)
endfunction()
