# Driver for the assert death-test. Invoked via `cmake -P`.
#
# Required: -DEXE=<path to test binary> -DEXPECT=<substring of the assert message>
#
# Why not CTest's WILL_FAIL: WILL_FAIL inverts a non-zero RETURN CODE, but an
# assert() terminates via SIGABRT, which CTest classifies as an "Exception" and
# does NOT invert -- so a correctly-aborting death test is reported as a
# failure. Verified: WILL_FAIL reports "Subprocess aborted***Exception".
#
# This driver is also strictly stronger. A WILL_FAIL test passes when the binary
# fails for ANY reason, including a segfault or a typo; asserting the message
# proves the ASSERT is what fired.

if(NOT DEFINED EXE OR NOT DEFINED EXPECT)
    message(FATAL_ERROR "run_death_test.cmake: EXE and EXPECT are required")
endif()

execute_process(
    COMMAND ${EXE}
    RESULT_VARIABLE result
    OUTPUT_VARIABLE out
    ERROR_VARIABLE err)

set(combined "${out}${err}")

if(result EQUAL 0)
    message(FATAL_ERROR
        "DEATH TEST FAILED: '${EXE}' exited 0, but a forged out-of-range key "
        "must trip the debug assert.\nExpected message containing: ${EXPECT}")
endif()

string(FIND "${combined}" "${EXPECT}" found)
if(found EQUAL -1)
    message(FATAL_ERROR
        "DEATH TEST FAILED: '${EXE}' died (${result}), but NOT via the expected assert.\n"
        "Expected message containing: ${EXPECT}\n"
        "--- actual output ---\n${combined}")
endif()

message(STATUS "death test: aborted via the expected assert")
