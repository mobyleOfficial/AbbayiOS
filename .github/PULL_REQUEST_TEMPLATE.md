## What this changes

<!-- What shipped, and why. The PR body is the durable record: this repo squash-merges, so the
individual commit messages are discarded. -->

## Verification

CI runs the suites only for PRs into `main` (see `.actions.yml`). For a PR into `develop` they
are a **local** gate. Either way, run:

```bash
bundle exec fastlane verify
```

- [ ] `bundle exec fastlane verify` passes (SwiftLint `--strict`, unit suite, UI suite)
- [ ] Paste the suite totals below, so the numbers are on the record

```
UNIT: <result> | total: <n> passed: <n> failed: <n>
UI:   <result> | total: <n> passed: <n> failed: <n>
```

<!-- If a suite was not run, say which and why. "Docs only, no Swift changed" is a fine reason;
silence is not. -->

## Knowingly left unfixed

<!-- Anything deliberately out of scope, with the issue number where one exists. -->
