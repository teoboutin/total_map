# total_map

[![CI](https://github.com/teoboutin/total_map/actions/workflows/ci.yml/badge.svg)](https://github.com/teoboutin/total_map/actions/workflows/ci.yml)
[![Try it on Compiler Explorer](https://img.shields.io/badge/try_it-Compiler_Explorer-67c52a)](https://godbolt.org/z/9K375b7d1)

A single-header, C++20, compile-time-checked **total map from an enum to
values**. An optional second header adds `emap::mutable_total_map`, the
[runtime-tunable sibling](#a-runtime-tunable-sibling-mutable_total_map).

`emap::total_map<E, V>` stores exactly one `V` per enumerator of `E` in a flat
`std::array<V, N>` indexed by the enum's underlying value. Lookup is a plain
array index — no hashing, no branching, no allocation. The table is authored as
one array literal, and **it refuses to compile unless every enumerator is
covered exactly once**.

"Total" is meant in the mathematical sense: the map is a total function from `E`,
defined on every enumerator. Proved at compile time.

It is a compile-time lookup table, not a runtime container: there is no
`insert`/`erase` and no runtime construction path. It is also **immutable**:
values cannot change and instances cannot be reassigned, so anything proven
about a table stays proven for every instance's whole lifetime. For values
tuned at run time, thaw a proven table into `emap::mutable_total_map`.

```cpp
enum class Color { Red, Green, Blue, Count };
struct Style { int thickness; const char* name; };

constexpr emap::total_map styles{
    emap::entry{Color::Red,   Style{1, "red"}},
    emap::entry{Color::Green, Style{2, "green"}},
    emap::entry{Color::Blue,  Style{3, "blue"}},   // omit one -> compile error
};

static_assert(styles[Color::Green].thickness == 2);
```

## Why

Hand-authored `constexpr` tables (per-enum config: labels, thresholds, colors,
dispatch parameters) are easy to get subtly wrong — a forgotten case, a
duplicated key, a row that drifts out of order. `total_map` moves all three
failures to compile time and keeps lookup as fast as a raw array.

- **Total** — a missing enumerator is a compile error.
- **Unique** — a duplicated key is a compile error.
- **Right-sized** — an input length `!= N` is a compile error.
  ([one caveat on what "total" proves](#what-it-does-not-prove).)
- **Order-independent** — rows may be authored in any order; values are stored
  in enum order regardless. Benefit: you can reorder the enumerators without
  having to edit the map definition itself.
- **No stored keys** — the key validates and places each row, then is dropped.
  Storage is a bare `std::array<V, N>`, so a value can never disagree with
  its slot.

## Requirements

- **C++20** (`consteval`, concepts, CTAD, aggregate CTAD for `entry`). Standard
  library includes only: `<array>`, `<cassert>`, `<cstddef>`, `<concepts>`,
  `<iterator>`, `<type_traits>`, `<utility>`. Notably **not** `<ranges>` —
  `entries()` composes with it if you include it, but you never pay for it if
  you don't.
- **No exception support needed.** The header builds and enforces every
  guarantee under `-fno-exceptions` — common in embedded, safety-critical and
  game builds, and available to Emscripten users who pass it. A rejected table
  is reported by calling a declared-but-undefined `emap::error::` function —
  not a constant expression, so it aborts the compile exactly as a `throw`
  would, without requiring exceptions to be enabled. CI gates this on GCC,
  Clang and em++/wasm.
- [Supported compilers/platforms](#supported-toolchains)
- The enum must have **contiguous underlying values `0..N-1`** — storage is
  indexed by `static_cast<size_t>(key)`.
- The enumerator count `N` is read from `emap::enum_count<E>::value`. By default
  this comes from a trailing `Count` sentinel (see below); a project whose
  sentinel is spelled otherwise teaches it once with an `emap::enum_count_policy`,
  and an enum with no sentinel at all needs an `emap::enum_count<E>`
  specialization. A missing count is reported with a clear `static_assert`. Only
  `Count` is recognised **by default** — not `COUNT`, `kCount`, or any other
  spelling; see
  [what it does not prove](#what-it-does-not-prove) for why that is deliberate.
- `V` must be a **literal type and copy-constructible**. It need **not** be
  default-constructible, and need **not** carry its own key.


## Installing

Header-only — the whole library is one header, and it has no dependencies.

**cmake** install requires cmake >= 3.23 (for `FILE_SET HEADERS`). 
Or just drop `include/emap/total_map.h` into your project, no requirements above c++20.

**CMake FetchContent:**

```cmake
include(FetchContent)
FetchContent_Declare(total_map
    GIT_REPOSITORY https://github.com/teoboutin/total_map.git
    GIT_TAG        v0.2.0)
FetchContent_MakeAvailable(total_map)

target_link_libraries(app PRIVATE emap::total_map)
```

**Installed, via find_package:**

```cmake
find_package(total_map 0.2.0 REQUIRED)
target_link_libraries(app PRIVATE emap::total_map)
```

Linking `emap::total_map` puts the header on your include path and requires
C++20 of the linking target — a target left on an older standard is raised to
C++20 rather than failing to compile.

**Or just copy `include/emap/total_map.h` into your project** — no build system
required.

```cpp
#include <emap/total_map.h>
```

## Usage

### Struct payloads

Rows need no factory — CTAD deduces `E` and `V` from them:

```cpp
enum class Color { Red, Green, Blue, Count };
struct Style { int thickness; const char* name; };

constexpr emap::total_map styles{
    emap::entry{Color::Blue,  Style{3, "blue"}},   // any order
    emap::entry{Color::Red,   Style{1, "red"}},
    emap::entry{Color::Green, Style{2, "green"}},
};

static_assert(styles[Color::Red].thickness == 1);
```

Rows may also be passed as a single `std::array` — that form is what
`emap::buildable<>` takes, since a non-type template parameter needs a named
array:

```cpp
constexpr emap::total_map arrayed{std::array{
    emap::entry{Color::Red, Style{1, "red"}}, /* ... */
}};
```

### Scalar payloads

A bare value is stored and read directly — no wrapper, no `.value` indirection:

```cpp
constexpr emap::total_map cost{
    emap::entry{Color::Red, 1250.0}, emap::entry{Color::Green, 500.0},
    emap::entry{Color::Blue, 625.0},
};

static_assert(cost[Color::Red] == 1250.0);
```

### Deriving tables

`total_map<E, V>::from(fn)` computes the table instead of authoring rows: `fn`
is invoked once per enumerator, in enum order. There are no rows to get wrong —
`fn` is total over `E` by its type, so exhaustiveness, uniqueness and order
hold **by construction** rather than by check:

```cpp
constexpr auto brightness = emap::total_map<Color, int>::from(
    [](Color c) { return static_cast<int>(c) * 40; });

static_assert(brightness[Color::Blue] == 80);
```

The callable must return `V` itself (a cv/ref-qualified `V` is fine) —
`from()` performs no conversions, mirroring row authoring, where `entry<E, V>`
fixes each row's value type. Write `return 90.0;`, not `return 90;`, for a
double map. Like every other construction path it is `consteval`: there is
still no runtime population.

`transform(fn)` is the sibling, deriving a table **from an existing table** by
mapping each value — how per-enum config gets varied in practice (a theme from
a base theme, a scaled cost table). The value type may change; the result is
`total_map<E, U>` with `U` deduced from `fn`:

```cpp
constexpr auto dark = styles.transform([](Style s) { s.thickness += 1; return s; });
constexpr auto names = styles.transform([](const Style& s) { return s.name; });

static_assert(names[Color::Red][0] == 'r'); // total_map<Color, const char*>
```

### Iterating

`entries()` iterates keys alongside values, in enum order. Values come back
by const reference:

```cpp
for (auto [color, style] : styles.entries())
    use(color, style);
```

Each element is an `emap::entry_ref<E, V>` — named `.key` and `.value` members,
the same vocabulary as the `entry` rows you authored with. The view is
non-owning, so `entries()` on a temporary dangles, as with any view.

The iterator models `std::forward_iterator`, so it composes with `std::views` if
you include `<ranges>` yourself — the header doesn't:

```cpp
#include <ranges>

for (auto [color, style] : styles.entries()
                         | std::views::filter([](auto e) { return e.value.thickness > 1; }))
    use(color, style);
```

A **common use case** of `entries()` is reverse lookup — parsing a string id
back to its enum. It is deliberately not an API: hand-rolled, *you* choose the
probe type, the projection, and the miss type (here `std::optional`, included
by you):

```cpp
constexpr std::optional<Color> color_from_name(std::string_view name)
{
    for (auto [color, style] : styles.entries())
        if (name == style.name)
            return color;
    return std::nullopt;
}

static_assert(color_from_name("green") == Color::Green);
static_assert(!color_from_name("mauve"));
```

Comparing through `std::string_view` makes equality mean *content*, and
[`emap::all_unique`](#proving-uniqueness-beyond-keys) can prove the answer is
unique — so the first match is *the* match, by proof rather than by hope.

Iterating the map directly gives **values only**, in enum order. `key_at(i)`
recovers the key for a single slot in O(1), callable on an instance or on the
type:

```cpp
static_assert(styles.key_at(0) == Color::Red);
```

`keys()` iterates the keys themselves, in enum order — the third of the three
iterations. It is `static`, like `key_at`: the keys are a property of the type,
so no instance is needed (though calling it on one works too), and the view
cannot dangle. The iterator models `std::forward_iterator` and composes with
`std::views`, like `entries()`:

```cpp
for (Color c : emap::total_map<Color, Style>::keys())
    use(c);
```

`begin()/end()`, `cbegin()/cend()`, `data()`, and `size()` are all available;
`operator[]`, `entries()`, and the iterators come in const and mutable forms.

Maps compare with `==`/`!=` whenever `V` does — equality is over values, slot
for slot, so authoring order is unobservable: the same rows in any order build
equal maps. A `V` with no `operator==` leaves the map non-comparable rather
than ill-formed.

### Sentinels spelled otherwise, and enums without one

By default the count comes from a trailing `Count` enumerator. Three ways to
override that, on two axes — a **rule** (reads the enum, so it self-maintains)
versus a **number** (hand-written, so it can go stale), and a whole **project**
versus one **enum**:

|  | a rule | a number |
|---|---|---|
| **whole project** | `enum_count_policy` | — |
| **one enum** | `enum_count`, reading that enum's sentinel | `enum_count`, with a literal count |

Prefer the first that fits. Reach for the number only when there's no sentinel
to read — it's the one form that can go stale.

**A policy — a rule, for a whole project.** If your house sentinel is spelled
something else, teach it once and every enum follows. No per-enum annotation, no
macro, no build flag:

```cpp
namespace emap {
template <class E>
    requires (std::is_enum_v<E> && requires { E::Size; })
struct enum_count_policy<E>
    : std::integral_constant<std::size_t, static_cast<std::size_t>(E::Size)> {};
}

namespace app { enum class Color { Red, Green, Blue, Size }; }

constexpr emap::total_map styles{
    emap::entry{app::Color::Red, 1}, emap::entry{app::Color::Green, 2},
    emap::entry{app::Color::Blue, 3},
};
```

A policy **reads** the enum, so it self-maintains exactly like the default: add
an enumerator and `N` follows. It is **additive** — a dependency whose enums use
the stock `Count` sentinel keeps working right beside it — and it **outranks**
`Count`, so an enum carrying both spellings resolves to your policy. Put it in a
header your enum declarations include.

**A specialization reading the sentinel — a rule, for one enum.** When a single
enum spells its sentinel its own way, point the trait at it. Same shape as
specializing `std::tuple_size`. Put it directly under the enum:

```cpp
namespace app { enum class Dir { North, East, South, West, DirCount }; }

namespace emap {
template <> struct enum_count<app::Dir>
    : std::integral_constant<std::size_t, static_cast<std::size_t>(app::Dir::DirCount)> {};
}

constexpr emap::total_map degrees{
    emap::entry{app::Dir::North, 0}, emap::entry{app::Dir::East, 90},
    emap::entry{app::Dir::South, 180}, emap::entry{app::Dir::West, 270},
};
```

The `static_cast` is required, not decoration: `integral_constant`'s second
argument is a `std::size_t`, and a scoped enum won't convert to one implicitly —
`app::Dir::DirCount` bare is a compile error.

This **reads** the enum, so it self-maintains just like a policy. It's the form
for a one-off, and for a codebase whose sentinels vary per enum (`NUM_COLORS`,
`kDirCount`) — no single policy can name those. It also **outranks a policy**, so
it's how you override a project-wide rule for one enum.

**A specialization with a count — a number, for one enum.** The last resort, for
an enum with no sentinel to read at all:

```cpp
namespace app { enum class Wind { North, East, South, West }; }

namespace emap {
template <> struct enum_count<app::Wind> : std::integral_constant<std::size_t, 4> {};
}
```

You own keeping that number current as the enum grows. It's the only form that
can go stale, which is why it's last. The enum must still be contiguous from 0.

### Asserting rejection with `static_assert`

Whether a table *would* build is itself a compile-time predicate — useful for
testing the checks, or for `static_assert`-ing that a partial table is
intentionally incomplete. One concept, `emap::buildable`, taking the table
either by value or by pointer:

```cpp
// by value — cleanest, for scalar/aggregate value types
static_assert( emap::buildable<kComplete>);
static_assert(!emap::buildable<kMissingBlue>);

// by pointer — same name; works for ANY value type (std::string_view,
// const char* holding a string literal, ...). Arr must have static storage
// duration.
inline constexpr auto labels = std::array{
    emap::entry{Color::Red,   std::string_view{"red"}},
    emap::entry{Color::Green, std::string_view{"green"}},
    emap::entry{Color::Blue,  std::string_view{"blue"}}};
static_assert(emap::buildable<&labels>);
```

Which form you use is decided by your `V`, not by picking a different name. Pass
by value for scalars and plain aggregates. Pass by pointer for string-like or
other non-structural value types — the by-value form requires the array to be a
valid non-type template parameter, which `std::string_view`, `std::string`, and
string-literal `const char*` values are not.

### Proving uniqueness beyond keys

Construction proves properties of the *keys*. `emap::all_unique` is the opt-in
proof for the *value* side: that some projection of the values — a `stringId`,
a wire code, the values themselves — is collision-free across the table.
Useful whenever something outside the enum keys the data too (parsing,
serialization):

```cpp
struct Style { int thickness; const char* stringId; };

constexpr emap::total_map styles{
    emap::entry{Color::Red,   Style{1, "red"}},
    emap::entry{Color::Green, Style{2, "green"}},
    emap::entry{Color::Blue,  Style{3, "blue"}},
};

static_assert(emap::all_unique(styles,
    [](const Style& s) { return std::string_view{s.stringId}; }));
```

The projection is any callable, or a pointer to a data member
(`&Style::thickness`); `all_unique(styles)` alone checks the values
themselves. Once uniqueness is proven, a hand-rolled reverse lookup over
`entries()` is *well-defined* — the answer is unique by proof, not by hope.

The proof is **durable**: `total_map` is immutable, so a table proven unique
stays proven — for every copy, for its whole lifetime. This is also why
`all_unique` does not accept `mutable_total_map`: a table that can drift is
exactly the object a stated proof no longer covers. Prove the frozen
baseline; thaw a copy if you need a live table.

**Project string-like members to `std::string_view`** (include it yourself —
this header doesn't), so equality means content. A raw `const char*`
projection compares addresses, and constant evaluation makes that loud rather
than wrong, in compiler-divergent ways: clang refuses *any* comparison of
string-literal addresses as unspecified, while g++ and MSVC accept
distinct-content comparisons. Never a silent wrong "unique" — but only the
`string_view` form is portable, and it is also the one that says what you
mean.

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

### A runtime-tunable sibling: mutable_total_map

`emap::mutable_total_map<E, V>` (header `emap/mutable_total_map.h`, which
includes `total_map.h` — copy both files for the no-build-system install) is
the mutable sibling: same fixed key set, same storage shape, but values may
be mutated and instances assigned. **Every `mutable_total_map` begins life as
a proven table** — the header contains no validation of its own. Author the
baseline as a `total_map`, keeping every compile-time proof, then *thaw* it,
at run time if you like:

```cpp
#include <emap/mutable_total_map.h>

emap::mutable_total_map live = styles;   // thaw a proven table
live[Color::Red].thickness = 4;          // tune values at run time
if (live != styles) { /* drift against the baseline is observable */ }
```

Row and `from(fn)` authoring also work and are sugar that builds the
`total_map` first — a bad table is rejected with `total_map`'s own
diagnostics. Mutation cannot break the *key* guarantees (keys are positional
and never stored), which is why the mutable surface is safe to offer. What a
live table gives up is value proofs: `all_unique` refuses the type, and
`transform` stays on `total_map` (derive there, then thaw). There is no
conversion back from a live table to a `total_map`.

### Self-tests

The header ships with compile-time self-tests, off by default. They emit no
runtime code and cost nothing unless you ask for them.

**Check the library against your own compiler** by adding a three-line
translation unit to your project — this is `tests/selftest.cpp` in this repo:

```cpp
#define TOTAL_MAP_SELFTEST
#include <emap/total_map.h>
int main() {}
```

```
c++ -std=c++20 -Iinclude -fsyntax-only tests/selftest.cpp
```

If you build with CMake, `cmake --build build && ctest --test-dir build` runs the
same check. Build first — the self-test cells are executables, so `ctest` alone
would run stale binaries, or none at all on a fresh configure.

A clean compile means every guarantee holds on your toolchain; there is nothing
to run. This is worth doing rather than taking on faith: `total_map` leans on
`consteval`, `requires`, and CTAD-driven substitution failure — a corner of C++20
where implementations genuinely differ.

That isn't hypothetical. Wrapping the table's construction in a lambda, rather
than leaving it the outermost call in the `bool_constant` operand, is a **hard
error on g++ 13.3 and a clean `false` on clang++ 22** — same code, same standard,
opposite results. `emap::buildable` is written to stay on the portable side of
that line, and the self-tests are how you confirm your compiler agrees.

## What it does not prove

`total_map` proves your table covers `0..N-1` exactly once. **It cannot prove
that `N` is your enumerator count** — C++20 has no reflection, so `N` is trusted
input. If `N` is wrong and too small, a table covering `0..N-1` is accepted while
the enumerators from `N` onward are silently uncovered.

This is the one hole in the design, and it exists however you supply `N`:

| how you supply `N` | goes wrong when | how often that happens |
|---|---|---|
| any rule that **reads a sentinel** — the default, an `emap::enum_count_policy`, or an `emap::enum_count` pointed at one | the enumerator it reads is a **real value**, not a sentinel — `enum class Metric { Sum, Count, Mean, Max }` reads `N == 1` | only if you name a real value the same as your sentinel |
| a hand-written **number** in `emap::enum_count` | the number goes **stale** | every time anyone adds an enumerator and forgets to bump it |

A sentinel is the default precisely because it **self-maintains**: add an
enumerator and `N` follows, so the stale case cannot arise. Every override that
**reads** a sentinel keeps that property — an `emap::enum_count_policy` for a
project, or an `emap::enum_count` pointed at one enum's own sentinel. Only a
hand-written **number** can go stale, which is why it's the last resort, not the
norm.

**If `Count` means something real in your enum, specialize `emap::enum_count`**,
and put the specialization directly under the enum declaration — a trait can't be
specialized after it's been implicitly instantiated, so a use that comes first
locks in the wrong `N`. The same ordering rule applies to a policy: put it in a
header your enum declarations include.

The collision is usually **loud**: authoring the real enumerators trips the
out-of-range check, whose message names this exact suspicion and points at
`enum_count`. (The mirror case — a hand-written count gone stale *too large* —
is equally loud, from the coverage check.) It is silent only if you happen to
author exactly the first `N` enumerators — i.e. if you forget precisely the
`Count`-named one and everything after it.

Only `Count` is recognised **by default**, and deliberately so: each extra
spelling widens the chance of colliding with a real enumerator, and `COUNT` is
*more* likely to be a real value than `Count` in SQL and statistics code. One
recognised spelling keeps the guess narrow and predictable. A policy lets a
project opt into a second spelling **for itself**, without widening the guess for
anyone who didn't ask.

## Caveats

- `operator[]` checks the key's **type** at compile time, but a runtime `E`
  forged outside `0..N-1` (a cast, or a `Count` sentinel used as a live value)
  indexes out of bounds. A debug-only `assert` catches this; it compiles away
  under `NDEBUG`. Constant-expression subscripts are always fully checked.
- With no reflection in C++20, "all enumerators" is inferred from `N` +
  contiguity rather than read from the language. Under C++26 static reflection
  the `enum_count`/`Count` convention — and the trust boundary above — become
  unnecessary.

## Supported toolchains

Every push runs the self-tests, the compile-failure tests, and all three install
paths across the matrix below. The floor is where CI proves the guarantees hold,
not where they are assumed to.

| Compiler | Minimum | Verified through |
|---|---|---|
| GCC | 12 | 16 |
| Clang | 16 | 22 |
| AppleClang | 17 (Xcode 16.4) | 21 |
| MSVC | 19.44 (VS 2022) | 19.51 (VS 2026) |

Also covered: clang-cl, MinGW, libc++ as well as libstdc++, arm64 as well as
x86_64, and 32-bit x86. Every cell builds at **C++20**, **C++23** and **C++26**
(where the compiler supports it), with and without `NDEBUG`.

Older toolchains are unsupported for concrete, tested reasons rather than
caution: **GCC 11 and Clang ≤ 15** predate [P2415R2], so `entries()` does not
compose with `std::views` there — the header stays out of `<ranges>` by design,
so it cannot opt in via `view_interface` to paper over it. **GCC 10** also
rejects `std::array<entry<E, V>, N>` as a non-type template parameter, which
breaks `emap::buildable` by value.

[P2415R2]: https://wg21.link/P2415R2

## Alternatives

The general idea — a compile-time enum-indexed table with some completeness
checking — has been built many times. The distinguishing traits of `total_map`
are that it enforces **exhaustiveness and uniqueness by key** (not just element
count), lets rows be authored **in any order**, requires **no reflection** and
**no default-constructibility**, and exposes buildability as a `static_assert`.
The main other options:

| Alternative | Approach | Main differences vs. total_map |
|---|---|---|
| **magic_enum** `containers::array<E, V>` (Neargye) | Reflection-based enum-keyed array; assign by key. C++17. | No `Count` sentinel or contiguity needed, and works with any enum — sparse or negative values included. But it does **not** enforce exhaustiveness: too *many* initializers is an error, too few is silent, and the uncovered tail is value-initialized. Covering every key explicitly (via `make_array`) works with any `V`; leaving slots to the aggregate is what pulls in a default-constructibility requirement. Heavier compile-time reflection; enum values must fall in `MAGIC_ENUM_RANGE_MIN..MAX` (default `-128..127`), and widening that runs into compiler-specific `constexpr` step limits. |
| **cpp-enum-tools** `enum_array<E, V>` (mmMike) | Enum-indexed `std::array` wrapper with a compile-time size check. C++11. | Checks only that the **initializer count** equals the enumerator count. Init is **positional**, so it can't catch a duplicate key or a misordered row. Depends on Boost.Preprocessor / Boost.Optional. |
| **Better Enums** `map<E, V>` (aantron) | Map generated from a user function. C++98 core; the `constexpr` mapping function needs C++14. | Requires defining the enum through the library's `BETTER_ENUM` macro, and `map` is documented as experimental. Nothing enforces exhaustiveness — `make_map` accepts any `T(*)(E)`; the docs *suggest* a `switch` so `-Wswitch` warns, which is a convention plus a warning rather than a check. Reverse lookup is a linear scan, re-run on every call. |
| **Plain `std::array` + `static_assert`** (idiom) | A `constexpr std::array<V, N>` with `static_assert(arr.size() == N)`. | No dependencies, but **positional** and **count-only**: no uniqueness check and no protection against rows drifting out of enum order. |
| [**EnumMapper**](https://web.archive.org/web/20150701023305/http://www.codeproject.com/Articles/422503/Enum-mapping-with-compile-time-lookup) (Rolf Kristensen, CodeProject 2012) | Mapping via inheritance + `static_cast`, one base per enumerator. C++03 in style. | Bidirectional, but only the enum→value direction is compile-time checked — the reverse lookup is marked `// Unsafe mapping` in its own source and asserts at runtime. Verbose and intrusive (one base class per value); no `constexpr` or CTAD. |

**Rule of thumb:** if you want any enum reflected to string/value without a
sentinel, or your enum is sparse, reach for **magic_enum**. If you want a
hand-authored `constexpr` table where the compiler *proves* you covered every
case exactly once — by key, in any order, with zero per-lookup overhead and no
reflection — use `total_map`. Exhaustiveness is the dividing line: none of the
alternatives above enforce it by key, so a forgotten row stays silent until it
reaches you at runtime.
