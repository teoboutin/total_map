# Registers one CTest test per negative case. Each case is an EXCLUDE_FROM_ALL
# object library so a normal `cmake --build .` never tries to compile these
# deliberately-broken files.

function(total_map_add_negative_tests)
    # basename => expected diagnostic substring. Each substring is verified to
    # lie within ONE physical source line of its header; the longer messages are
    # multi-line literal concatenations, so a substring spanning lines would
    # never match. Compilers surface these via caret source echo — and clang
    # echoes only the caret's own line, which is why each message literal in
    # the headers must start on the same line as its emap::error call.
    set(cases
        "not_an_enum|E must be an enum type"
        "no_enum_count|trailing sentinel enumerator"
        "zero_enumerators|was read as having zero enumerators"
        "duplicate_key|duplicate enum key"
        "missing_enumerator|enum value not covered"
        "too_many_rows|duplicate enum key"
        "key_out_of_range|enum key >= enum_count_v<E>"
        "mutable_duplicate_key|duplicate enum key"
        "mutable_missing_enumerator|enum value not covered"
        "duplicate_value|duplicate value"
        "projection_collision|values collide under projection"
        "keyed_missing_enumerator|enum value not covered")

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
            # message passed to the emap::error call never appears in the output
            # and every Tier 2 test fails as "wrong reason". (The error function's
            # NAME survives without caret — it rides the diagnostic text itself —
            # so only these free-form substrings need the flag.)
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

    # --- rejection still HARD-ERRORS with exceptions disabled --------------
    # The cases above prove rejection under the default (exceptions-enabled)
    # build. This one proves the guarantee does not quietly depend on exception
    # support: with -fno-exceptions, a bad table must STILL be a hard compile
    # error naming the same reason, not a silent acceptance.
    #
    # It pairs with selftest.no_exceptions in cmake/TestMatrix.cmake, which
    # covers the other half (valid tables build, buildable<> stays a clean
    # true/false). Together they gate both properties the emap::error functions
    # exist to preserve. See the emap::error block in total_map.h.
    #
    # Not MSVC, for the reason given in TestMatrix.cmake: -fno-exceptions is a
    # GCC/Clang spelling with no clean MSVC equivalent.
    if(NOT MSVC)
        set(target "negative_missing_enumerator_no_exceptions")
        add_library(${target} OBJECT EXCLUDE_FROM_ALL
            ${CMAKE_CURRENT_SOURCE_DIR}/tests/negative/missing_enumerator.cpp)
        target_link_libraries(${target} PRIVATE emap::total_map)
        target_compile_features(${target} PRIVATE cxx_std_20)
        target_compile_options(${target} PRIVATE -fno-exceptions)

        add_test(NAME negative.missing_enumerator.no_exceptions
            COMMAND ${CMAKE_COMMAND}
                -DBUILD_DIR=${CMAKE_BINARY_DIR}
                -DTARGET=${target}
                -DEXPECT=enum value not covered
                -DCONFIG=$<CONFIG>
                -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/run_negative_test.cmake)
        set_tests_properties(negative.missing_enumerator.no_exceptions
            PROPERTIES RESOURCE_LOCK negative_build)
    endif()
endfunction()
