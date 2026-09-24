# Contributing to Miqat

Thanks for your interest! Miqat is a small app with a deliberately tiny scope,
so before opening a PR for a new feature, please open an issue first to discuss it.

## Branching

Development happens on the **`dev`** branch — it should always build and run.
`main` receives merges from `dev` and is where release tags are cut. PRs
target `dev`.

## Development setup

```bash
git clone https://github.com/HamzaSamirAmmar/miqat.git
cd miqat
xcodegen generate          # regenerates Miqat.xcodeproj (requires: brew install xcodegen)
open Miqat.xcodeproj       # then Cmd+R
```

Or drive everything through the Swift Package Manager:

```bash
swift build
swift test
```

Requirements: macOS 13+, Xcode 14+.

## Guidelines

- The single third-party dependency is
  [adhan-swift](https://github.com/batoulapps/adhan-swift) (MIT) — the
  prayer-time math. Keep everything else dependency-free.
- Match the existing Swift style; no formatting pipeline is configured.
- New user-facing strings must land in **both** `Localization` tables
  (English and Arabic) — CI-style parity tests enforce this in
  `LocalizationTests`.
- Bug fixes and small improvements: just open a PR describing the change.
- If you bump `MARKETING_VERSION` in `project.yml`, add a `CHANGELOG.md` entry.
- The bundled city database is generated — never hand-edit
  `Miqat/Resources/cities.json`; regenerate with
  `python3 scripts/build_cities.py`.

## Releasing (maintainers)

> `main` is protected — it only accepts changes via pull request. `dev` allows
> direct pushes from the maintainer but no force-pushes or deletions.

1. Open a PR from `dev` into `main` (or via CLI):
   `gh pr create --base main --head dev --fill`
2. Merge it (CI runs on the PR; no approvals required for solo merges)
3. On `main`: update `MARKETING_VERSION` + `CHANGELOG.md` via a small PR
   (or bump the version on `dev` before step 1)
4. Tag the release: `git tag vX.Y.Z && git push origin vX.Y.Z` — tags are not
   blocked by branch protection; CI builds and publishes the Release
5. Update the Homebrew cask with the new version + SHA256
