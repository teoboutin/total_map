# Changelog

All notable changes to this project are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project adheres to [Semantic Versioning](https://semver.org/): while
the major version is 0, a **minor** bump may break — which is also what the
installed package declares (`COMPATIBILITY SameMinorVersion`), so
`find_package` enforces it.

## [Unreleased]

### Changed

- **Breaking:** `total_map` is now fully immutable after construction. The
  non-const `operator[]`, `begin()`/`end()`, `data()` and `entries()`
  overloads are gone, and assignment is deleted (copy/move construction
  stay). An `emap::all_unique` proof therefore holds for every instance's
  whole lifetime. Migration: in-place value mutation moves to the new
  `emap::mutable_total_map` (thaw the table: `emap::mutable_total_map live =
  frozen;`); wholesale reassignment becomes construction of a new table.
- CI gains a `ci-ok` aggregate job — the single status check the branch
  ruleset requires, so a red job anywhere in the matrix blocks the merge.

### Added

- `emap::mutable_total_map<E, V>` — the runtime-tunable sibling, in its own
  header `emap/mutable_total_map.h` (bare-copy installs now copy both files;
  the new header reaches its sibling via a quote-form include). It never
  validates anything itself: the primary constructor thaws a proven
  `total_map` (constexpr, so at run time too), and row/array/`from(fn)`
  authoring delegate to `total_map`, keeping validation and diagnostics in
  one place. Full mutable surface, plus heterogeneous `==`/`!=` against a
  `total_map` baseline for drift checks. Deliberately absent: `transform`,
  any conversion back to `total_map`, and `all_unique` eligibility.
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
- `emap::bijection<E1, E2>` — a proven bijection between two same-sized
  enums, in its own header `emap/bijection.h`. IS-A `total_map<E1, E2>`;
  construction additionally proves no E2 value repeats (equal counts are a
  `static_assert`), which licenses `inverse()` — the whole map read the
  other way, materialized at compile time with no re-check — and
  `inverse_at(E2)`, the runtime single-slot form, total so it returns by
  value. `bijection<E, E>` is a proven permutation. Acceptance is again a
  predicate: `emap::bijective<Arr | &Arr>`, subsuming `buildable`.
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

## [0.2.0] — 2026-07-17

### Added

- `operator==`/`!=` over values, slot for slot. Conditionally present: a `V`
  with no `operator==` leaves the map non-comparable rather than ill-formed.
- `total_map<E, V>::from(fn)` — derive the table from a function of the key;
  total by construction, nothing to validate. The callable must return exactly
  `V` (cvref aside); `from()` performs no conversions.
- `keys()` — iterate the keys themselves, in enum order. Static, like
  `key_at`; the view cannot dangle, and it composes with `std::views`.
- `transform(fn)` — derive a table from a table by mapping each value; the
  value type may change (`U` deduced from `fn`).
- `emap::all_unique(map, projection)` — opt-in compile-time proof that a
  projection of the values (a stringId, a wire code, or with the one-argument
  overload the values themselves) is collision-free. Project string-like
  members to `std::string_view` so equality means content.

### Fixed

- The header now builds under **`-fno-exceptions`**: consteval rejections are
  reported by calling a declared-but-undefined function instead of `throw`,
  which was ill-formed under that flag even for valid tables. CI gates this on
  GCC, Clang and em++/wasm.
- The `find_package` consumer test no longer hard-codes a version that goes
  stale on release; it is parsed from the header and must match exactly.

### Documentation

- Live [Compiler Explorer demo](https://godbolt.org/z/9K375b7d1) linked from
  the README badge, pinned to the release tag.
- Hand-rolled reverse lookup documented as a common use case of `entries()` —
  deliberately an example, not an API.
- `docs/reflection-prototype-notes.md`: findings from a working C++26 (P2996)
  reflection prototype, and why reflection support will be a parallel feature
  rather than an extension of `total_map`.

## [0.1.0] — 2026-07-15

### Added

- Initial release: `emap::total_map<E, V>`, a single-header C++20
  compile-time-checked total map from an enum to values. Construction refuses
  to compile unless every enumerator is covered exactly once; rows may be
  authored in any order; keys are validated, then dropped. `entries()`
  iteration, `key_at()`, `emap::buildable`, the `enum_count` /
  `enum_count_policy` customization tiers, in-header self-tests, and the
  full CI matrix (GCC, Clang, AppleClang, MSVC, clang-cl, MinGW, em++;
  libstdc++ and libc++; x86-64, x86, arm64; C++20/23/26).

[Unreleased]: https://github.com/teoboutin/total_map/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/teoboutin/total_map/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/teoboutin/total_map/releases/tag/v0.1.0
