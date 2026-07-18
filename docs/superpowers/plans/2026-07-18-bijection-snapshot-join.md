# bijection + snapshot_map/join Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `emap::bijection<E1, E2>` (Step 2) and `emap::snapshot_map<K, V, N>` + `emap::join` (Step 3) of `docs/DESIGN-keyed-refinements.md`, fully tested, plus the owed documentation.

**Architecture:** Two new single-file headers in `include/emap/`, each depending on already-shipped headers only. `bijection` is a `total_map<E1, E2>` refinement (public inheritance, consteval injectivity check at construction, count equality by `static_assert`) licensing `inverse()`/`inverse_at()` through a private tagged constructor. `snapshot_map` is a sealed parallel-array table whose sole producer is the consteval free function `join(keyed_map, bijection, total_map)` — check-free by signature.

**Tech Stack:** C++20 header-only library; CMake ≥ 3.23 + CTest; no dependencies.

**Authoritative spec:** `docs/DESIGN-keyed-refinements.md` (committed, converged — decisions there are settled; do not relitigate them). Read it in full, then read `include/emap/total_map.h` top to bottom and `include/emap/keyed_map.h` top to bottom before writing any code. keyed_map.h is the structural template for bijection.h; total_map.h is the machinery reference.

## Global Constraints

(From the design doc §6 — every task implicitly includes these.)

- License header **verbatim** (copy lines 1–27 of `include/emap/keyed_map.h`) at the top of every new header.
- Big top doc comment in total_map.h's register: WHAT IT IS / INTENDED USE / CONSTRUCTION / WHAT THE PROOF LICENSES / DIAGNOSTICS / REQUIREMENTS & GUARANTEES; reasoning recorded, caveats named, CAPS for emphasis. The plan supplies this text — adapt phrasing only to fix errors, not to shorten.
- Include guard `<NAME>_INCLUDED`; sibling emap includes in quote form **first** (`#include "total_map.h"`), then standard headers. Version macros live in total_map.h only.
- Standard-library budget: `<array> <cassert> <concepts> <cstddef> <type_traits> <utility>` only. **Never** `<functional>`, `<optional>`, `<ranges>`, exceptions. Selftest sections (inside `#ifdef TOTAL_MAP_SELFTEST`) may additionally include `<string_view>` and sibling emap headers.
- Rejections via declared-but-undefined `emap::error::` functions; the message literal **starts on the physical line of the call**; slot payloads ride **template arguments** (checks unrolled over `index_sequence` — a loop variable cannot be a template argument).
- Mirror total_map's E/V `static_assert`s naming the **new** type, so diagnostics blame the type the user wrote.
- Deleted assignment on immutable types; consteval construction everywhere except deliberately-runtime lookups (`constexpr` `find` / `inverse_at`).
- Selftests inline, gated on `TOTAL_MAP_SELFTEST`, **fresh type names** — the snapshot driver compiles every header's selftests in ONE TU, so no selftest identifier may collide with the existing ones. Taken enums: `Bare Chan Color Dir Gauge Gem Hue Lane Metric Odd Stat Tone`; taken structs: `Mute Spec Style Weight`; taken constants include `kRowsOk kRowsCollide kRowsPartial kPromoted kFromFn kDoubled kCodes` and more — this plan's names (`Port Pin Ring Jack Amp Patch Conf Badge`, `kWires…`, `kSnap…`, `kLink`, …) were checked against the full inventory; keep them exactly.
- Negative tests: `tests/negative/<case>.cpp` with `// Expect: "substring"` first line; the substring must lie within ONE physical source line of the header.
- Formatting: match the existing headers (4-space indent, `{` on its own line for functions/classes, ~95-column lines, comment density like keyed_map.h). There is a `.clang-format` only if the repo has one — otherwise imitate by eye.
- Git: commit at the end of every task; messages in the repo's style (imperative, descriptive, no `feat:` prefixes — e.g. "Add emap::keyed_map, the id-proven sibling").
- Do NOT bump version macros or `project(VERSION)` — releases are a separate process (`docs/releasing.md`); features accumulate under CHANGELOG `[Unreleased]`.

## File Map

| File | Role |
|---|---|
| `include/emap/bijection.h` | Create — Tasks 1–4 (type, `inverse_at`, `inverse`, predicate, inline selftests) |
| `tests/selftest_bijection.cpp` | Create — Task 1 (3-line driver) |
| `include/emap/snapshot_map.h` | Create — Tasks 7–8 (type + `join`, inline selftests) |
| `tests/selftest_snapshot.cpp` | Create — Task 7 (3-line driver) |
| `tests/negative/bijection_repeated_value.cpp`, `…_count_mismatch.cpp`, `…_missing_enumerator.cpp` | Create — Task 5 |
| `tests/negative/snapshot_upstream_collision.cpp` | Create — Task 9 |
| `CMakeLists.txt` | Modify — Tasks 1, 7 (selftest executables + FILE_SET) |
| `cmake/NegativeTests.cmake` | Modify — Tasks 5, 9 (cases list) |
| `cmake/TestMatrix.cmake` | Modify — Tasks 6, 10 (TU sweep; Task 6 also fixes the keyed omission) |
| `tests/consumer/consumer.cpp` | Modify — Tasks 6, 10 (runtime uses) |
| `README.md`, `CHANGELOG.md` | Modify — Task 11 (keyed_map's owed docs + the two new headers) |

**Verification commands used throughout** (run from the repo root):

```bash
# quick single-TU syntax check
c++ -std=c++20 -Iinclude -Wall -Wextra -Wpedantic -Werror -fsyntax-only tests/selftest_bijection.cpp

# the full local sweep the design doc requires (standards x exceptions x NDEBUG)
for std in c++20 c++23; do for exc in "" "-fno-exceptions"; do for nd in "" "-DNDEBUG"; do
  echo "== $std $exc $nd =="
  c++ -std=$std $exc $nd -Iinclude -Wall -Wextra -Wpedantic -Werror -fsyntax-only tests/selftest_bijection.cpp || exit 1
done; done; done

# full suite
cmake -S . -B build -DTOTAL_MAP_TEST_MATRIX=ON && cmake --build build -j && ctest --test-dir build --output-on-failure

# consumer install paths (not registered in ctest; run explicitly)
cmake -DSOURCE_DIR=$PWD -DWORK_DIR=$PWD/build/consumer-work -P cmake/run_consumer_tests.cmake
```

---

### Task 1: bijection.h — the count-matched, value-distinct core

**Files:**
- Create: `include/emap/bijection.h`
- Create: `tests/selftest_bijection.cpp`
- Modify: `CMakeLists.txt` (FILE_SET list ~line 72; test block ~line 91)

**Interfaces:**
- Consumes: `emap::total_map<E, V>`, `emap::entry`, `emap::error::` mechanism, `enum_count_v`, `has_enum_count` (all from total_map.h).
- Produces: `emap::bijection<E1, E2>` — class template, public `total_map<E1, E2>` base; consteval ctors `bijection(const total_map<E1,E2>&)` (implicit promote), `bijection(const std::array<entry<E1,E2>, M>&)`, variadic `bijection(Rows...)`; deduction guides for all three; private `static consteval base check(const base&)` walker; `emap::error::enum_value_repeated<FirstSlot, SecondSlot>(const char*)`. Tasks 2–4 add members to this class.

- [ ] **Step 1: Write the failing test — the driver**

Create `tests/selftest_bijection.cpp`:

```cpp
// Compiles the bijection sibling's compile-time self-tests against YOUR
// compiler — and, because bijection.h includes total_map.h with the macro
// already defined, the flagship header's self-tests in the same TU.
//
//     c++ -std=c++20 -Iinclude -fsyntax-only tests/selftest_bijection.cpp
//
// Success is a clean compile; there is nothing to run.
#define TOTAL_MAP_SELFTEST
#include <emap/bijection.h>
int main() {}
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `c++ -std=c++20 -Iinclude -Wall -Wextra -Wpedantic -Werror -fsyntax-only tests/selftest_bijection.cpp`
Expected: FAIL — `emap/bijection.h: No such file or directory`.

- [ ] **Step 3: Write the header**

Create `include/emap/bijection.h`. License header: copy lines 1–27 of `include/emap/keyed_map.h` verbatim. Then:

```cpp
// ============================================================================
// bijection.h  —  emap::bijection<E1, E2>
// A total_map between two same-sized enums whose stored values are proven
// pairwise distinct — a compile-time bijection, invertible without re-proof.
// Requires C++20.
// ----------------------------------------------------------------------------
//
// WHAT IT IS
//   emap::bijection<E1, E2> IS a total_map<E1, E2> (public inheritance, and
//   meant that way: everything proven about the base holds here) that has
//   additionally proven, at construction, that no two rows carry the same E2
//   value. The header also demands enum_count_v<E1> == enum_count_v<E2> — a
//   static_assert, because it is a property of the TYPES, not of any rows.
//   Between finite sets of equal size, total + injective implies surjective,
//   so the instance is a proven BIJECTION and no separate surjectivity check
//   ever runs.
//
// INTENDED USE
//   Two enums that are one set with two spellings: a wire protocol's codes
//   and the internal enum, a save-format id and the live id, scan codes and
//   logical keys.
//
//       enum class Port { A, B, C, Count };
//       enum class Pin  { P0, P1, P2, Count };
//
//       constexpr emap::bijection wires{
//           emap::entry{Port::A, Pin::P2},
//           emap::entry{Port::B, Pin::P0},
//           emap::entry{Port::C, Pin::P1},  // repeat a Pin -> compile error
//       };
//       static_assert(wires[Port::A] == Pin::P2);            // inherited
//       static_assert(wires.inverse()[Pin::P2] == Port::A);  // licensed
//
//   E1 == E2 is legal and useful: bijection<E, E> is a proven PERMUTATION of
//   one enum (a successor cycle, a remapping), and inverse() simply returns
//   the same type.
//
// CONSTRUCTION — always through a proven table
//   Mirrors keyed_map exactly. The primary constructor PROMOTES an already-
//   proven total_map<E1, E2>; consteval and IMPLICIT, deliberately: an API
//   taking bijection can be handed a total_map and the missing proof is
//   demanded — at compile time — right at the call site. Row / array
//   authoring forms are sugar that builds the total_map first, so key
//   diagnostics are total_map's own, verbatim; what this header adds is the
//   value-distinctness check, run on the proven table before the base is
//   initialized. There is deliberately NO from(): the promote path composes —
//   emap::bijection<E1, E2>{emap::total_map<E1, E2>::from(fn)}. And there is
//   no path FROM emap::mutable_total_map, as for every refinement: a table
//   that can drift is exactly the object this proof no longer covers.
//
// WHAT THE PROOF LICENSES — inverse(), and its single-slot form inverse_at()
//   inverse() returns bijection<E2, E1>: the whole map read the other way,
//   O(1) in both directions once materialized. consteval, like every
//   construction path — materializing a map IS construction. It does NOT
//   re-run any check: the inverse of a proven bijection is proven by the
//   same evidence, so inverse() enters through a private tagged constructor
//   (see the door below for the reasoning). Round trip:
//   b.inverse()[b[e]] == e for every key, and inverse().inverse() compares
//   equal to b.
//
//   inverse_at(E2) returns the ONE key mapping to that value, without
//   materializing the inverse map — constexpr, because runtime lookup of a
//   compile-time-proven table is the point. It returns E1 BY VALUE, no
//   pointer: unlike keyed_map::find, nothing here is partial — bijectivity
//   makes the inverse total. O(N) scan, nothing at enumerator counts. Its
//   VALUE argument is checked like operator[]'s key: debug assert only — a
//   forged E2 (a cast, or a Count sentinel used as a live value) asserts
//   under !NDEBUG and returns a well-defined but WRONG key in release.
//
// DIAGNOSTICS
//   * A repeated E2 value: `enum value repeated`, with the two colliding
//     slots as TEMPLATE ARGUMENTS of the error function (measured, not
//     stylistic — see the emap::error block in keyed_map.h; same unrolled-
//     check consequence). Distinct from total_map's `duplicate enum key`:
//     here the VALUES are enumerators of E2, and with equal counts a value
//     hit twice means another E2 value is necessarily missed.
//   * Unequal counts: a static_assert containing `enum counts differ`. NOTE
//     THE EDGE this implies: a class-scope static_assert fires at implicit
//     instantiation of the TYPE, outside any immediate context, so
//     emap::bijective on rows between count-mismatched enums is a HARD
//     ERROR, not `false` — the same documented behavior as buildable's NTTP
//     edges and total_map's own E/V asserts. bijective answers for tables
//     between count-compatible enums; between count-incompatible enums
//     there is nothing to ask.
//   * Key-side failures (missing enumerator, duplicate key, out of range):
//     total_map's own messages, verbatim, from the delegated construction.
//
// REQUIREMENTS & GUARANTEES
//   total_map<E1, E2>'s, exactly (contiguity and enum_count discovery for
//   E1, rejection of bad row sets — delegated), plus:
//   * E2 must itself be an enum with a discoverable count (same three-way
//     customization as E1's; see enum_count in total_map.h), and
//     enum_count_v<E1> == enum_count_v<E2>.
//   * Whether a row set would be accepted is again a compile-time predicate,
//     emap::bijective<Arr> / emap::bijective<&Arr>, mirroring
//     emap::buildable's two passing forms and restrictions. It answers for
//     the WHOLE construction, so bijective subsumes buildable.
// ============================================================================

#ifndef BIJECTION_INCLUDED
#define BIJECTION_INCLUDED

// The quote form, deliberately: it resolves relative to THIS file first, so
// the headers can be copied into a project as one emap/ directory and work
// with no include-path setup — the same no-build-system install path
// total_map.h supports alone. Version macros live in total_map.h; one
// library, one version.
#include "total_map.h"

#include <array>
#include <cassert>
#include <concepts>
#include <cstddef>
#include <type_traits>
#include <utility>

namespace emap
{

// A rejected table is reported the same way total_map's are — a call to a
// declared-but-undefined function is not a constant expression — and for the
// same -fno-exceptions reasons (see the emap::error block in total_map.h).
// The message literal starts on the call's own line, as clang's caret echo
// requires; the two colliding SLOTS ride the template arguments, for the
// measured reasons documented on keyed_map.h's emap::error block. Slots are
// enum order, so slot I's key is key_at(I).
namespace error
{
template <std::size_t FirstSlot, std::size_t SecondSlot>
void enum_value_repeated(const char* why);
} // namespace error

template <class E1, class E2> class bijection : public total_map<E1, E2>
{
    // Mirrors total_map's guards so a bad E1/E2 is reported against the type
    // actually named in the source; the base re-checks E1 behind these, but
    // by then the diagnostic would blame the delegation target. E2 gets the
    // full treatment here because for the BASE it is only a value type — the
    // enum-ness and count of E2 are this refinement's own requirements.
    static_assert(std::is_enum_v<E1>, "emap::bijection: E1 must be an enum type.");
    static_assert(std::is_enum_v<E2>,
        "emap::bijection: E2 must be an enum type — the VALUES of a bijection are "
        "enumerators. For a map to non-enum values, use total_map or keyed_map.");
    static_assert(has_enum_count<E1>,
        "emap::bijection: could not determine the number of enumerators of E1. Add a "
        "trailing sentinel enumerator (`Count` by default), specialize "
        "emap::enum_count<E1>::value, or claim E1 with an emap::enum_count_policy<E1>.");
    static_assert(has_enum_count<E2>,
        "emap::bijection: could not determine the number of enumerators of E2. Add a "
        "trailing sentinel enumerator (`Count` by default), specialize "
        "emap::enum_count<E2>::value, or claim E2 with an emap::enum_count_policy<E2>.");

    // A property of the TYPES, not of any rows — which is why it is a
    // static_assert and not an emap::error call. Consequence (documented in
    // DIAGNOSTICS above): emap::bijective hard-errors, rather than answering
    // false, for rows between count-mismatched enums.
    static_assert(enum_count_v<E1> == enum_count_v<E2>,
        "emap::bijection: enum counts differ. A total injective map between finite "
        "sets exists only at equal sizes, so no bijection between these enums can "
        "exist. If either count surprises you, check the sentinel it was read from "
        "(see enum_count in total_map.h).");

    using base = total_map<E1, E2>;

    // --- the value-distinctness check: pairwise over the PROVEN table ---
    // A deliberate ~20-line twin of keyed_map's check_against_earlier /
    // check_all (with the identity projection over V = E2, and bijection's
    // own diagnostic). NOT factored into a shared detail:: helper: the shape
    // is pinned by the measured template-argument constraint both twins
    // document, so they cannot drift apart in substance, and keeping it
    // local keeps this header depending on total_map.h alone.
    static consteval bool values_equal(const base& tm, std::size_t a, std::size_t b)
    {
        return tm[base::key_at(a)] == tm[base::key_at(b)];
    }

    template <std::size_t FirstSlot, std::size_t SecondSlot> static consteval void report()
    {
        error::enum_value_repeated<FirstSlot, SecondSlot>("emap::bijection: enum value repeated. Two rows map to the same E2 "
            "enumerator — and with equal counts, a value hit twice means some other "
            "E2 enumerator is never hit at all, so the table cannot be a bijection. "
            "The template arguments name the colliding slots, in enum order: "
            "key_at(slot) is the row.");
    }

    // Slot J against every earlier slot; then every J. Empty comma folds
    // (J == 0, and N == 1 overall) are well-formed no-ops.
    template <std::size_t J, std::size_t... Is>
    static consteval void check_against_earlier(const base& tm, std::index_sequence<Is...>)
    {
        ((values_equal(tm, Is, J) ? report<Is, J>() : void()), ...);
    }

    template <std::size_t... Js>
    static consteval void check_all(const base& tm, std::index_sequence<Js...>)
    {
        (check_against_earlier<Js>(tm, std::make_index_sequence<Js>{}), ...);
    }

    // Returns its argument so the promoting constructor can initialize the
    // base from the checked table in one expression.
    static consteval base check(const base& tm)
    {
        check_all(tm, std::make_index_sequence<base::size()>{});
        return tm;
    }

  public:
    // PROMOTE — the primary constructor: an already-proven total_map, with
    // the value-distinctness check run before the base is initialized.
    // consteval and IMPLICIT, deliberately (see CONSTRUCTION above).
    consteval bijection(const base& tm) : base(check(tm)) {}

    // Authoring sugar. Each form builds the total_map FIRST and promotes it,
    // so key validation and its diagnostics stay in exactly one place —
    // total_map — and the value check in exactly one other: check(), above.
    template <std::size_t M>
    consteval bijection(const std::array<entry<E1, E2>, M>& in) : bijection(base(in))
    {
    }

    template <std::same_as<entry<E1, E2>>... Rows>
    consteval bijection(Rows... rows) : bijection(base(rows...))
    {
    }
};

// Deduction guides, mirroring the base's own — both enums come off the rows
// (or the promoted table), so unlike keyed_map nothing is left to name.
template <class E1, class E2> bijection(const total_map<E1, E2>&) -> bijection<E1, E2>;
template <class E1, class E2, std::size_t M>
bijection(const std::array<entry<E1, E2>, M>&) -> bijection<E1, E2>;
template <class E1, class E2, class... Rest>
bijection(entry<E1, E2>, Rest...) -> bijection<E1, E2>;

} // namespace emap

// ============================================================================
// SELF-TESTS
// Same contract as total_map.h's: opt-in via TOTAL_MAP_SELFTEST, compile-time
// only, a clean compile is the pass. Self-contained — fresh type names, so it
// holds even in a TU where the other headers' selftests are also compiled
// (tests/selftest_snapshot.cpp is exactly such a TU). See
// tests/selftest_bijection.cpp for the three-line driver.
// ============================================================================
#ifdef TOTAL_MAP_SELFTEST
namespace emap::selftest
{

enum class Port { A, B, C, Count };
enum class Pin { P0, P1, P2, Count };

// --- CTAD from rows: both enums come off the entries ---
constexpr emap::bijection kWires{
    entry{Port::A, Pin::P2}, entry{Port::B, Pin::P0}, entry{Port::C, Pin::P1}};
static_assert(std::is_same_v<decltype(kWires), const emap::bijection<Port, Pin>>);

// the base's contract is inherited intact: total lookup, size, key recovery
static_assert(kWires[Port::A] == Pin::P2);
static_assert(kWires.size() == 3);
static_assert(kWires.key_at(2) == Port::C);

// --- IS-A total_map: the proof only ever ADDS ---
static_assert(std::is_base_of_v<emap::total_map<Port, Pin>, decltype(kWires)>);
static_assert(std::convertible_to<const emap::bijection<Port, Pin>&,
                                  const emap::total_map<Port, Pin>&>);
// the all_unique predicate agrees with the proof the type already carries
static_assert(emap::all_unique(kWires));
// equality reaches through the base, in both directions
constexpr emap::total_map kWiresPlain{
    entry{Port::B, Pin::P0}, entry{Port::C, Pin::P1}, entry{Port::A, Pin::P2}};
static_assert(kWires == kWiresPlain);
static_assert(kWiresPlain == kWires);

// --- promote: an already-proven table, CTAD from the primary constructor ---
constexpr emap::bijection kWiresPromoted = kWiresPlain;
static_assert(std::is_same_v<decltype(kWiresPromoted), const emap::bijection<Port, Pin>>);
static_assert(kWiresPromoted == kWires);

// --- the array authoring form ---
constexpr emap::bijection kWiresFromArray{std::array{
    entry{Port::A, Pin::P2}, entry{Port::B, Pin::P0}, entry{Port::C, Pin::P1}}};
static_assert(kWiresFromArray == kWires);

// authoring through from(): the promote path composes, no from() of its own
constexpr emap::bijection<Port, Pin> kWiresFromFn{emap::total_map<Port, Pin>::from(
    [](Port p) { return static_cast<Pin>((static_cast<int>(p) + 1) % 3); })};
static_assert(kWiresFromFn[Port::A] == Pin::P1);

// --- immutable, like the base: proofs must outlive their statement ---
static_assert(!std::is_copy_assignable_v<emap::bijection<Port, Pin>>);
static_assert(!std::is_move_assignable_v<emap::bijection<Port, Pin>>);

} // namespace emap::selftest
#endif // TOTAL_MAP_SELFTEST

#endif // BIJECTION_INCLUDED
```

- [ ] **Step 4: Run the driver to verify it passes**

Run: `c++ -std=c++20 -Iinclude -Wall -Wextra -Wpedantic -Werror -fsyntax-only tests/selftest_bijection.cpp`
Expected: clean compile, no output.

- [ ] **Step 5: Wire into CMake**

In `CMakeLists.txt`, add the header to the FILE_SET (after the keyed_map.h line):

```cmake
              ${CMAKE_CURRENT_SOURCE_DIR}/include/emap/keyed_map.h
              ${CMAKE_CURRENT_SOURCE_DIR}/include/emap/bijection.h)
```

and the selftest executable (after the `total_map_selftest_keyed` block):

```cmake
    add_executable(total_map_selftest_bijection tests/selftest_bijection.cpp)
    target_link_libraries(total_map_selftest_bijection PRIVATE emap::total_map)
    add_test(NAME total_map_selftest_bijection COMMAND total_map_selftest_bijection)
```

- [ ] **Step 6: Run the suite**

Run: `cmake -S . -B build && cmake --build build -j && ctest --test-dir build --output-on-failure`
Expected: all tests pass, including the new `total_map_selftest_bijection`.

- [ ] **Step 7: Commit**

```bash
git add include/emap/bijection.h tests/selftest_bijection.cpp CMakeLists.txt
git commit -m "Add emap::bijection: the count-matched, value-distinct core"
```

---

### Task 2: inverse_at — the single-slot inverse lookup

**Files:**
- Modify: `include/emap/bijection.h` (public section of the class + selftests)

**Interfaces:**
- Consumes: `bijection` class from Task 1 (`base`, `base::key_at`, `base::size`, inherited `operator[]`).
- Produces: `constexpr E1 inverse_at(E2 v) const` — total, returns by value; debug-asserted argument.

- [ ] **Step 1: Write the failing test**

Append to the selftest namespace in `include/emap/bijection.h` (before the closing `} // namespace emap::selftest`):

```cpp
// --- inverse_at: the single-slot inverse, licensed by the proof ---
// Total, so by value — no pointer: bijectivity means every E2 value has
// exactly one key, and the signature says so.
static_assert(kWires.inverse_at(Pin::P0) == Port::B);
static_assert(kWires.inverse_at(Pin::P1) == Port::C);
static_assert(kWires.inverse_at(Pin::P2) == Port::A);
```

- [ ] **Step 2: Run it to verify it fails**

Run: `c++ -std=c++20 -Iinclude -Wall -Wextra -Wpedantic -Werror -fsyntax-only tests/selftest_bijection.cpp`
Expected: FAIL — no member named `inverse_at`.

- [ ] **Step 3: Implement**

Add to the public section of `bijection` (after the variadic constructor):

```cpp
    // SINGLE-SLOT inverse lookup — the proof's cheap half, without
    // materializing the whole inverse map. constexpr, not consteval: runtime
    // lookup of a compile-time-proven table is the point. Returns E1 BY
    // VALUE — bijectivity makes the inverse TOTAL, so unlike keyed_map::find
    // there is no partial case to be honest about. O(N) scan, nothing at
    // enumerator counts.
    //
    // The debug assert mirrors operator[]'s: a forged E2 — a cast, or a
    // Count sentinel used as a live value — asserts under !NDEBUG; in
    // release the scan returns a well-defined but WRONG key for a forged
    // value, which is an array's contract stated for the value side.
    constexpr E1 inverse_at(E2 v) const
    {
        assert(static_cast<std::size_t>(v) < base::size() &&
               "emap::bijection: value out of range (a sentinel used as a live value?)");
        for (std::size_t i = 0; i + 1 < base::size(); ++i) {
            if ((*this)[base::key_at(i)] == v) {
                return base::key_at(i);
            }
        }
        // Not a guess: the proof says v IS some slot's value, and no earlier
        // slot matched, so it is the last one's. (This is also what lets the
        // function end without a control path the compiler must warn about.)
        return base::key_at(base::size() - 1);
    }
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `c++ -std=c++20 -Iinclude -Wall -Wextra -Wpedantic -Werror -fsyntax-only tests/selftest_bijection.cpp`
Expected: clean compile. Also run with `-DNDEBUG` added — still clean (guards the assert's variable use).

- [ ] **Step 5: Commit**

```bash
git add include/emap/bijection.h
git commit -m "License inverse_at, the single-slot inverse lookup"
```

---

### Task 3: the tagged door and inverse()

**Files:**
- Modify: `include/emap/bijection.h` (private door + public `inverse()` + selftests)

**Interfaces:**
- Consumes: Task 2's `inverse_at` (the door's base-initializer calls it on the forward map); `total_map::from`.
- Produces: `consteval bijection<E2, E1> inverse() const`; private `struct proven_inverse_t {}` + `consteval bijection(proven_inverse_t, const bijection<E2, E1>&)`; `template <class, class> friend class bijection`.

- [ ] **Step 1: Write the failing test**

Append to the selftest namespace:

```cpp
// --- inverse(): the licensed operation — round trip over every key ---
constexpr auto kUnwires = kWires.inverse();
static_assert(std::is_same_v<decltype(kUnwires), const emap::bijection<Pin, Port>>);
static_assert([] {
    for (Port p : decltype(kWires)::keys()) {
        if (kUnwires[kWires[p]] != p) {
            return false;
        }
    }
    return true;
}());
static_assert([] {
    for (Pin q : decltype(kUnwires)::keys()) {
        if (kWires[kUnwires[q]] != q) {
            return false;
        }
    }
    return true;
}());

// inverse().inverse(): type and value identity
static_assert(std::is_same_v<decltype(kUnwires.inverse()), emap::bijection<Port, Pin>>);
static_assert(kUnwires.inverse() == kWires);

// the materialized inverse and the single-slot form agree
static_assert(kUnwires[Pin::P0] == kWires.inverse_at(Pin::P0));

// --- a permutation: E1 == E2 is a legal, useful bijection ---
enum class Ring { R0, R1, R2, Count };
constexpr emap::bijection kSucc{
    entry{Ring::R0, Ring::R1}, entry{Ring::R1, Ring::R2}, entry{Ring::R2, Ring::R0}};
static_assert(std::is_same_v<decltype(kSucc), const emap::bijection<Ring, Ring>>);
static_assert(kSucc.inverse_at(Ring::R1) == Ring::R0); // the predecessor
constexpr auto kPred = kSucc.inverse();
static_assert(kPred[Ring::R0] == Ring::R2);
static_assert(kPred.inverse() == kSucc);
```

- [ ] **Step 2: Run it to verify it fails**

Run: `c++ -std=c++20 -Iinclude -Wall -Wextra -Wpedantic -Werror -fsyntax-only tests/selftest_bijection.cpp`
Expected: FAIL — no member named `inverse`.

- [ ] **Step 3: Implement the door and inverse()**

In the **private** section of `bijection`, after `check()`:

```cpp
    // --- the tagged door: check-free construction of a PROVEN inverse ---
    // Every other constructor proves; this one is HANDED a proof. The
    // inverse of a proven bijection is proven by the same evidence — one set
    // of N distinct pairs, read the other way — so re-running the check here
    // would not add safety, it would state that the proof is doubted. The
    // door stays invisible from outside: tag and constructor are private,
    // reachable only through the friendship below, so the public invariant —
    // every reachable constructor proves — survives.
    //
    // The BASE is not opened at all: total_map::from is already the
    // check-free totality path (a function cannot lie), and the callable
    // below is total over E1 by its type. What this door skips is only the
    // value-distinctness RE-check. O(N^2) consteval work (N inverse_at
    // scans) — nothing at enumerator counts.
    struct proven_inverse_t {};

    // ALL specializations are friends, deliberately: bijection<E2, E1> must
    // reach this constructor from ITS inverse(), the one-line spelling is
    // fully portable where one-off mutual friendship risks toolchain
    // divergence, and the door it widens is still private. E1 == E2 makes
    // this self-friendship — harmless.
    template <class, class> friend class bijection;

    consteval bijection(proven_inverse_t, const bijection<E2, E1>& forward)
        : base(base::from([&forward](E1 key) { return forward.inverse_at(key); }))
    {
    }
```

In the **public** section, after `inverse_at`:

```cpp
    // THE OPERATION THE PROOF LICENSES: the whole map, read the other way,
    // O(1) in both directions once materialized. consteval, like every
    // construction path — materializing a map IS construction. Enters
    // bijection<E2, E1> through its private tagged door (above): no check
    // re-runs, because none could fail.
    consteval bijection<E2, E1> inverse() const
    {
        using inverse_type = bijection<E2, E1>;
        return inverse_type(typename inverse_type::proven_inverse_t{}, *this);
    }
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `c++ -std=c++20 -Iinclude -Wall -Wextra -Wpedantic -Werror -fsyntax-only tests/selftest_bijection.cpp`
Expected: clean compile. If the mutual friendship fails on this toolchain (it should not, with the all-specializations spelling), the design doc's recorded fallback is to re-run `check()` inside the door — but try the friendship first and only fall back on a real measured failure, recording it in a comment.

- [ ] **Step 5: Run the suite and commit**

Run: `cmake --build build -j && ctest --test-dir build --output-on-failure` — all pass.

```bash
git add include/emap/bijection.h
git commit -m "Open the tagged door: inverse() without re-proof"
```

---

### Task 4: the bijective predicate

**Files:**
- Modify: `include/emap/bijection.h` (namespace-scope concept after the deduction guides + selftests)

**Interfaces:**
- Consumes: `detail::deref_if_ptr` (total_map.h), the Task 1 constructors + deduction guides.
- Produces: `template <auto X> concept emap::bijective` — both passing forms (`bijective<Arr>`, `bijective<&Arr>`); subsumes `buildable`.

- [ ] **Step 1: Write the failing test**

Append to the selftest namespace:

```cpp
// --- bijective: acceptance as a predicate, both passing forms ---
constexpr auto kWireRowsOk = std::array{
    entry{Port::A, Pin::P0}, entry{Port::B, Pin::P1}, entry{Port::C, Pin::P2}};
constexpr auto kWireRowsRepeat = std::array{
    entry{Port::A, Pin::P0}, entry{Port::B, Pin::P0}, entry{Port::C, Pin::P2}};
constexpr auto kWireRowsPartial = std::array{entry{Port::A, Pin::P0}};
static_assert(emap::bijective<kWireRowsOk>);
static_assert(!emap::bijective<kWireRowsRepeat>); // a value repeated...
static_assert(emap::buildable<kWireRowsRepeat>);  // ...on a table that BUILDS fine:
                                                  // bijective is strictly stronger
static_assert(!emap::bijective<kWireRowsPartial>); // and it subsumes buildable —
static_assert(!emap::buildable<kWireRowsPartial>); // a non-table is bijective false too

// by pointer — the general form (enum values are NTTP-valid, so by-value
// also works above; the pointer form is locked anyway, mirroring buildable)
inline constexpr auto kWireRowsPtr = std::array{
    entry{Port::A, Pin::P1}, entry{Port::B, Pin::P2}, entry{Port::C, Pin::P0}};
static_assert(emap::bijective<&kWireRowsPtr>);

// NOTE deliberately absent: no bijective test between count-mismatched
// enums. That case is a class-scope static_assert, which HARD-ERRORS at
// type instantiation rather than answering false (documented in
// DIAGNOSTICS); tests/negative/bijection_count_mismatch.cpp pins it.
```

- [ ] **Step 2: Run it to verify it fails**

Run: `c++ -std=c++20 -Iinclude -Wall -Wextra -Wpedantic -Werror -fsyntax-only tests/selftest_bijection.cpp`
Expected: FAIL — `bijective` is not a member of `emap`.

- [ ] **Step 3: Implement**

After the deduction guides, before `} // namespace emap`:

```cpp
// ---------------------------------------------------------------------------
// Acceptability predicate — a compile-time answer to "would bijection accept
// this row set?", mirroring emap::buildable: the same two passing forms (by
// value, restricted to NTTP-valid tables — enum rows always are; by pointer,
// general), the same substitution-failure mechanism, and the same measured
// portability rule — the CONSTRUCTION is the outermost call in the
// bool_constant operand, and only the ARGUMENT goes through a helper (see
// total_map.h). Unlike keyable, plain CTAD suffices: both enums come off the
// rows, nothing is left to name.
//
// bijective SUBSUMES buildable: the construction it forces runs total_map's
// key checks before the value check, so a table that would not even build is
// bijective == false — one predicate answers for the whole construction.
//
// EDGE (documented in DIAGNOSTICS above): between enums of UNEQUAL COUNTS
// this concept is a hard error, not false — the count check is a class-scope
// static_assert, which fires at instantiation of the type, outside the
// immediate context.
// ---------------------------------------------------------------------------
template <auto X>
concept bijective =
    requires { typename std::bool_constant<(bijection(detail::deref_if_ptr(X)), true)>; };
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `c++ -std=c++20 -Iinclude -Wall -Wextra -Wpedantic -Werror -fsyntax-only tests/selftest_bijection.cpp`
Expected: clean compile.

- [ ] **Step 5: Commit**

```bash
git add include/emap/bijection.h
git commit -m "Add emap::bijective, the acceptance predicate"
```

---

### Task 5: bijection negative tests

**Files:**
- Create: `tests/negative/bijection_repeated_value.cpp`
- Create: `tests/negative/bijection_count_mismatch.cpp`
- Create: `tests/negative/bijection_missing_enumerator.cpp`
- Modify: `cmake/NegativeTests.cmake` (the `cases` list)

**Interfaces:**
- Consumes: the complete `bijection` from Tasks 1–4; the negative-test harness (`run_negative_test.cmake`, driven by the cases list).
- Produces: three registered `negative.*` ctest cases.

- [ ] **Step 1: Write the three cases**

`tests/negative/bijection_repeated_value.cpp`:

```cpp
// Expect: "enum value repeated"
//
// Distinct from total_map's `duplicate enum key`: the KEYS here are fine —
// it is the VALUES that are enumerators, and one is hit twice, so with
// equal counts another is necessarily missed.
#include <emap/bijection.h>

enum class Port { A, B, C, Count };
enum class Pin { P0, P1, P2, Count };

constexpr emap::bijection m{
    emap::entry{Port::A, Pin::P0},
    emap::entry{Port::B, Pin::P0},
    emap::entry{Port::C, Pin::P2},
};

int main() {}
```

`tests/negative/bijection_count_mismatch.cpp`:

```cpp
// Expect: "enum counts differ"
//
// A property of the TYPES, not of any rows — instantiating the type is
// enough (sizeof forces it), no construction is attempted. This is also the
// case emap::bijective cannot answer `false` for: the class-scope
// static_assert fires outside any immediate context, so a probe is a hard
// error — which is exactly what this test pins.
#include <emap/bijection.h>

enum class Port { A, B, C, Count };
enum class Duo { D0, D1, Count };

static_assert(sizeof(emap::bijection<Port, Duo>) > 0);

int main() {}
```

`tests/negative/bijection_missing_enumerator.cpp`:

```cpp
// Expect: "enum value not covered"
//
// Key-side failures are DELEGATED: the sugar builds the total_map first, so
// the diagnostic is total_map's own, verbatim.
#include <emap/bijection.h>

enum class Port { A, B, C, Count };
enum class Pin { P0, P1, P2, Count };

constexpr emap::bijection<Port, Pin> m{
    emap::entry{Port::A, Pin::P0},
    emap::entry{Port::B, Pin::P1},
};

int main() {}
```

- [ ] **Step 2: Verify each fails for the expected reason, by hand**

```bash
for c in bijection_repeated_value bijection_count_mismatch bijection_missing_enumerator; do
  expect=$(head -1 tests/negative/$c.cpp | sed 's/.*"\(.*\)".*/\1/')
  c++ -std=c++20 -Iinclude -fsyntax-only tests/negative/$c.cpp 2>&1 | grep -q "$expect" \
    && echo "ok: $c" || echo "WRONG REASON: $c"
done
```

Expected: three `ok:` lines. (Each file must FAIL to compile *and* the diagnostic must contain the Expect substring.)

- [ ] **Step 3: Register in the harness**

In `cmake/NegativeTests.cmake`, extend the `cases` list (after the `keyed_missing_enumerator` line):

```cmake
        "keyed_missing_enumerator|enum value not covered"
        "bijection_repeated_value|enum value repeated"
        "bijection_count_mismatch|enum counts differ"
        "bijection_missing_enumerator|enum value not covered")
```

(The closing parenthesis moves to the new last line.)

- [ ] **Step 4: Run the negative suite**

Run: `cmake -S . -B build && ctest --test-dir build -R "negative" --output-on-failure`
Expected: all negative tests pass, including the three new `negative.bijection_*`.

- [ ] **Step 5: Commit**

```bash
git add tests/negative/bijection_repeated_value.cpp tests/negative/bijection_count_mismatch.cpp \
        tests/negative/bijection_missing_enumerator.cpp cmake/NegativeTests.cmake
git commit -m "Prove bijection's rejection diagnostics"
```

---

### Task 6: Step 2 closeout — consumer, test matrix, changelog, full sweep

**Files:**
- Modify: `tests/consumer/consumer.cpp`
- Modify: `cmake/TestMatrix.cmake`
- Modify: `CHANGELOG.md` (`[Unreleased]` → `Added`)

**Interfaces:**
- Consumes: everything shipped in Tasks 1–5.
- Produces: Step 2 fully green through every suite; the matrix now sweeps ALL selftest TUs (this also fixes an existing omission: `selftest_keyed` never joined the matrix when keyed_map shipped).

- [ ] **Step 1: Extend the consumer test**

In `tests/consumer/consumer.cpp`: update the top comment's "ALL THREE headers" to "ALL FOUR headers", add the include, a proven bijection, and a runtime `inverse_at` use:

```cpp
#include <emap/bijection.h>
```

after the existing includes (alphabetical position: first). After the `keyed` block:

```cpp
enum class Lamp { Dark, Lit, Count };
enum class Mode { Off, On, Count };

constexpr emap::bijection modeLamp{
    emap::entry{Mode::Off, Lamp::Dark},
    emap::entry{Mode::On, Lamp::Lit},
};
static_assert(modeLamp.inverse()[Lamp::Lit] == Mode::On);
```

and in `main`, extend the `ok` conjunction with a runtime single-slot inverse:

```cpp
    const bool ok = live[Color::Red] == 7 && live[Color::Green] == 2 && live != styles &&
                    found != nullptr && *found == 3 && keyed.find(9) == nullptr &&
                    modeLamp.inverse_at(Lamp::Dark) == Mode::Off;
```

- [ ] **Step 2: Sweep the matrix**

In `cmake/TestMatrix.cmake`:

(a) Replace the TU loop header and its comment:

```cmake
            # One TU per header: the flagship standalone, then each sibling —
            # every sibling TU transitively re-proves the flagship's selftests
            # in a multi-header TU. (selftest_keyed joins here belatedly: it
            # was omitted when keyed_map shipped.)
            foreach(tu IN ITEMS selftest selftest_mutable selftest_keyed selftest_bijection)
```

(b) Replace the two hand-written `*_no_exceptions` blocks inside `if(NOT MSVC)` with a loop over the same TU list (test names `selftest.no_exceptions` and `selftest_mutable.no_exceptions` are preserved by the `${tu}` pattern):

```cmake
    if(NOT MSVC)
        foreach(tu IN ITEMS selftest selftest_mutable selftest_keyed selftest_bijection)
            add_executable(${tu}_no_exceptions ${CMAKE_CURRENT_SOURCE_DIR}/tests/${tu}.cpp)
            target_link_libraries(${tu}_no_exceptions PRIVATE emap::total_map)
            set_target_properties(${tu}_no_exceptions PROPERTIES
                CXX_STANDARD 20
                CXX_STANDARD_REQUIRED ON
                CXX_EXTENSIONS OFF)
            target_compile_options(${tu}_no_exceptions PRIVATE
                -fno-exceptions -Wall -Wextra -Wpedantic -Werror)
            add_test(NAME ${tu}.no_exceptions COMMAND ${tu}_no_exceptions)
        endforeach()
    endif()
```

Keep the existing explanatory comment block above it (the `throw` regression story) — it still applies; only the repetition goes.

- [ ] **Step 3: Changelog entry**

In `CHANGELOG.md`, under `## [Unreleased]` → `### Added`, append:

```markdown
- `emap::bijection<E1, E2>` — a proven bijection between two same-sized
  enums, in its own header `emap/bijection.h`. IS-A `total_map<E1, E2>`;
  construction additionally proves no E2 value repeats (equal counts are a
  `static_assert`), which licenses `inverse()` — the whole map read the
  other way, materialized at compile time with no re-check — and
  `inverse_at(E2)`, the runtime single-slot form, total so it returns by
  value. `bijection<E, E>` is a proven permutation. Acceptance is again a
  predicate: `emap::bijective<Arr | &Arr>`, subsuming `buildable`.
```

- [ ] **Step 4: The full local verification sweep the design doc requires**

```bash
for std in c++20 c++23; do for exc in "" "-fno-exceptions"; do for nd in "" "-DNDEBUG"; do
  echo "== $std $exc $nd =="
  c++ -std=$std $exc $nd -Iinclude -Wall -Wextra -Wpedantic -Werror -fsyntax-only tests/selftest_bijection.cpp || exit 1
done; done; done
cmake -S . -B build -DTOTAL_MAP_TEST_MATRIX=ON && cmake --build build -j && ctest --test-dir build --output-on-failure
cmake -DSOURCE_DIR=$PWD -DWORK_DIR=$PWD/build/consumer-work -P cmake/run_consumer_tests.cmake
```

Expected: 8 clean syntax-check cells; full ctest green (matrix cells included); all three consumer paths `ok`.

- [ ] **Step 5: Commit — Step 2 ships here**

```bash
git add tests/consumer/consumer.cpp cmake/TestMatrix.cmake CHANGELOG.md
git commit -m "Sweep bijection (and the omitted keyed TU) through matrix and consumer"
```

---

### Task 7: snapshot_map.h + join — the proven value-to-value snapshot

**Files:**
- Create: `include/emap/snapshot_map.h`
- Create: `tests/selftest_snapshot.cpp`
- Modify: `CMakeLists.txt` (FILE_SET + selftest executable)

**Interfaces:**
- Consumes: `keyed_map<E1, V1, P1>` (+ `detail::projected_id_t`, `detail::project`, `identity_projection` from keyed_map.h), `bijection<E1, E2>`, `total_map<E2, V2>`, `enum_count_v`.
- Produces: `emap::snapshot_map<K, V, N>` — sealed class: `constexpr const V* find(const K&) const`, `static constexpr std::size_t size()`, copy/move construction, deleted assignment, NO other public surface; `emap::join(const keyed_map<E1,V1,P1>&, const bijection<E1,E2>&, const total_map<E2,V2>&) -> snapshot_map<detail::projected_id_t<P1,V1>, V2, enum_count_v<E1>>` — consteval free function, sole producer.

- [ ] **Step 1: Write the failing test — the driver**

Create `tests/selftest_snapshot.cpp`:

```cpp
// Compiles the snapshot sibling's compile-time self-tests against YOUR
// compiler — and, because snapshot_map.h includes keyed_map.h and
// bijection.h (and they include total_map.h) with the macro already
// defined, EVERY header's self-tests in one TU.
//
//     c++ -std=c++20 -Iinclude -fsyntax-only tests/selftest_snapshot.cpp
//
// Success is a clean compile; there is nothing to run.
#define TOTAL_MAP_SELFTEST
#include <emap/snapshot_map.h>
int main() {}
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `c++ -std=c++20 -Iinclude -Wall -Wextra -Wpedantic -Werror -fsyntax-only tests/selftest_snapshot.cpp`
Expected: FAIL — `emap/snapshot_map.h: No such file or directory`.

- [ ] **Step 3: Write the header**

Create `include/emap/snapshot_map.h`. License header verbatim (as in Task 1), then:

```cpp
// ============================================================================
// snapshot_map.h  —  emap::snapshot_map<K, V, N> + emap::join
// A fully immutable value-owning snapshot with proven-distinct keys of
// arbitrary literal type, producible ONLY by joining proven parts.
// Requires C++20.
// ----------------------------------------------------------------------------
//
// WHAT IT IS
//   The library's first non-enum-indexed table. Parallel arrays — keys and
//   values, slot for slot — where slot i IS the association: like
//   total_map's "no stored keys", nothing can disagree with its own slot.
//   The keys are proven pairwise distinct, but NOT by any check in this
//   header: snapshot_map has no public validating constructor at all. Its
//   SOLE producer is emap::join (below), so every snapshot descends from
//   already-proven parts, and this type merely carries the combined proof.
//
// INTENDED USE
//   The end of a proof chain: an id-indexed view of per-enum config,
//   assembled at compile time from tables that each proved their own part.
//
//       enum class Jack { J0, J1, J2, Count };   // wire-facing enum
//       enum class Amp  { Lo, Mid, Hi, Count };  // internal enum
//       struct Patch { int wire; };              // carries the public id
//       struct Conf  { int gain; };              // per-Amp config
//
//       constexpr emap::keyed_map<Jack, Patch, &Patch::wire> patches{...};
//       constexpr emap::bijection link{...};     // Jack <-> Amp
//       constexpr emap::total_map confs{...};    // Amp -> Conf
//
//       constexpr auto byWire = emap::join(patches, link, confs);
//       static_assert(byWire.find(100)->gain == 5);  // wire id -> Conf
//
// WHAT THE PROOF LICENSES — find(), and only find()
//   find(id) returns a pointer to THE value stored under that key, or
//   nullptr: id -> value is a PARTIAL lookup (nothing proves an arbitrary
//   id is present, only that a present id is unambiguous), and the
//   signature says so — same contract as keyed_map::find. constexpr, not
//   consteval: runtime lookup of a compile-time-proven table is the point.
//   O(N) scan; a sorted index would be an invisible optimization and can
//   arrive later without changing this API. There is deliberately NO
//   operator[] (no totality claim exists over an open key type K), no
//   iteration, no mutable path — every absent operation is an absent claim.
//
// CONSTRUCTION — none, publicly
//   join is the one producer, entering through a private tagged constructor
//   (the same reasoning as bijection's inverse() door: the parts already
//   carry the proof, and a check that cannot fail would only state that the
//   proof is doubted). Copy/move CONSTRUCTION stay — join returns by value,
//   and deriving a copy of a proven snapshot is fine; assignment is deleted,
//   like every immutable type here, so an instance can never detach from
//   the table it was proven as.
//
// THE OUTLIVING CLAIM, SCOPED — read before storing string_view ids
//   V values are COPIED out of the joined tables: on the VALUE side a
//   snapshot is self-contained and may outlive its inputs. The KEYS are
//   projected ids, and an id type like std::string_view ALIASES storage it
//   does not own: ids pointing into string literals or a namespace-scope
//   constexpr table are fine (static storage outlives everything), and
//   constant evaluation keeps a genuine dangle LOUD — a pointer into a
//   vanished temporary is not a constant expression — but the self-
//   containment claim is the VALUES', not the keys'. (The same scoping
//   applies transitively to a V that itself holds pointers, as everywhere
//   in this library.)
//
// DIAGNOSTICS
//   None of its own — deliberately. join CANNOT fail (see its block), and
//   every way to reach a snapshot runs the producing types' own checks with
//   their own diagnostics. A collision surfaces UPSTREAM, at keyed_map
//   construction, where the colliding slots are named;
//   tests/negative/snapshot_upstream_collision.cpp pins that.
//
// REQUIREMENTS & GUARANTEES
//   * K and V must be literal types, copy-constructible; K equality-
//     comparable. All guaranteed upstream by join's inputs, and asserted
//     here against THIS type's name so a future construction path cannot
//     regress the diagnostic.
//   * Keys pairwise distinct (from the keyed_map input's proof) — which is
//     what makes find()'s answer well-defined.
//   * The snapshot is exactly the third table RE-KEYED by the first one's
//     ids: every row represented exactly once (from the bijection input's
//     proof; see join below).
// ============================================================================

#ifndef SNAPSHOT_MAP_INCLUDED
#define SNAPSHOT_MAP_INCLUDED

// Quote form, deliberately (copy-pastable emap/ directory; see total_map.h).
// Both refinement headers, because join's signature names both refinements;
// they each pull in total_map.h. Version macros live in total_map.h.
#include "bijection.h"
#include "keyed_map.h"

#include <array>
#include <concepts>
#include <cstddef>
#include <type_traits>
#include <utility>

namespace emap
{

template <class K, class V, std::size_t N> class snapshot_map;

// Declared before the class so the friend declaration inside it refers to
// THIS template rather than silently declaring a new, invisible one.
// Definition and full documentation below the class.
template <class E1, class V1, auto P1, class E2, class V2>
consteval snapshot_map<detail::projected_id_t<P1, V1>, V2, enum_count_v<E1>>
join(const keyed_map<E1, V1, P1>& a, const bijection<E1, E2>& b,
     const total_map<E2, V2>& m2);

template <class K, class V, std::size_t N> class snapshot_map
{
    // Guaranteed upstream by join's inputs (keyed_map's projects_comparably
    // bar, total_map's V requirements), but asserted against THIS type's
    // name so a future direct construction path cannot regress the
    // diagnostic.
    static_assert(std::is_copy_constructible_v<K>,
        "emap::snapshot_map: K must be copy-constructible to be placed into storage.");
    static_assert(std::is_copy_constructible_v<V>,
        "emap::snapshot_map: V must be copy-constructible to be placed into storage.");
    static_assert(requires(const K& a, const K& b) {
        { a == b } -> std::convertible_to<bool>;
    }, "emap::snapshot_map: K must be equality-comparable — find(id) compares ids.");

    // Parallel arrays: slot i IS the association. Keys ARE stored here —
    // unlike total_map's enum keys they are not recoverable from position —
    // but they are as frozen as the values, so they still cannot disagree
    // with their slots.
    std::array<K, N> keys_;
    std::array<V, N> values_;

    // --- the tagged door: join is the sole producer ---
    // Same reasoning as bijection's inverse() door, recorded there in full:
    // the inputs already carry the proof, so a re-check here could not fail
    // and would only state that the proof is doubted. Private tag + the
    // friendship below keep the public invariant: no reachable constructor
    // skips a proof, because no reachable constructor exists.
    struct proven_join_t {};

    template <class E1, class V1, auto P1, class E2, class V2>
    friend consteval snapshot_map<detail::projected_id_t<P1, V1>, V2, enum_count_v<E1>>
    join(const keyed_map<E1, V1, P1>&, const bijection<E1, E2>&,
         const total_map<E2, V2>&);

    // Pack-expanded per slot so neither K nor V needs a default constructor
    // (each element is copy-initialized from the callable's result) —
    // total_map's from_fn_t pattern, for two arrays.
    template <class KeyFn, class ValFn, std::size_t... Is>
    consteval snapshot_map(proven_join_t, KeyFn& keyFn, ValFn& valFn,
                           std::index_sequence<Is...>)
        : keys_{keyFn(Is)...}, values_{valFn(Is)...}
    {
    }

  public:
    // LOOKUP BY ID — the one operation. A pointer, because the lookup is
    // PARTIAL; const, because everything here is; constexpr, because runtime
    // lookup of a proven table is the point. See the top block.
    constexpr const V* find(const K& id) const
    {
        for (std::size_t i = 0; i < N; ++i) {
            if (keys_[i] == id) {
                return &values_[i];
            }
        }
        return nullptr;
    }

    static constexpr std::size_t size() { return N; }

    // Immutable: copy/move CONSTRUCTION stay (join returns by value, and a
    // copy of a proven snapshot is proven), assignment is deleted — see
    // total_map's identical block for the -Wdeprecated-copy note behind
    // declaring the constructors as defaulted.
    constexpr snapshot_map(const snapshot_map&) = default;
    constexpr snapshot_map(snapshot_map&&) = default;
    snapshot_map& operator=(const snapshot_map&) = delete;
    snapshot_map& operator=(snapshot_map&&) = delete;
};

// ---------------------------------------------------------------------------
// join — the snapshot's sole producer. For each E1 key e, the snapshot pairs
// P1(a[e]) — the id — with m2[b[e]] — the value. consteval; NO VALIDATION IN
// THE BODY, and none omitted: the signature is the entire proof.
//
// Which argument proves what — precisely:
//   * KEY DISTINCTNESS comes from `a` ALONE: the snapshot's keys are a's
//     projected ids, proven collision-free at a's construction.
//   * COVERAGE comes from the totality of all three arguments.
//   * `b` being a BIJECTION is demanded for a guarantee about the RESULT,
//     not for its validity: it makes the snapshot exactly m2 RE-KEYED by
//     a's ids — every row of m2 represented exactly once, nothing dropped,
//     nothing duplicated. (A merely-total bridge would still produce a
//     valid snapshot, but could hit one E2 row twice and silently miss
//     another.) Bijectivity is NOT what makes the keys distinct — a alone
//     does that.
//
// V2 values are COPIED (self-contained on the value side; the keys' scoping
// is the aliasing block at the top). Accepting these parameter types also
// accepts anything publicly derived from them — fine: the proof rides the
// base subobject. emap::mutable_total_map matches NONE of the three
// positions, by signature — the selftests pin that refusal.
//
// join cannot fail, so there is no negative test OF join — only the
// upstream one showing where a collision actually surfaces.
// ---------------------------------------------------------------------------
template <class E1, class V1, auto P1, class E2, class V2>
consteval snapshot_map<detail::projected_id_t<P1, V1>, V2, enum_count_v<E1>>
join(const keyed_map<E1, V1, P1>& a, const bijection<E1, E2>& b,
     const total_map<E2, V2>& m2)
{
    using result_type = snapshot_map<detail::projected_id_t<P1, V1>, V2, enum_count_v<E1>>;
    auto keyFn = [&a](std::size_t i) {
        auto proj = P1; // an lvalue for detail::project to bind
        return detail::project(proj, a[a.key_at(i)]);
    };
    auto valFn = [&b, &m2](std::size_t i) -> V2 { return m2[b[b.key_at(i)]]; };
    return result_type(typename result_type::proven_join_t{}, keyFn, valFn,
                       std::make_index_sequence<enum_count_v<E1>>{});
}

} // namespace emap

// ============================================================================
// SELF-TESTS
// Same contract as total_map.h's: opt-in via TOTAL_MAP_SELFTEST, compile-time
// only, a clean compile is the pass. This TU transitively compiles EVERY
// header's selftests, which is why all names here are fresh. See
// tests/selftest_snapshot.cpp for the three-line driver.
// ============================================================================
#ifdef TOTAL_MAP_SELFTEST
#include <string_view>
namespace emap::selftest
{

// --- the worked example: wire enum <-> internal enum -> config ---
enum class Jack { J0, J1, J2, Count };
enum class Amp { Lo, Mid, Hi, Count };

struct Patch {
    int wire;
};
struct Conf {
    int gain;
};

constexpr emap::keyed_map<Jack, Patch, &Patch::wire> kPatches{
    entry{Jack::J0, Patch{100}}, entry{Jack::J1, Patch{200}}, entry{Jack::J2, Patch{300}}};
constexpr emap::bijection kLink{
    entry{Jack::J0, Amp::Mid}, entry{Jack::J1, Amp::Lo}, entry{Jack::J2, Amp::Hi}};
constexpr emap::total_map kConfs{
    entry{Amp::Lo, Conf{1}}, entry{Amp::Mid, Conf{5}}, entry{Amp::Hi, Conf{9}}};

constexpr auto kSnap = emap::join(kPatches, kLink, kConfs);

// join's result type is exact — id type off the projection, size off E1
static_assert(std::is_same_v<decltype(kSnap), const emap::snapshot_map<int, Conf, 3>>);
static_assert(kSnap.size() == 3);

// id -> V2 hits follow the composition Jack -> Amp -> Conf; misses are honest
static_assert(kSnap.find(100)->gain == 5); // J0 -> Mid
static_assert(kSnap.find(200)->gain == 1); // J1 -> Lo
static_assert(kSnap.find(300)->gain == 9); // J2 -> Hi
static_assert(kSnap.find(42) == nullptr);

} // namespace emap::selftest
#endif // TOTAL_MAP_SELFTEST

#endif // SNAPSHOT_MAP_INCLUDED
```

- [ ] **Step 4: Run the driver to verify it passes**

Run: `c++ -std=c++20 -Iinclude -Wall -Wextra -Wpedantic -Werror -fsyntax-only tests/selftest_snapshot.cpp`
Expected: clean compile. If the friend declaration fails to match the prior `join` declaration (unlikely but toolchain-sensitive), the two declarations must be textually identical in template head, consteval, return type, and parameter types — diff them character by character before trying anything structural.

- [ ] **Step 5: Wire into CMake**

`CMakeLists.txt` — FILE_SET gains (after the bijection.h line):

```cmake
              ${CMAKE_CURRENT_SOURCE_DIR}/include/emap/bijection.h
              ${CMAKE_CURRENT_SOURCE_DIR}/include/emap/snapshot_map.h)
```

and after the `total_map_selftest_bijection` block:

```cmake
    add_executable(total_map_selftest_snapshot tests/selftest_snapshot.cpp)
    target_link_libraries(total_map_selftest_snapshot PRIVATE emap::total_map)
    add_test(NAME total_map_selftest_snapshot COMMAND total_map_selftest_snapshot)
```

- [ ] **Step 6: Run the suite**

Run: `cmake -S . -B build && cmake --build build -j && ctest --test-dir build --output-on-failure`
Expected: green, including `total_map_selftest_snapshot`.

- [ ] **Step 7: Commit**

```bash
git add include/emap/snapshot_map.h tests/selftest_snapshot.cpp CMakeLists.txt
git commit -m "Add emap::snapshot_map and join, the proven value-to-value snapshot"
```

---

### Task 8: seal the surface — refusals, string_view ids

**Files:**
- Modify: `include/emap/snapshot_map.h` (selftest section only)

**Interfaces:**
- Consumes: Task 7's `snapshot_map`/`join`; `emap::mutable_total_map` (selftest-only include).
- Produces: locked selftests other code may rely on: no public validating constructors, no assignment, mutable refusal by signature, `std::string_view` id support.

- [ ] **Step 1: Write the tests (they should pass immediately — these LOCK behavior Task 7 built; a failure here is a Task 7 bug)**

In the selftest section of `include/emap/snapshot_map.h`, extend the includes:

```cpp
#ifdef TOTAL_MAP_SELFTEST
#include <string_view>
// The refusal checks below need the mutable sibling IN THE TEST TU; the
// header proper never touches it — refinements build on the immutable
// total_map only.
#include "mutable_total_map.h"
```

and append inside the namespace, before the closing brace:

```cpp
// --- string_view ids: the supported aliasing case (static storage) ---
struct Badge {
    const char* name;
};
constexpr emap::keyed_map<Jack, Badge,
    [](const Badge& b) { return std::string_view{b.name}; }>
    kBadges{entry{Jack::J0, Badge{"alpha"}}, entry{Jack::J1, Badge{"beta"}},
            entry{Jack::J2, Badge{"gamma"}}};
constexpr auto kByName = emap::join(kBadges, kLink, kConfs);
static_assert(std::is_same_v<decltype(kByName),
                             const emap::snapshot_map<std::string_view, Conf, 3>>);
static_assert(kByName.find(std::string_view{"beta"})->gain == 1);
static_assert(kByName.find(std::string_view{"delta"}) == nullptr);

// --- the surface is sealed: join is the sole producer ---
using Snap = emap::snapshot_map<int, Conf, 3>;
static_assert(std::is_copy_constructible_v<Snap>); // join returns by value...
static_assert(std::is_move_constructible_v<Snap>); // ...and a copy stays proven
static_assert(!std::is_default_constructible_v<Snap>);
// no public validating construction: raw parallel arrays are refused
static_assert(!std::is_constructible_v<Snap, std::array<int, 3>, std::array<Conf, 3>>);
static_assert(!std::is_copy_assignable_v<Snap>);
static_assert(!std::is_move_assignable_v<Snap>);

// --- mutable tables are refused BY SIGNATURE, at every position ---
static_assert(!requires(const emap::mutable_total_map<Amp, Conf>& live) {
    emap::join(kPatches, kLink, live);
});
static_assert(!requires(const emap::mutable_total_map<Jack, Patch>& live) {
    emap::join(live, kLink, kConfs);
});
```

- [ ] **Step 2: Run to verify a clean compile**

Run: `c++ -std=c++20 -Iinclude -Wall -Wextra -Wpedantic -Werror -fsyntax-only tests/selftest_snapshot.cpp`
Expected: clean. Any failure here means Task 7's surface leaks — fix the class, not the test.

- [ ] **Step 3: Commit**

```bash
git add include/emap/snapshot_map.h
git commit -m "Seal snapshot_map's surface and prove the refusals"
```

---

### Task 9: the upstream-collision negative test

**Files:**
- Create: `tests/negative/snapshot_upstream_collision.cpp`
- Modify: `cmake/NegativeTests.cmake`

**Interfaces:**
- Consumes: the negative-test harness; keyed_map's `values collide under projection` diagnostic.
- Produces: registered `negative.snapshot_upstream_collision` ctest case.

- [ ] **Step 1: Write the case**

`tests/negative/snapshot_upstream_collision.cpp`:

```cpp
// Expect: "values collide under projection"
//
// There is no negative test OF join — it cannot fail; its signature is its
// proof. This case shows WHERE a collision actually surfaces: upstream, at
// keyed_map construction, with keyed_map's own slot-naming diagnostic,
// before join is ever reached.
#include <emap/snapshot_map.h>

enum class Jack { J0, J1, Count };
enum class Amp { Lo, Hi, Count };

struct Patch {
    int wire;
};
struct Conf {
    int gain;
};

constexpr emap::keyed_map<Jack, Patch, &Patch::wire> kPatches{
    emap::entry{Jack::J0, Patch{7}},
    emap::entry{Jack::J1, Patch{7}},
};

// Never reached: the error above is the point.
constexpr emap::bijection kLink{
    emap::entry{Jack::J0, Amp::Lo},
    emap::entry{Jack::J1, Amp::Hi},
};
constexpr emap::total_map kConfs{
    emap::entry{Amp::Lo, Conf{1}},
    emap::entry{Amp::Hi, Conf{9}},
};
constexpr auto kSnap = emap::join(kPatches, kLink, kConfs);

int main() {}
```

- [ ] **Step 2: Verify it fails for the expected reason**

Run: `c++ -std=c++20 -Iinclude -fsyntax-only tests/negative/snapshot_upstream_collision.cpp 2>&1 | grep -c "values collide under projection"`
Expected: a count ≥ 1.

- [ ] **Step 3: Register**

In `cmake/NegativeTests.cmake`, extend the cases list (the new last line):

```cmake
        "bijection_missing_enumerator|enum value not covered"
        "snapshot_upstream_collision|values collide under projection")
```

- [ ] **Step 4: Run the negative suite**

Run: `cmake -S . -B build && ctest --test-dir build -R "negative" --output-on-failure`
Expected: green, including `negative.snapshot_upstream_collision`.

- [ ] **Step 5: Commit**

```bash
git add tests/negative/snapshot_upstream_collision.cpp cmake/NegativeTests.cmake
git commit -m "Show join's collision is caught upstream"
```

---

### Task 10: Step 3 closeout — consumer, matrix, changelog, full sweep

**Files:**
- Modify: `tests/consumer/consumer.cpp`
- Modify: `cmake/TestMatrix.cmake` (add `selftest_snapshot` to BOTH TU lists from Task 6)
- Modify: `CHANGELOG.md`

**Interfaces:**
- Consumes: everything from Tasks 7–9.
- Produces: Step 3 fully green through every suite.

- [ ] **Step 1: Extend the consumer test**

In `tests/consumer/consumer.cpp`: comment now says "ALL FIVE headers"; add `#include <emap/snapshot_map.h>` (alphabetical: after mutable_total_map.h); after the `modeLamp` block add:

```cpp
constexpr emap::keyed_map<Mode, int> modeCodes{
    emap::entry{Mode::Off, 10},
    emap::entry{Mode::On, 20},
};
constexpr emap::total_map lampGain{
    emap::entry{Lamp::Dark, 0},
    emap::entry{Lamp::Lit, 9},
};
constexpr auto snap = emap::join(modeCodes, modeLamp, lampGain);
// asserted through the dereference (see the -Waddress note in the design doc)
static_assert(*snap.find(10) == 0); // Off -> Dark -> 0
static_assert(*snap.find(20) == 9); // On -> Lit -> 9
```

and in `main`, extend `ok` with a runtime snapshot lookup:

```cpp
    const int* gain = snap.find(20);
    const bool ok = live[Color::Red] == 7 && live[Color::Green] == 2 && live != styles &&
                    found != nullptr && *found == 3 && keyed.find(9) == nullptr &&
                    modeLamp.inverse_at(Lamp::Dark) == Mode::Off &&
                    gain != nullptr && *gain == 9 && snap.find(5) == nullptr;
```

- [ ] **Step 2: Matrix**

In `cmake/TestMatrix.cmake`, both `foreach(tu IN ITEMS ...)` lists (the standards×NDEBUG loop and the no-exceptions loop) gain `selftest_snapshot`:

```cmake
foreach(tu IN ITEMS selftest selftest_mutable selftest_keyed selftest_bijection selftest_snapshot)
```

- [ ] **Step 3: Changelog entry**

In `CHANGELOG.md`, under `[Unreleased]` → `### Added`, append after the bijection entry:

```markdown
- `emap::snapshot_map<K, V, N>` + `emap::join` — the first non-enum-indexed
  table, in its own header `emap/snapshot_map.h`: a fully immutable
  value-owning snapshot with proven-distinct keys of arbitrary literal type,
  offering `find(id)` (partial, pointer-honest) and `size()`. It has NO
  public validating constructor: its sole producer is
  `emap::join(keyed_map, bijection, total_map)`, a consteval free function
  whose signature is its entire proof — key distinctness from the keyed_map,
  coverage from totality, and, from the bijection, the guarantee that the
  snapshot is exactly the third table re-keyed by the first one's ids.
  Values are copied; `std::string_view` ids alias their (static-storage)
  sources, as documented in the header.
```

- [ ] **Step 4: The full sweep**

```bash
for std in c++20 c++23; do for exc in "" "-fno-exceptions"; do for nd in "" "-DNDEBUG"; do
  echo "== $std $exc $nd =="
  c++ -std=$std $exc $nd -Iinclude -Wall -Wextra -Wpedantic -Werror -fsyntax-only tests/selftest_snapshot.cpp || exit 1
done; done; done
cmake -S . -B build -DTOTAL_MAP_TEST_MATRIX=ON && cmake --build build -j && ctest --test-dir build --output-on-failure
cmake -DSOURCE_DIR=$PWD -DWORK_DIR=$PWD/build/consumer-work -P cmake/run_consumer_tests.cmake
```

Expected: 8 clean cells, full ctest green, three consumer paths `ok`.

- [ ] **Step 5: Commit — Step 3 ships here**

```bash
git add tests/consumer/consumer.cpp cmake/TestMatrix.cmake CHANGELOG.md
git commit -m "Sweep snapshot_map through matrix and consumer"
```

---

### Task 11: README + the owed keyed_map docs

**Files:**
- Modify: `README.md`
- Modify: `CHANGELOG.md`

Context: keyed_map shipped with NO README section and NO changelog entry — both are owed from its own step (verified: `grep keyed CHANGELOG.md` is empty; README's sole match is in the alternatives table). This task pays that debt and documents the two new headers, batched per the design doc's "author's call".

**Interfaces:**
- Consumes: the shipped surface of keyed_map, bijection, snapshot_map (use their header doc comments as the source of truth for claims — do not re-derive).
- Produces: three README sections + one keyed_map changelog entry.

- [ ] **Step 1: keyed_map changelog entry**

In `CHANGELOG.md` under `[Unreleased]` → `### Added`, insert BEFORE the bijection entry (chronological ship order):

```markdown
- `emap::keyed_map<E, V, Proj>` — a `total_map` whose values are proven
  distinct under a projection, in its own header `emap/keyed_map.h`: the
  type-level carrier of an `emap::all_unique` proof. The projected result is
  the value's ID, and proven-distinct ids license `find(id)` — the library's
  one partial lookup, pointer-honest. Construction promotes an already-
  proven `total_map` (implicit, consteval) or authors rows/arrays through
  it; collisions are reported with both slots as template arguments
  (`duplicate value` under the identity default, `values collide under
  projection` under a real one). Acceptance is a predicate:
  `emap::keyable<Arr | &Arr, Proj>`, subsuming `buildable`.
```

- [ ] **Step 2: README sections**

In `README.md`, after the `### Proving uniqueness beyond keys` section (which documents `all_unique`) and before `### A runtime-tunable sibling: mutable_total_map`, add three sections in the surrounding register (study the neighboring sections first; keep code examples compiling — test them by pasting into a scratch TU with `-Iinclude`):

```markdown
### Lookup by id: keyed_map

`emap::all_unique` states a proof; `emap::keyed_map<E, V, Proj>` (header
`emap/keyed_map.h`) carries it in the type — a `total_map` that has proven,
at construction, that `Proj` maps no two of its values to equal results. The
projected result is the value's **id** (a wire code, a name), and the proof
licenses the one lookup `total_map` cannot have: `find(id)`, well-defined
because at most one value can match.

```cpp
#include <emap/keyed_map.h>

enum class Color { Red, Green, Blue, Count };
struct Style { int wireCode; int thickness; };

constexpr emap::keyed_map<Color, Style, &Style::wireCode> styles{
    emap::entry{Color::Red,   Style{7,  1}},
    emap::entry{Color::Green, Style{9,  2}},
    emap::entry{Color::Blue,  Style{12, 3}},  // a duplicate wireCode -> compile error
};

static_assert(styles.find(9)->thickness == 2);  // hit
static_assert(styles.find(8) == nullptr);       // miss: find is the library's
                                                // one partial lookup, and says so
```

`find` returns a const pointer, `nullptr` on a miss — nothing proves an
arbitrary id is present, only that a present one is unambiguous. `Proj` is
part of the type (a data-member pointer or a captureless lambda; omitted, the
values are their own ids). Construction **promotes** a proven `total_map`
(implicitly, at compile time), so an API taking `keyed_map` can be handed a
`total_map` and the missing proof is demanded at the call site. A collision
names both offending slots in the diagnostic. Acceptance is again a
predicate: `emap::keyable<Arr, Proj>` / `emap::keyable<&Arr, Proj>`,
subsuming `buildable`. For string ids, project to `std::string_view` so
equality means content.

### A proven two-enum correspondence: bijection

`emap::bijection<E1, E2>` (header `emap/bijection.h`) is a `total_map<E1,
E2>` that has additionally proven no E2 value repeats — and demands
`enum_count_v<E1> == enum_count_v<E2>` by `static_assert`. Total + injective
at equal counts is bijective, which licenses inversion with no further
proof:

```cpp
#include <emap/bijection.h>

enum class Port { A, B, C, Count };
enum class Pin  { P0, P1, P2, Count };

constexpr emap::bijection wires{
    emap::entry{Port::A, Pin::P2},
    emap::entry{Port::B, Pin::P0},
    emap::entry{Port::C, Pin::P1},  // repeat a Pin -> compile error
};

static_assert(wires[Port::A] == Pin::P2);            // inherited total lookup
static_assert(wires.inverse()[Pin::P2] == Port::A);  // the licensed operation
```

`inverse()` materializes the reversed map at compile time — it re-checks
nothing, because the inverse of a proven bijection is proven by the same
evidence. `inverse_at(E2)` is the runtime single-slot form, returning `E1`
**by value**: bijectivity makes the inverse total, so there is no pointer to
be honest with. `bijection<E, E>` is a proven permutation. Acceptance:
`emap::bijective<Arr | &Arr>`, subsuming `buildable` (note: between enums of
*unequal counts* the predicate is a hard error, not `false` — the count
check is a property of the types).

### Joining proofs: snapshot_map

`emap::join` (header `emap/snapshot_map.h`) composes three proven tables
into the library's first non-enum-indexed one — with **no validation of its
own**, because its signature is its proof:

```cpp
#include <emap/snapshot_map.h>

enum class Jack { J0, J1, J2, Count };   // wire-facing enum
enum class Amp  { Lo, Mid, Hi, Count };  // internal enum
struct Patch { int wire; };
struct Conf  { int gain; };

constexpr emap::keyed_map<Jack, Patch, &Patch::wire> patches{
    emap::entry{Jack::J0, Patch{100}},
    emap::entry{Jack::J1, Patch{200}},
    emap::entry{Jack::J2, Patch{300}}};
constexpr emap::bijection link{                       // Jack <-> Amp
    emap::entry{Jack::J0, Amp::Mid},
    emap::entry{Jack::J1, Amp::Lo},
    emap::entry{Jack::J2, Amp::Hi}};
constexpr emap::total_map confs{                      // Amp -> Conf
    emap::entry{Amp::Lo, Conf{1}},
    emap::entry{Amp::Mid, Conf{5}},
    emap::entry{Amp::Hi, Conf{9}}};

constexpr auto byWire = emap::join(patches, link, confs);
static_assert(byWire.find(100)->gain == 5);  // wire id -> config
static_assert(byWire.find(42) == nullptr);
```

Key distinctness comes from the `keyed_map`, coverage from totality, and
the `bijection` guarantees the snapshot is exactly the third table
**re-keyed** by the first one's ids — every row represented exactly once.
The result, `emap::snapshot_map<K, V, N>`, is sealed: `find` and `size()`
are the whole surface, and `join` is the only producer, so every snapshot
descends from proven parts. Values are copied; ids like `std::string_view`
alias their (static-storage) sources — the header scopes that claim
precisely.
```

- [ ] **Step 3: Verify the README examples compile**

Concatenate each README code block into a scratch TU (e.g. `/tmp/readme_check.cpp`, each block wrapped in a distinct namespace, one set of includes at the top, `int main() {}` at the bottom — minus the deliberate-error rows, which get commented out with their `-> compile error` markers kept in the README) and run:
`c++ -std=c++20 -Iinclude -Wall -Wextra -Werror -fsyntax-only /tmp/readme_check.cpp`
Expected: clean.

- [ ] **Step 4: Commit**

```bash
git add README.md CHANGELOG.md
git commit -m "Document the refinement family: keyed_map, bijection, snapshot_map"
```

---

## Plan Self-Review Notes (already applied)

- **Spec coverage:** every §5 bullet of the design doc maps to a task — Step 2 core/`inverse_at`/`inverse`/predicate/tests/wiring → Tasks 1–6; Step 3 type/`join`/selftests/negative/wiring → Tasks 7–10; §6 conventions → Global Constraints + Task 11. The design doc's resolved decisions (walker duplication, all-specializations friendship, `from()`-based door, count-mismatch hard-error edge, id-aliasing scoping, copy-construction kept) are each embodied in the code above, not re-decided.
- **Deliberately absent, per the design doc — do not add:** `compose`, `identity<E>()`, precomposition helpers, snapshot iteration/`operator[]`/sorted find, direct snapshot construction, any `from()` on refinements, any mutable path.
- **Type consistency:** `inverse_at(E2) -> E1`; `join(keyed_map<E1,V1,P1>, bijection<E1,E2>, total_map<E2,V2>) -> snapshot_map<detail::projected_id_t<P1,V1>, V2, enum_count_v<E1>>`; selftest names are unique across all five headers' selftest sections (checked against the full inventory).
- **Known risks, with fallbacks recorded:** (1) friend-template matching for `join` — keep the two declarations textually identical; (2) mutual `bijection` friendship — all-specializations spelling should hold everywhere, design doc records the re-check fallback; (3) MSVC rendering of `enum_value_repeated<I, J>` — CI-observed only, doc claims adjusted afterward per design doc §4.
