// Expects to ABORT: a forged out-of-range key must trip the debug-only assert
// in mutable_total_map's NON-CONST operator[] — the mutable path, which
// tests/assert_death.cpp (const path, on total_map) cannot reach. Also the
// one test that exercises the RUNTIME thaw: `live` below is built at run
// time from a constexpr baseline.
//
// Debug half only, and NDEBUG force-undefined, for the reasons documented in
// tests/assert_death.cpp — they apply verbatim here.
#undef NDEBUG
#include <cassert>

#include <emap/mutable_total_map.h>

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

    constexpr emap::total_map baseline{
        emap::entry{Color::Red, 1},
        emap::entry{Color::Green, 2},
        emap::entry{Color::Blue, 3},
    };
    emap::mutable_total_map live = baseline; // runtime thaw

    // The Count sentinel forged into a live key: index 3 in a 3-slot map.
    // volatile keeps the compiler from constant-folding the subscript.
    volatile Color forged = Color::Count;
    live[const_cast<Color&>(forged)] = 7; // must assert BEFORE the OOB write
    return 0;
}
