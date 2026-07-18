# total_map: proof-carrying refinements — design spec & work plan

Status: keyed_map shipped (commit `Add emap::keyed_map, the id-proven sibling`).
This document is the converged design for the remaining work, written for a
fresh implementation session on this repo. It records decisions **with their
rationale** so they are not relitigated, the codebase conventions that every
new file must follow, and the measured compiler facts that already forced one
design change. Read the whole document before writing code; read
`include/emap/total_map.h` top to bottom before writing anything — it is the
style and machinery reference for everything below.

---

## 1. Goal

Generalize total_map's compile-time totality proof to the other function
properties — injectivity, surjectivity, bijectivity — and use them to build
proven value↔value lookup. Each property is checkable only if a side of the
map has the right structure:

| property     | prerequisite                                   | status |
|--------------|------------------------------------------------|--------|
| totality     | enumerable domain (`enum_count`)               | done — `total_map` |
| injectivity  | constexpr equality on a projection of V        | done — `all_unique` (predicate), `keyed_map` (type) |
| surjectivity | enumerable codomain (enum, or declared set)    | next — `bijection` covers the enum case |
| bijectivity  | totality + injectivity + `count<E1>==count<E2>`| next |

For finite equal-sized sets, total + injective implies surjective, so
`bijection` never checks surjectivity separately.

## 2. Design principles (settled — do not reopen)

1. **Predicate + refinement, not property tags.** Consteval predicates answer
   "does this table have property P" (`all_unique`, `buildable`, `keyable`);
   thin refinement **types** carry the proof and expose exactly the
   operations the proof licenses. No `basic_map<E, V, props...>`.
2. **Every public operation is a claim; smaller surface = smaller proof
   burden.** YAGNI throughout: deliver minimal functionality first, extend
   later if needed. Deferred features are listed in §5 Step 4+ — do not
   implement them now.
3. **Checks happen at construction of exactly one type; combinators are
   check-free by signature.** `join`'s constraints ARE its proof — its body is
   array walks. Never add "convenience" overloads taking raw arrays to a
   combinator; that reintroduces checking at the wrong layer.
4. **Immutable is the default; mutation is the opt-in exception**
   (`mutable_total_map`). Every refinement type builds on the immutable
   `total_map` only — a proof over mutable values is a contradiction. No
   refinement accepts or converts from `mutable_total_map`.
5. **A refinement type must earn its existence with at least one operation
   impossible without the proof.** `keyed_map` → `find`; `bijection` →
   O(1) total `inverse`. Plain surjectivity unlocks little → predicate only,
   deferred.
6. **Partial lookups are honest in the signature.** `find` returns a const
   pointer, nullptr on miss. Total lookups get `operator[]`. Nothing else.
7. **Vocabulary** (matches the codebase — this overrides earlier drafts of
   the design that said "key" for projected identities):
   - **key** = an enumerator of E. Validated at construction, then dropped;
     recoverable positionally (`key_at`).
   - **id** = the projection of a value; the value's identity within a table
     (`keyed_map::id_type`, `find(id)`).
   - **promote** = constructing a refinement from an already-proven weaker
     type. **thaw** = total_map → mutable_total_map (existing).

## 3. What exists (baseline for the next session)

On master + the keyed_map commit:

- `emap::total_map<E, V>` — immutable, consteval-checked total/unique/sized;
  `entry`, `entries()`, `keys()`, `key_at`, `from(fn)`, `transform`,
  conditional `==`, `buildable<Arr|&Arr>`, `enum_count` machinery,
  `emap::error::` reporting mechanism, `all_unique(m[, proj])`,
  `detail::project` (callable or member pointer, no `<functional>`).
- `emap::mutable_total_map<E, V>` — thaw-only sibling; no validation of its
  own; refused by `all_unique`.
- `emap::keyed_map<E, V, Proj = identity_projection{}>` — public inheritance
  from `total_map<E, V>`; consteval id-distinctness check at construction;
  implicit consteval **promote** ctor from `total_map` plus row/array sugar
  delegating through it; `id_type`; `constexpr const V* find(const id_type&)`
  (O(N) scan); no `from()` (promote composes:
  `keyed_map<E,V,P>{total_map<E,V>::from(fn)}`); `emap::keyable<X, Proj>`
  concept subsuming `buildable`; `emap::identity_projection`;
  errors `duplicate_value` (identity default) and
  `values_collide_under_projection` (real projection), both templated on the
  two colliding slots.

## 4. Measured compiler facts (constraints, not preferences)

- **g++ 13.3 does not print evaluated runtime arguments** in
  constant-evaluation failure notes; only the source line via caret echo.
  Therefore diagnostic payloads that must reach the user (colliding slots)
  ride **template arguments** of the `emap::error::` function — part of the
  instantiated name, on the diagnostic-text channel, surviving without caret
  echo. Consequence: any check wanting slot-carrying diagnostics must be
  **unrolled over `index_sequence`** — a loop variable cannot be a template
  argument. Follow this pattern for bijection's checks.
- Message literals must **start on the physical line of the `error::` call**
  (clang echoes only the caret's line); the negative-test substring must lie
  within that first line. `cmake/NegativeTests.cmake` documents this.
- In `buildable`-style concepts, the **construction must be the outermost
  call** in the `bool_constant` operand; only the argument may go through a
  helper. Wrapping the construction in a lambda is a hard error on g++ 13.3
  and a clean false on clang 22 (documented in total_map.h). `keyable`
  already follows this; `bijective` (below) must too.
- Clang/MSVC rendering of the templated error names is **unverified** —
  negative tests pin only the one-line message substrings, so CI passes
  regardless, but check the CI logs once and adjust the doc claims in
  keyed_map.h if a toolchain renders nothing useful.

## 5. The work, in order

Each step ships alone, fully tested. Do not start a step before the previous
one is green through the full suite.

### Step 2 — `emap::bijection<E1, E2>` (new header `include/emap/bijection.h`)

**What it is.** A proven bijection between two counted enums. IS-A
`total_map<E1, E2>` (public inheritance, like keyed_map): totality of E1→E2
comes from the base; the header adds (a) `static_assert(enum_count_v<E1> ==
enum_count_v<E2>)` with a friendly message, and (b) an injectivity check on
the stored E2 values — which, with equal counts, proves bijectivity.
The injectivity check is structurally keyed_map's check with the identity
projection over `V = E2`; do NOT inherit from `keyed_map<E1, E2>` for it —
the diagnostic must be bijection's own (see below) and keyed_map would drag
in `id_type`/`find` vocabulary that means something else here. Write the
unrolled walker AGAIN in bijection.h (a ~20-line twin of keyed_map's
`check_against_earlier`/`check_all`), with a comment naming the twin —
decided, do not factor a shared `detail::` helper: the walker's shape is
pinned by the measured template-argument constraint (§4), so the twins
cannot drift apart in substance, and locality preserves the include story
(keyed_map.h and bijection.h each depend on total_map.h alone; a shared
helper would either bloat total_map.h with refinement-only machinery or
make one refinement include the other for vocabulary it must not expose).

**The operation the proof licenses: `inverse()`.** Returns
`bijection<E2, E1>`, O(1) both ways, materialized as a reversed
`std::array` at consteval time.

**The open question from the design discussion, now decided — resolve it this
way:** a check-free `inverse()` needs a construction path that bypasses
validation, a new kind of door in a library where every constructor proves.
Open the door **privately and tag it**: a private consteval constructor
taking a `struct proven_inverse_t {}` tag plus the forward map, befriending
`bijection<E2, E1>`. Rationale: the inverse of a proven bijection is proven
by the same evidence — re-checking would imply the proof is doubted, and the
private tag keeps the door invisible to users, so the public invariant
("every reachable constructor proves") survives. Document this reasoning in
the header at the door itself. If mutual friendship between
`bijection<E1,E2>` and `bijection<E2,E1>` hits a toolchain problem, fall back
to re-running the check in inverse() (it cannot fail; cost is compile time
only) and record the measurement in a comment.

Two implementation notes that keep the door small. First, the BASE needs no
new door: `total_map::from(fn)` is already the check-free totality path (a
function cannot lie), so the tag constructor initializes its base with
`total_map<E2, E1>::from` over the forward map's `inverse_at` (O(N²) at
consteval — nothing at enumerator counts), skipping only the injectivity
RE-check — total_map itself is not opened.
Second, spell the friendship `template <class, class> friend class
bijection;` — all specializations, one line, fully portable — which
dissolves the mutual-friendship toolchain risk outright (keep the fallback
above recorded in case). `E1 == E2` makes this self-friendship, which is
harmless — and `bijection<E, E>` (a permutation) is a legal, useful
instance of the type, not an edge to reject: the count static_assert holds
trivially and inverse() returns the same type.

**Also license:** `constexpr E1 inverse_at(E2) const` — single-slot inverse
lookup without materializing the whole inverse map (assert-guarded like
`operator[]`, since a forged E2 indexes out of bounds). Total, so it returns
by value, no pointer.

**Deliberately absent (defer):** `compose`, `identity<E>()`, any
`bijection ∘ total_map` precomposition helper — until `join` needs them or a
user asks. `inverse()` and `inverse_at` are the whole surface.

**Diagnostic.** One new error:
`template <std::size_t FirstSlot, std::size_t SecondSlot> void
enum_value_repeated(const char* why);` — first line contains the substring
`enum value repeated` (distinct from total_map's `duplicate enum key`: here
the *values* are enumerators of E2 and one is hit twice, so some E2 value is
also necessarily missed — say so in the message). The count-mismatch case is
a `static_assert`, not an `error::` call — it is a property of the types, not
of the rows. Resolved consequence (do not rediscover it): a class-scope
static_assert fires at implicit instantiation of the TYPE, outside any
immediate context, so `bijective<X>` on mismatched-count rows and any
`std::is_constructible_v` probe are HARD ERRORS, not `false`. Accepted, with
precedent — total_map's own E/V static_asserts behave the same way, and
buildable documents comparable hard-error edges (NTTP validity). Keep the
friendly static_assert, document this edge in the header next to
`bijective`, and cover the rejection with the negative test alone.

**Construction surface** (mirror keyed_map exactly): implicit consteval
promote from `total_map<E1, E2>`; array + variadic sugar delegating through
it; deduction guides; no `from()`.

**Predicate.** `emap::bijective<X>` mirroring `keyable` (both passing forms,
outermost construction, subsumes `buildable`).

**Tests.**
- Inline selftests (fresh type names — existing selftest enums are
  `Color/Style`, `Stat`, `Hue`, `Gauge`, `Tone`, `Bare`, `Odd`, `Lane`,
  `Chan`, `Gem/Spec`; pick unused ones): round-trip
  `b.inverse()[b[e]] == e` for all keys; `inverse().inverse()` type and value
  identity; a `bijection<E, E>` permutation (same enum both sides —
  exercises self-friendship; e.g. a successor cycle, with `inverse_at`
  agreeing with the predecessor); CTAD; IS-A total_map (+ `all_unique`
  accepts, `==` reaches through); immutability; `bijective`
  true/false/subsumes-buildable; count-mismatch rejection via negative test
  only (resolved above: the class-scope static_assert makes every
  concept/trait probe a hard error, so a `false` is not expressible).
- `tests/selftest_bijection.cpp` driver (three-line, like the others).
- Negative tests: `bijection_repeated_value.cpp` (expect
  `enum value repeated`), `bijection_count_mismatch.cpp` (expect a distinct
  static_assert substring), `bijection_missing_enumerator.cpp` (delegation,
  expect `enum value not covered`).
- Wire into `CMakeLists.txt` (selftest executable + FILE_SET) and
  `cmake/NegativeTests.cmake`; extend `tests/consumer/consumer.cpp` with a
  runtime `inverse_at` use.

### Step 3 — `emap::snapshot_map<K, V, N>` + `emap::join` (new header `include/emap/snapshot_map.h`)

**What it is.** The library's first non-enum-indexed table: a fully immutable
value-owning snapshot with proven-distinct keys of arbitrary literal type K.
Parallel arrays `std::array<K, N> keys_; std::array<V, N> values_;` — slot i
IS the association (echoes "no stored keys": nothing can disagree with its
slot). Not user-constructible in v1: **`join` is its sole producer**, so
every snapshot descends from proven parts. Everything const:

- `constexpr const V* find(const K&) const` — linear scan, nullptr on miss.
  **No `operator[]`**, no mutable path, no iteration in v1 beyond what a
  test needs (if iteration is added for tests, entries-style const view
  only). No sorted/binary-search path (invisible optimization, defer).
- `size()`, and that is essentially all.

Mirror total_map's static_asserts against snapshot_map's own name (K and V
copy-constructible; K's equality bar is guaranteed upstream by keyed_map's
`projects_comparably`, but assert it here anyway so a future direct
constructor cannot regress the diagnostic). Copy CONSTRUCTION is kept and
assignment deleted, like every immutable type in the library — join returns
by value, which needs the copy/move constructors anyway.

**`join`** — a consteval free function:

```cpp
template <class E1, class V1, auto P1, class E2, class V2>
consteval snapshot_map<projected-id-of-P1-over-V1, V2, enum_count_v<E1>>
join(const keyed_map<E1, V1, P1>& a,
     const bijection<E1, E2>& b,
     const total_map<E2, V2>& m2);
```

Semantics: for each E1 key `e`, the snapshot pairs `P1(a[e])` (the id) with
`m2[b[e]]` (the value). **No validation in the body** — the signature is the
entire proof (principle 3). Be precise about which argument proves what: the
snapshot's KEY distinctness comes from `a` ALONE (the keys are a's projected
ids), and its coverage from the totality of all three arguments. The
snapshot would be VALID with any total `total_map<E1, E2>` bridge — b's
injectivity and the count equality are never consumed by the validity
argument. `bijection` is demanded anyway, and the demand is SEMANTIC: it
guarantees the snapshot is exactly `m2` re-keyed by a's ids — every row of
m2 represented exactly once, nothing dropped, nothing duplicated, where a
merely-total bridge could hit one E2 row twice and silently miss another.
State this guarantee, and that it is the reason for the strong signature, in
the header where join is documented; do NOT present bijectivity as needed
for key distinctness — that claim is false, and a reader who checks it will
stop trusting the register. V2 values are **copied** (self-contained on the
value side, may outlive inputs — scoped by the id-aliasing caveat below).
Accepting a `keyed_map` / `bijection` argument also accepts anything
derived — fine; accepting `mutable_total_map` anywhere is impossible by
signature — verify with a selftest concept check.

**Id-aliasing caveat (goes in the header).** "Self-contained" is scoped to
the VALUES. The snapshot's KEYS are projected ids, and the flagship id form
is `std::string_view`, which aliases storage it does not own: ids pointing
into string literals or a namespace-scope constexpr table are fine (static
storage), and constant evaluation keeps a genuine dangle loud — a pointer
into a vanished temporary is not a constant expression — but the header must
scope its outliving claim accordingly, in the same register as total_map's
entries()-dangling note.

Note `join` produces the snapshot through a private constructor +
friendship, same tagged-door reasoning as `inverse()` — document it there
too.

**Tests.** Selftests: a 3-enum worked example (wire enum ↔ internal enum ↔
config struct) asserting id→V2 hits/misses at compile time; runtime `find`
through the consumer test; `is_constructible` checks proving the snapshot has
no public VALIDATING constructors (copy/move construction stays — see
above), no assignment, no mutable access; a
`static_assert`-level check that join's result type is exact. Negative tests:
none needed of join itself (it cannot fail — assert that in a comment), but
keep one showing a collision is caught **upstream** at keyed_map
construction. Wire into CMake as before.

### Step 4+ — deferred (recorded so they are not accidentally half-implemented)

Explicitly out of scope until pulled by need: declared key sets
(`surjective onto &codomain`), the bijection **derived** from two keyed_maps
sharing a declared key set, `snapshot_bimap`, sorted `find`, `compose` /
`identity`, mutable `find`, direct snapshot construction, key-side
generalization beyond enums (Ix-style `index_of` trait), plain-surjectivity
predicate. Each is a pure addition later; adding any now violates §2.2.

## 6. Conventions checklist (apply to every new file)

- License header verbatim; big top doc comment in total_map.h's register
  (WHAT IT IS / INTENDED USE / CONSTRUCTION / WHAT THE PROOF LICENSES /
  DIAGNOSTICS / REQUIREMENTS & GUARANTEES), reasoning recorded, caveats
  named, CAPS for emphasis.
- Include guard `<NAME>_INCLUDED`; `#include "total_map.h"` quote-form first
  (copy-pastable emap/ directory); version macros live in total_map.h only.
- Standard-library budget: `<array> <cassert> <concepts> <cstddef>
  <type_traits> <utility>` (+`<iterator>` where views need it). **Never**
  `<functional>`, `<optional>`, `<ranges>`, exceptions. Selftest sections may
  add `<string_view>`/`<ranges>` inside the `#ifdef`.
- Rejections via declared-but-undefined `emap::error::` functions
  (-fno-exceptions story); message starts on the call's line; slot payloads
  as template arguments (unrolled checks).
- Mirror total_map's E/V static_asserts naming the new type, so diagnostics
  blame the type the user wrote.
- Deleted assignment on immutable types, with the defaulted-copy-ctor note;
  consteval construction everywhere except deliberately-runtime lookups
  (constexpr `find` / `inverse_at`).
- Selftests inline, gated on `TOTAL_MAP_SELFTEST`, self-contained fresh type
  names, plus a three-line `tests/selftest_<name>.cpp` driver.
- Negative tests: `tests/negative/<case>.cpp` with `// Expect: "substring"`
  first line; register in `cmake/NegativeTests.cmake`; substring within one
  physical line of the header.
- Add each header to the `FILE_SET HEADERS` list; extend
  `tests/consumer/consumer.cpp` with a runtime use of each new capability.
- Verify locally before declaring done: selftest TU under
  `-Wall -Wextra -Werror`, at C++20 and C++23, with and without
  `-fno-exceptions`, with and without `NDEBUG`; all negative cases rejected
  **for the expected reason**; full `cmake`+`ctest` suite green. (Watch for
  gcc `-Waddress` on constant-folded non-null pointer comparisons in
  static_asserts — assert through the dereference instead.)
- README: update once per shipped step (a section per header, in the
  existing register), or batch at the end — author's call.
- CHANGELOG.md: an entry per shipped step, in the existing entries'
  register; version macros bump per docs/releasing.md (one MINOR for the
  whole feature set or one per step — author's call, but say which in the
  shipping commit).
