# Releasing

The steps to cut a release, in order. Most exist because skipping them has a
concrete failure attached — the v0.2.0 release shipped with a stale version in
the consumer test and a permanently red release gate, and had to be re-tagged.
When a step says *why*, that is the incident it prevents.

Versioning stance (also stated in CHANGELOG.md): while the major version is 0,
a **minor** bump may break. The installed package enforces exactly that —
`COMPATIBILITY SameMinorVersion` — so a consumer's `find_package(total_map
0.2.0)` refuses a 0.3.0 install. Pick the new version accordingly: API
additions or behavior changes → minor; fixes only → patch.

## 1. Branch

- [ ] `git checkout -b release-vX.Y.Z` — the ruleset requires a PR; nothing
      lands on master directly.

## 2. Bump the version — both sides, together

- [ ] `TOTAL_MAP_VERSION_MAJOR/MINOR/PATCH` in `include/emap/total_map.h`.
- [ ] `project(VERSION ...)` in `CMakeLists.txt`.

They are published to different install paths (`find_package` reads the
project version, a bare header copy reads the macros), and the configure-time
check is the only thing holding them together — a fresh `cmake -S . -B build`
must pass, and will loudly refuse a half-bump.

## 3. Roll the changelog

- [ ] Move the `[Unreleased]` entries in `CHANGELOG.md` under a new
      `## [X.Y.Z] — YYYY-MM-DD` heading; leave `[Unreleased]` empty.
- [ ] Update the compare links at the bottom (`[Unreleased]`, the new
      version's link).

## 4. Update version references the build does not check

The consumer test parses its requested version from the header since v0.2.0 —
that one self-maintains. These do not:

- [ ] README install examples: `GIT_TAG vX.Y.Z` (FetchContent) and
      `find_package(total_map X.Y.Z REQUIRED)`.
- [ ] Then grep for stragglers — this catches the next reference someone adds
      and forgets:

      git grep -n "<old X.Y.Z>" -- ':!CHANGELOG.md'

      CHANGELOG.md is excluded because history legitimately names old
      versions. Anything else that matches needs a look.

## 5. Re-mint the Compiler Explorer demo

The demo's `#include` URL references the **tag name**, so the link can be
minted and committed *before* the tag exists — it resolves the moment the tag
lands on this very commit. That is what keeps the badge inside the tagged
release rather than one commit behind it.

- [ ] Take the previous demo source (the badge link stores it — open it and
      copy, or keep `demo.cpp` around), change the raw URL's ref to
      `vX.Y.Z`, and POST it to `https://godbolt.org/api/shortener`.
- [ ] Put the returned short link in the README badge.
- [ ] Until the tag is pushed, the link 404s on the include — expected,
      transient, and the reason the tag must end up on this commit.

## 6. Verify locally

- [ ] `cmake -S . -B build && cmake --build build -j && ctest --test-dir build`
      — the configure step is what runs the version-match check.
- [ ] The consumer install paths, which is where v0.2.0 broke:

      cmake -DSOURCE_DIR=$PWD -DWORK_DIR=/tmp/consumer-work -P cmake/run_consumer_tests.cmake

      Look for `consumer will request total_map X.Y.Z (parsed from the
      header)` — it must name the NEW version.

## 7. PR, merge, tag

- [ ] Open the PR; arm auto-merge (`gh pr merge --auto --rebase`) — `ci-ok`
      is the required check and gates the whole matrix.
- [ ] After the merge, tag the **merged commit on master** (not the branch
      head — rebase-merge rewrites hashes):

      git checkout master && git pull
      git tag -a vX.Y.Z -m "vX.Y.Z: <one-line summary>"
      git push origin vX.Y.Z

- [ ] The tag push triggers the release-gate CI run. **Watch it to green.**
      A claim CI does not gate is a claim CI does not prove, and the tag run
      is the release's proof. v0.2.0's first tag run was red; the tag had to
      be moved.

## 8. Confirm the release is live

- [ ] `curl -sI https://raw.githubusercontent.com/teoboutin/total_map/vX.Y.Z/include/emap/total_map.h`
      returns 200, and the served header carries the new
      `TOTAL_MAP_VERSION_MINOR`/`PATCH`.
- [ ] The README badge's Compiler Explorer link now compiles (the include
      resolves against the fresh tag).

## 9. Afterwards, optional

- [ ] GitHub release page: `gh release create vX.Y.Z --notes-from-tag` (or
      paste the changelog section).
- [ ] Package registries (vcpkg / Conan) pin the tag's archive checksum —
      compute it only once the tag is final. If a tag ever has to move again,
      every downstream checksum breaks; prefer a patch release instead once
      anything external references the tag.
