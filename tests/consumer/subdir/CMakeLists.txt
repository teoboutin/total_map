cmake_minimum_required(VERSION 3.23)
project(consumer_subdir LANGUAGES CXX)

include(FetchContent)
# SOURCE_DIR consumes the working tree: this tests the local checkout, not a
# published tag.
FetchContent_Declare(total_map SOURCE_DIR ${TOTAL_MAP_SOURCE_DIR})
FetchContent_MakeAvailable(total_map)

add_executable(consumer_subdir ${TOTAL_MAP_SOURCE_DIR}/tests/consumer/consumer.cpp)
target_link_libraries(consumer_subdir PRIVATE emap::total_map)

# The option defaults must hold when NOT top-level, or a consumer's
# `cmake --install` would silently also install total_map.
if(TOTAL_MAP_BUILD_TESTS)
    message(FATAL_ERROR "TOTAL_MAP_BUILD_TESTS must default OFF when consumed")
endif()
if(TOTAL_MAP_INSTALL)
    message(FATAL_ERROR "TOTAL_MAP_INSTALL must default OFF when consumed")
endif()
