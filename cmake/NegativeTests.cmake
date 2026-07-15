# Registers one CTest test per negative case. Each case is an EXCLUDE_FROM_ALL
# object library so a normal `cmake --build .` never tries to compile these
# deliberately-broken files.

function(total_map_add_negative_tests)
    # basename => expected diagnostic substring. Each substring is verified to
    # lie within ONE physical source line of total_map.h; the longer messages are
    # multi-line literal concatenations, so a substring spanning lines would
    # never match. Compilers surface these via caret source echo.
    set(cases
        "not_an_enum|E must be an enum type"
        "no_enum_count|trailing sentinel enumerator"
        "zero_enumerators|was read as having zero enumerators"
        "duplicate_key|duplicate enum key"
        "missing_enumerator|enum value not covered"
        "too_many_rows|duplicate enum key"
        "key_out_of_range|enum key >= enum_count_v<E>")

    foreach(case IN LISTS cases)
        string(REPLACE "|" ";" parts "${case}")
        list(GET parts 0 name)
        list(GET parts 1 expect)

        set(target "negative_${name}")
        add_library(${target} OBJECT EXCLUDE_FROM_ALL
            ${CMAKE_CURRENT_SOURCE_DIR}/tests/negative/${name}.cpp)
        target_link_libraries(${target} PRIVATE emap::total_map)

        # Negative cases run at C++20 only: the diagnostics do not vary by
        # standard, so sweeping them would buy nothing.
        target_compile_features(${target} PRIVATE cxx_std_20)

        # -Werror would turn an unrelated warning into a spurious "rejection",
        # so these targets deliberately do NOT get the warning flags.
        if(MSVC)
            # MSVC does not echo source lines by default; without caret the
            # thrown message never appears in the output and every Tier 2 test
            # fails as "wrong reason".
            target_compile_options(${target} PRIVATE /diagnostics:caret /Zc:__cplusplus)
        endif()

        add_test(NAME negative.${name}
            COMMAND ${CMAKE_COMMAND}
                -DBUILD_DIR=${CMAKE_BINARY_DIR}
                -DTARGET=${target}
                -DEXPECT=${expect}
                -DCONFIG=$<CONFIG>
                -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/run_negative_test.cmake)

        # All cases drive `cmake --build` against the SAME build tree.
        # Without this lock, `ctest -j` races concurrent builds in one directory.
        set_tests_properties(negative.${name} PROPERTIES RESOURCE_LOCK negative_build)
    endforeach()
endfunction()
