cmake_minimum_required(VERSION 3.23)
project(consumer_find_package LANGUAGES CXX)

# Exercises the installed package: exported targets, emap:: namespace, the
# generated Config, the version file, and header placement.
find_package(total_map 0.1.0 REQUIRED)

add_executable(consumer_find_package ${TOTAL_MAP_SOURCE_DIR}/tests/consumer/consumer.cpp)
target_link_libraries(consumer_find_package PRIVATE emap::total_map)
