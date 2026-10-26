# Working rules for Abbay

These apply to every change, whoever makes it: a person, an agent, or a subagent.

## Every change

1. **Branch from `develop`, PR into `develop`, squash-merge.** The PR body is the squash message
   and the only durable record, so write it as documentation: what shipped, how it was tested
   (exact counts), what is knowingly left, and what comes next.
2. **Update the feature map.** `.claude/skills/verify-abbay/features/` describes what a user can
   do. Any change to behaviour, an accessibility id (`Abbay/Core/AccessibilityID.swift`) or a
   launch argument (`Abbay/Core/LaunchArgument.swift`) updates the matching page in the same PR.
   A page that no longer matches the app is a bug.
3. **Verify live, not just with tests.** Drive the changed features in a simulator, following
   their feature-map pages (ids, launch arguments, expected evidence). Until the `verify-abbay`
   skill and its `abbay-ctl` driver exist, drive with XCUITest or `xcrun simctl`. The PR says
   which pages were updated and what was driven, with evidence. The whole map is audited
   periodically with `/maintain-verification-skill`.
4. **File every gap as an issue.** A follow-up, known gap, deferred bullet or device check that a
   PR leaves behind gets a GitHub issue before the PR merges: what, where, why it matters, and
   when it is done. The PR's known-gaps section links those issues. Check `gh issue list` first
   and comment on an existing issue rather than filing a duplicate. Nothing is left only in a PR
   body, a commit message or a chat.
5. **Screenshots for UI changes, before and after.** Before from `develop`, after from the branch:
   same simulator, same seed data, same language (pt-BR too when text changes). Commit the PNGs
   to the orphan `pr-screenshots` branch under `pr-<number>/`, never to the feature branch, and
   embed them in the PR body with
   `https://github.com/mobyleOfficial/AbbayiOS/blob/pr-screenshots/pr-<n>/<file>.png?raw=true`.
6. **Gate locally.** CI only runs SwiftLint on `develop` PRs (`.actions.yml`), and doesn't run at
   all while #145 is open. Lint, the unit suite and the UI suite must pass locally:
   `bundle exec fastlane verify`, or the same three steps by hand.

## Constraints

- **Deployment target stays iOS 17.0.** Gate newer APIs with `@available`; never raise the floor.
- **Keep the `@escaping` closures in the LibriVox download layer** (`handleBackgroundEvents`,
  `onAdded:`). Do not convert them to async/await.
- **No AI attribution** in commits or PR bodies: no `Co-Authored-By` trailer, no "Generated
  with" line.
- **Strings in two languages.** Every user-visible string goes in
  `Abbay/Resources/Localizable/Localizable.xcstrings` with `en` and `pt-BR`.

## Practicalities

- Put worktrees under the repo (`.worktrees/` or `.claude/worktrees/`), never under `/tmp`:
  `/tmp` is a symlink, and XcodeGen then adds `AbbayTests/Info.plist` as a resource, which breaks
  the test build.
- When several runs share the Mac, give each its own simulator and pass
  `-parallel-testing-enabled NO`. Parallel testing leaves simulator clones in
  `~/Library/Developer/XCTestDevices` that fill the disk.
- Check a device build before handing it out: `otool -L` on every binary in the `.app` must show
  only `@rpath` and system paths. Simulator builds hide a bad install name (#142).
  `Scripts/check-app-binary <.app|.xcarchive|.ipa>` does this plus the entitlement,
  bundle-metadata (version keys, package types) and Debug-resource checks (`--allow-debug-resources` for Debug builds).
