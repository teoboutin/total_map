# Exercises all three documented install paths. Invoked via `cmake -P`.
#
# Required: -DSOURCE_DIR=<repo root> -DWORK_DIR=<scratch dir>
# Optional: -DGENERATOR=<generator> -DCONFIG=<cfg>
#
# install(EXPORT), total_mapConfig.cmake and the version file are otherwise
# entirely unexercised, and packaging is the classic thing broken at a v0.1.0
# release. Every path here is one the README tells users to take.

if(NOT DEFINED SOURCE_DIR OR NOT DEFINED WORK_DIR)
    message(FATAL_ERROR "run_consumer_tests.cmake: SOURCE_DIR and WORK_DIR are required")
endif()

set(gen_args "")
if(DEFINED GENERATOR AND NOT GENERATOR STREQUAL "")
    set(gen_args -G ${GENERATOR})
endif()
set(cfg_args "")
if(DEFINED CONFIG AND NOT CONFIG STREQUAL "")
    set(cfg_args --config ${CONFIG})
endif()

function(run_step desc)
    execute_process(COMMAND ${ARGN} RESULT_VARIABLE rc OUTPUT_VARIABLE o ERROR_VARIABLE e)
    if(NOT rc EQUAL 0)
        message(FATAL_ERROR "CONSUMER TEST FAILED: ${desc}\n--- output ---\n${o}${e}")
    endif()
    message(STATUS "ok: ${desc}")
endfunction()

file(REMOVE_RECURSE ${WORK_DIR})
file(MAKE_DIRECTORY ${WORK_DIR})

# --- Path 1: add_subdirectory / FetchContent -------------------------------
run_step("configure add_subdirectory consumer"
    ${CMAKE_COMMAND} ${gen_args} -S ${SOURCE_DIR}/tests/consumer/subdir
    -B ${WORK_DIR}/subdir -DTOTAL_MAP_SOURCE_DIR=${SOURCE_DIR})
run_step("build add_subdirectory consumer"
    ${CMAKE_COMMAND} --build ${WORK_DIR}/subdir ${cfg_args})

# --- Path 2: install + find_package ----------------------------------------
# The version the consumer requests is PARSED FROM THE HEADER, not written
# here: a literal is a number that goes stale on every release — the v0.2.0
# release shipped with the consumer still requesting 0.1.0, which
# COMPATIBILITY SameMinorVersion rightly rejects. Same regex as the root
# CMakeLists' version-match check, and self-maintaining for the same reason.
file(READ ${SOURCE_DIR}/include/emap/total_map.h _header_contents)
foreach(part MAJOR MINOR PATCH)
    if(NOT _header_contents MATCHES "#define[ \t]+TOTAL_MAP_VERSION_${part}[ \t]+([0-9]+)")
        message(FATAL_ERROR
            "run_consumer_tests.cmake: could not find TOTAL_MAP_VERSION_${part} in the header")
    endif()
    set(_v_${part} ${CMAKE_MATCH_1})
endforeach()
set(header_version ${_v_MAJOR}.${_v_MINOR}.${_v_PATCH})
message(STATUS "consumer will request total_map ${header_version} (parsed from the header)")

run_step("configure total_map for install"
    ${CMAKE_COMMAND} ${gen_args} -S ${SOURCE_DIR} -B ${WORK_DIR}/build-install
    -DCMAKE_INSTALL_PREFIX=${WORK_DIR}/prefix -DTOTAL_MAP_BUILD_TESTS=OFF)
run_step("install total_map"
    ${CMAKE_COMMAND} --install ${WORK_DIR}/build-install ${cfg_args})

# Guard: find_package below must resolve against the INSTALL PREFIX. If the
# Config is missing here but the consumer still configures, it found the package
# somewhere else (a system copy, the build tree) and the test would be lying.
if(NOT EXISTS ${WORK_DIR}/prefix/lib/cmake/total_map/total_mapConfig.cmake)
    file(GLOB_RECURSE found_config ${WORK_DIR}/prefix/*total_mapConfig.cmake)
    message(FATAL_ERROR
        "CONSUMER TEST FAILED: install produced no total_mapConfig.cmake at the "
        "expected location.\nFound instead: ${found_config}")
endif()
message(STATUS "ok: install prefix contains total_mapConfig.cmake")

run_step("configure find_package consumer"
    ${CMAKE_COMMAND} ${gen_args} -S ${SOURCE_DIR}/tests/consumer/find_package
    -B ${WORK_DIR}/find_package -DTOTAL_MAP_SOURCE_DIR=${SOURCE_DIR}
    -DTOTAL_MAP_EXPECTED_VERSION=${header_version}
    -DCMAKE_PREFIX_PATH=${WORK_DIR}/prefix)
run_step("build find_package consumer"
    ${CMAKE_COMMAND} --build ${WORK_DIR}/find_package ${cfg_args})

# --- Path 3: bare header copy ----------------------------------------------
# The README's "just copy include/emap/total_map.h into your project".
file(MAKE_DIRECTORY ${WORK_DIR}/bare/emap)
file(COPY ${SOURCE_DIR}/include/emap/total_map.h DESTINATION ${WORK_DIR}/bare/emap)
run_step("configure bare-copy consumer"
    ${CMAKE_COMMAND} ${gen_args} -S ${SOURCE_DIR}/tests/consumer/bare
    -B ${WORK_DIR}/bare-build -DTOTAL_MAP_SOURCE_DIR=${SOURCE_DIR}
    -DBARE_INCLUDE_DIR=${WORK_DIR}/bare)
run_step("build bare-copy consumer"
    ${CMAKE_COMMAND} --build ${WORK_DIR}/bare-build ${cfg_args})

message(STATUS "all consumer install paths OK")
