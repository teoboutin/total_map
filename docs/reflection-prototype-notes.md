# Reflection prototype — findings and decision

*July 2026. A working prototype of a P2996-reflection-backed `enum_count` was
built against the shipped header (pinned at `2e6b8f5`) and tested on the two
implementations that exist. This note records what was learned and why the
result is **not** being merged into `total_map`.*

**Decision: reflection support will be a parallel feature, not an extension of
the shipped `total_map`.** The shipped design exists to *circumvent* the lack
of reflection — the sentinel convention, the `enum_count` tiers, and the
documented trust boundary are all workarounds for not being able to ask the
language what the enumerators are. Retrofitting ground truth under those
conventions turned out to be brittle in ways that are structural, not
incidental (see findings). A reflection-native map, designed with no sentinel
convention at all, belongs beside this one — like the sparse-enum variant
would — not inside it.

## What was prototyped

Three inserts into the shipped header (~60 lines total), plus tests:

1. A gate on `__cpp_impl_reflection` / `<meta>`.
2. A new **lowest** `enum_count` tier: enums claimed by no existing tier
   (no `Count`, no policy, no specialization) get N derived from
   `std::meta::enumerators_of(^^E)`.
3. One `static_assert` inside `total_map`: whatever tier produced N, it must
   agree with the reflected enumerators
   (`detail::count_matches_reflection<E>(N)`).

Live demo (both compilers, side by side): https://godbolt.org/z/MMh4nGG1o

### Results

| Variant | g++ 13, C++20 (gate off) | GCC trunk `-freflection` | clang-p2996 |
|---|---|---|---|
| Positive tests | compiles, shipped behavior | pass | pass |
| `Metric` (`Count` is a real value, one-row table) | **silent** — the documented hole | rejected, named diagnostic | rejected |
| Stale hand-written count (5 enumerators, count says 3) | **silent** — the documented hole | rejected | rejected |

The mechanism works. The reasons not to ship it are below.

## Findings

**1. The gate cannot be trusted yet.** GCC trunk is conforming
(`-std=c++26 -freflection` defines `__cpp_impl_reflection` and
`__cpp_lib_reflection`). Bloomberg's clang-p2996 fork implements the feature
but defines *neither* macro — the prototype needed a manual
`TOTAL_MAP_FORCE_REFLECTION` override. Nothing here is releasable under this
project's rule that a claim CI does not gate is a claim CI does not prove:
there is no released compiler to gate on, only trunks and forks.

**2. `enumerators_of(^^E).size()` is the wrong count.** Aliases
(`First = A, Last = C`) are enumerators too and inflate it. The correct
derivation is max underlying value + 1, with contiguity checked separately.
Any future implementation must count *values*, not *enumerators*.

**3. One ambiguity is unclosable while the sentinel convention exists.** The
verifier must tolerate a surplus enumerator whose value is exactly N — that is
what "trailing sentinel" *means* — so a hand count stale by exactly one, whose
extra enumerator lands on N, still passes. Stale by more, and every
`Metric`-style collision, is caught. Reflection supplies facts; a sentinel is
a *convention about intent*; reconciling the two requires heuristics. This is
the structural brittleness: every wrinkle found traces back to it.

**4. The tier claims enums it shouldn't.** `enum class Lane { Left, Right,
LaneCount }` with no policy is today a loud "teach me the count" error — the
right prompt. Under the reflection tier it is silently claimed with N = 3,
demanding a row for `LaneCount`: loud, but wrong in intent. Avoiding that
means guessing which trailing enumerators are sentinel-*shaped* — exactly the
spelling-guess game the shipped design deliberately refuses to play.

**5. Closing the hole is a breaking change (Hyrum's law).** The in-class
verification turns previously-silently-accepted tables into hard errors. Any
consumer deliberately using a too-small N as a "map over a prefix of the enum"
feature — unsupported but currently functional — breaks. Relatedly, a failing
class-scope `static_assert` is a hard error, not a substitution failure, so
`emap::buildable` on a misread enum becomes a compile error rather than a
clean `false`. Both are defensible, neither is compatible.

**6. What still holds.** Pre-reflection behavior was bit-identical throughout
(verified on g++ 13 / C++20 with the gate off, all variants). The tier order
(explicit specialization > policy > `Count` > reflection) composes without
ambiguity. The verifier itself is sound: everything it rejects is a genuine
bug.

## Shape of the parallel feature

A reflection-native map should be designed from its own premises, not this
header's workarounds:

- **No sentinel convention.** Every reflected enumerator is a key. An enum
  carrying a `Count` sentinel is simply not what the type is for (or needs a
  row for it — a design decision to make cleanly, not retrofit).
- **No `enum_count`, no tiers, no trust boundary.** N is read from the
  language. "The one thing it does not prove" ceases to exist rather than
  being patched.
- **Sparse and negative enums become possible** via a reflected key→slot
  mapping — the same reason it must be a separate type: lookup is no longer
  a plain array index, which is the shipped type's identity.

One intermediate worth considering when toolchains stabilize: an opt-in
companion header (`emap/total_map_reflect.h` or similar) offering the
*verifier only* — a consumer-placed
`static_assert(emap::reflect::consistent<E>)` — which delivers most of the
safety win with zero change to the shipped type's semantics.

## Revisit when

- P2996 ships in a *released* GCC or Clang with stable feature-test macros —
  then a CI cell can gate it.
- Until then, the prototype's inserts are reproduced below; the scratchpad
  copy is ephemeral.

## Appendix: the prototype inserts

Gate (top of header):

```cpp
#if defined(__cpp_impl_reflection) || defined(TOTAL_MAP_FORCE_REFLECTION)
#define TOTAL_MAP_HAS_REFLECTION 1
#include <meta>
#else
#define TOTAL_MAP_HAS_REFLECTION 0
#endif
```

Count + verifier + tier (after `enum_count_v`, inside `namespace emap`):

```cpp
#if TOTAL_MAP_HAS_REFLECTION
namespace detail
{
// N inferred from the reflected enumerators: max underlying value + 1.
// NOT enumerators_of(^^E).size() — aliases (First = A) would inflate that.
template <class E>
    requires std::is_enum_v<E>
consteval std::size_t reflected_enum_count()
{
    long long max_v = -1;
    for (std::meta::info e : std::meta::enumerators_of(^^E)) {
        const auto v = static_cast<long long>(std::to_underlying(std::meta::extract<E>(e)));
        if (v > max_v) {
            max_v = v;
        }
    }
    return static_cast<std::size_t>(max_v + 1);
}

// Accept iff every enumerator value lies in [0, N] and slots {0..N-1} are all
// covered; value == N is tolerated as a trailing sentinel. See finding 3 for
// the inherent off-by-one ambiguity this tolerance carries.
template <class E>
    requires std::is_enum_v<E>
consteval bool count_matches_reflection(std::size_t n)
{
    std::vector<bool> covered(n, false); // NB: needs <vector>; the prototype rode on <meta> pulling it in
    for (std::meta::info e : std::meta::enumerators_of(^^E)) {
        const auto raw = std::to_underlying(std::meta::extract<E>(e));
        if (std::cmp_less(raw, 0) || std::cmp_greater(raw, n)) {
            return false;
        }
        const auto v = static_cast<std::size_t>(raw);
        if (v < n) {
            covered[v] = true;
        }
    }
    for (std::size_t i = 0; i < n; ++i) {
        if (!covered[i]) {
            return false;
        }
    }
    return true;
}
} // namespace detail

// Tier 4 (lowest): reflection, for enums claimed by NO existing tier.
// See finding 4 for why this claims more than it should.
template <class E>
    requires (std::is_enum_v<E> && !detail::has_count_sentinel<E> &&
              !detail::has_count_policy<E>)
struct enum_count<E>
    : std::integral_constant<std::size_t, detail::reflected_enum_count<E>()> {
};
#endif // TOTAL_MAP_HAS_REFLECTION
```

Verification (inside `total_map`, after `N`):

```cpp
#if TOTAL_MAP_HAS_REFLECTION
    static_assert(detail::count_matches_reflection<E>(N),
        "emap::total_map: enum_count_v<E> disagrees with E's reflected enumerators. "
        "Either N is wrong (a sentinel that is really a live value, or a stale "
        "hand-written emap::enum_count<E> — specialize it with the true count) or "
        "the enum is not contiguous from 0.");
#endif
```

Compiler invocations that exercised it:

```
g++ (trunk)      -std=c++26 -freflection
clang (p2996)    -std=c++26 -freflection-latest -DTOTAL_MAP_FORCE_REFLECTION
g++ 13 (gate off) -std=c++20
```
