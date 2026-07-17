cmake_minimum_required(VERSION 3.23)
project(consumer_find_package LANGUAGES CXX)

# Exercises the installed package: exported targets, emap:: namespace, the
# generated Config, the version file, and header placement.
#
# The requested version is passed in by run_consumer_tests.cmake, parsed from
# the header — a literal here went stale at v0.2.0 and failed the release
# gate, because COMPATIBILITY SameMinorVersion rightly rejects an old request.
if(NOT DEFINED TOTAL_MAP_EXPECTED_VERSION)
    message(FATAL_ERROR "pass -DTOTAL_MAP_EXPECTED_VERSION (see run_consumer_tests.cmake)")
endif()
find_package(total_map ${TOTAL_MAP_EXPECTED_VERSION} REQUIRED)

# Exact match, not merely compatible: the version file must carry the header's
# version, or the two published install paths have drifted apart.
if(NOT total_map_VERSION STREQUAL TOTAL_MAP_EXPECTED_VERSION)
    message(FATAL_ERROR
        "found total_map ${total_map_VERSION}, expected ${TOTAL_MAP_EXPECTED_VERSION}")
endif()

add_executable(consumer_find_package ${TOTAL_MAP_SOURCE_DIR}/tests/consumer/consumer.cpp)
target_link_libraries(consumer_find_package PRIVATE emap::total_map)
