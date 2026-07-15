// Expects to ABORT: a forged out-of-range key must trip the debug-only assert
// in total_map::operator[]. Registered WILL_FAIL, so aborting IS the pass
// condition.
//
// Debug half only. Verifying that the assert compiles away under NDEBUG would
// mean executing the out-of-bounds read, which is UB -- a test whose pass
// depends on UB being benign proves nothing. In debug the assert fires BEFORE
// any OOB access, so this half is well-defined and safe to run.
//
// This test is ABOUT the assert, so it must not depend on the build config.
// Multi-config generators build --config Release, which defines NDEBUG, which
// compiles the assert away -- the binary then exits 0 and the death test fails.
// Undefining NDEBUG before <cassert> pins the assert on regardless of config.
// (<cassert> re-evaluates NDEBUG on every include, by design.)
#undef NDEBUG
#include <cassert>

#include <emap/total_map.h>

#ifdef _MSC_VER
#include <crtdbg.h>
#include <cstdlib>
#endif

enum class Color { Red, Green, Blue, Count };

int main()
{
#ifdef _MSC_VER
    // Without this, abort() raises a modal dialog and HANGS the CI job.
    _set_abort_behavior(0, _WRITE_ABORT_MSG | _CALL_REPORTFAULT);
    _CrtSetReportMode(_CRT_ASSERT, _CRTDBG_MODE_FILE);
    _CrtSetReportFile(_CRT_ASSERT, _CRTDBG_FILE_STDERR);
#endif

    constexpr emap::total_map m{
        emap::entry{Color::Red, 1},
        emap::entry{Color::Green, 2},
        emap::entry{Color::Blue, 3},
    };

    // The Count sentinel forged into a live key: index 3 in a 3-slot map.
    // volatile keeps the compiler from constant-folding the subscript, which
    // would turn this into a compile error instead of the runtime assert.
    volatile Color forged = Color::Count;
    return m[const_cast<Color&>(forged)];
}
