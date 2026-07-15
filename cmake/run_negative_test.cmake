# Driver for one negative compile test. Invoked via `cmake -P`.
#
# Required: -DBUILD_DIR=<dir> -DTARGET=<target> -DEXPECT=<substring> [-DCONFIG=<cfg>]
#
# Asserts BOTH that the build fails AND that the diagnostic contains EXPECT.
# Both matter: a case broken by a typo also fails to compile, and must not be
# allowed to pass as if it had proven anything.

if(NOT DEFINED BUILD_DIR OR NOT DEFINED TARGET OR NOT DEFINED EXPECT)
    message(FATAL_ERROR "run_negative_test.cmake: BUILD_DIR, TARGET and EXPECT are required")
endif()

set(build_args --build ${BUILD_DIR} --target ${TARGET})
if(DEFINED CONFIG AND NOT CONFIG STREQUAL "")
    list(APPEND build_args --config ${CONFIG})
endif()

execute_process(
    COMMAND ${CMAKE_COMMAND} ${build_args}
    RESULT_VARIABLE result
    OUTPUT_VARIABLE out
    ERROR_VARIABLE err)

set(combined "${out}${err}")

if(result EQUAL 0)
    message(FATAL_ERROR
        "NEGATIVE TEST FAILED: target '${TARGET}' COMPILED, but must be rejected.\n"
        "Expected diagnostic containing: ${EXPECT}")
endif()

string(FIND "${combined}" "${EXPECT}" found)
if(found EQUAL -1)
    message(FATAL_ERROR
        "NEGATIVE TEST FAILED: target '${TARGET}' was rejected, but for the WRONG reason.\n"
        "Expected diagnostic containing: ${EXPECT}\n"
        "--- actual output ---\n${combined}")
endif()

message(STATUS "negative test '${TARGET}': rejected with expected diagnostic")
