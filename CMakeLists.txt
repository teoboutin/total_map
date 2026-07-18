cmake_minimum_required(VERSION 3.23)

project(total_map
    VERSION      0.2.0
    DESCRIPTION  "Compile-time-checked total map from an enum to values"
    HOMEPAGE_URL "https://github.com/teoboutin/total_map"
    LANGUAGES    CXX)

# ---------------------------------------------------------------------------
# Version sync
# ---------------------------------------------------------------------------
# project(VERSION) above and the TOTAL_MAP_VERSION_* macros in the header are two
# hand-maintained copies of one fact, and they are PUBLISHED TO DIFFERENT INSTALL
# PATHS: find_package() resolves against project(VERSION), while a consumer who
# just copied the header -- a supported path, with no build system to ask -- can
# only gate on the macros. So a mismatch does not degrade gracefully; it means
# two consumers of the same release disagree about what version they have.
#
# Nothing else here compares them. A header claiming the wrong version compiles
# clean, passes every selftest, and passes all three consumer install paths, so
# this check is the only thing holding the two sides together.
#
# It reads the three COMPONENTS, not TOTAL_MAP_VERSION_STRING: that string is
# derived from them by stringification and is deliberately no longer a literal in
# the file, so there is nothing there to match.
function(total_map_check_header_version)
    set(header "${CMAKE_CURRENT_SOURCE_DIR}/include/emap/total_map.h")
    file(READ "${header}" contents)

    foreach(part MAJOR MINOR PATCH)
        if(NOT contents MATCHES "#define[ \t]+TOTAL_MAP_VERSION_${part}[ \t]+([0-9]+)")
            message(FATAL_ERROR
                "total_map: could not find TOTAL_MAP_VERSION_${part} in ${header}.\n"
                "If the version macros were renamed or reformatted, this check needs "
                "updating -- do not delete it, or the header and project(VERSION) can "
                "drift apart unnoticed.")
        endif()
        set(v_${part} "${CMAKE_MATCH_1}")
    endforeach()

    set(header_version "${v_MAJOR}.${v_MINOR}.${v_PATCH}")
    if(NOT "${header_version}" STREQUAL "${PROJECT_VERSION}")
        message(FATAL_ERROR
            "total_map: VERSION MISMATCH.\n"
            "  header  (include/emap/total_map.h): ${header_version}\n"
            "  project (CMakeLists.txt):           ${PROJECT_VERSION}\n"
            "Bump TOTAL_MAP_VERSION_MAJOR/MINOR/PATCH and project(VERSION) together. "
            "Both are published: find_package() sees project(VERSION), a bare header "
            "copy sees only the macros.")
    endif()
endfunction()

total_map_check_header_version()

# ---------------------------------------------------------------------------
# The library
# ---------------------------------------------------------------------------
add_library(total_map INTERFACE)
add_library(emap::total_map ALIAS total_map)

# Propagates the C++20 requirement to consumers: a linking target left on an
# older standard is RAISED to C++20 rather than failing, since a compile feature
# acts as a floor over the target's own CXX_STANDARD.
target_compile_features(total_map INTERFACE cxx_std_20)

# BASE_DIRS populates INTERFACE_INCLUDE_DIRECTORIES under $<BUILD_INTERFACE:>;
# install(TARGETS ... FILE_SET HEADERS) adds the $<INSTALL_INTERFACE:> half.
target_sources(total_map
    INTERFACE
    FILE_SET  HEADERS
    BASE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/include
    FILES     ${CMAKE_CURRENT_SOURCE_DIR}/include/emap/total_map.h
              ${CMAKE_CURRENT_SOURCE_DIR}/include/emap/mutable_total_map.h
              ${CMAKE_CURRENT_SOURCE_DIR}/include/emap/keyed_map.h
              ${CMAKE_CURRENT_SOURCE_DIR}/include/emap/bijection.h)

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------
option(TOTAL_MAP_BUILD_TESTS "Build total_map self-tests" ${PROJECT_IS_TOP_LEVEL})

if(TOTAL_MAP_BUILD_TESTS)
    enable_testing()
    add_executable(total_map_selftest tests/selftest.cpp)
    target_link_libraries(total_map_selftest PRIVATE emap::total_map)
    add_test(NAME total_map_selftest COMMAND total_map_selftest)

    add_executable(total_map_selftest_mutable tests/selftest_mutable.cpp)
    target_link_libraries(total_map_selftest_mutable PRIVATE emap::total_map)
    add_test(NAME total_map_selftest_mutable COMMAND total_map_selftest_mutable)

    add_executable(total_map_selftest_keyed tests/selftest_keyed.cpp)
    target_link_libraries(total_map_selftest_keyed PRIVATE emap::total_map)
    add_test(NAME total_map_selftest_keyed COMMAND total_map_selftest_keyed)

    add_executable(total_map_selftest_bijection tests/selftest_bijection.cpp)
    target_link_libraries(total_map_selftest_bijection PRIVATE emap::total_map)
    add_test(NAME total_map_selftest_bijection COMMAND total_map_selftest_bijection)

    include(${CMAKE_CURRENT_SOURCE_DIR}/cmake/NegativeTests.cmake)
    total_map_add_negative_tests()

    # OFF by default: keeps a plain contributor build fast. CI turns it on.
    option(TOTAL_MAP_TEST_MATRIX "Build selftests across standards x NDEBUG" OFF)
    if(TOTAL_MAP_TEST_MATRIX)
        include(${CMAKE_CURRENT_SOURCE_DIR}/cmake/TestMatrix.cmake)
        total_map_add_test_matrix()
    endif()
endif()

# ---------------------------------------------------------------------------
# Install
# ---------------------------------------------------------------------------
# OFF by default when consumed (FetchContent/add_subdirectory), so a consumer's
# `cmake --install` does not silently also install this library.
option(TOTAL_MAP_INSTALL "Generate total_map install rules" ${PROJECT_IS_TOP_LEVEL})

if(TOTAL_MAP_INSTALL)
    include(GNUInstallDirs)
    include(CMakePackageConfigHelpers)

    set(TOTAL_MAP_CMAKEDIR ${CMAKE_INSTALL_LIBDIR}/cmake/total_map)

    install(TARGETS total_map
        EXPORT   total_mapTargets
        FILE_SET HEADERS DESTINATION ${CMAKE_INSTALL_INCLUDEDIR})

    install(EXPORT total_mapTargets
        NAMESPACE   emap::
        DESTINATION ${TOTAL_MAP_CMAKEDIR})

    configure_package_config_file(
        ${CMAKE_CURRENT_SOURCE_DIR}/cmake/total_mapConfig.cmake.in
        ${CMAKE_CURRENT_BINARY_DIR}/total_mapConfig.cmake
        INSTALL_DESTINATION ${TOTAL_MAP_CMAKEDIR})

    # ARCH_INDEPENDENT: header-only, so no ABI — an install from one
    # architecture is legitimately usable from a build targeting another.
    write_basic_package_version_file(
        ${CMAKE_CURRENT_BINARY_DIR}/total_mapConfigVersion.cmake
        COMPATIBILITY SameMinorVersion
        ARCH_INDEPENDENT)

    install(FILES
        ${CMAKE_CURRENT_BINARY_DIR}/total_mapConfig.cmake
        ${CMAKE_CURRENT_BINARY_DIR}/total_mapConfigVersion.cmake
        DESTINATION ${TOTAL_MAP_CMAKEDIR})
endif()
