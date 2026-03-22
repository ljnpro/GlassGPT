# CI Baseline Update Playbook

## Purpose

Use this playbook when a code change intentionally moves a UI surface, alters
runtime presentation, or changes release infrastructure output. The goal is to
update the right baselines once, in the right order, and finish with clean
local and remote logs instead of rediscovering the same failures one gate at a
time.

## Rule Zero

Do not start from `git push`.

First make the local branch clean enough that:

- targeted regressions already pass
- full local CI can pass
- every generated log is readable and quiet

Only then move on to TestFlight or GitHub Actions.

## What To Update

### Runtime or presentation changes

Examples:

- reasoning/waiting/completed visibility
- recovery or relaunch UI state
- detached streaming or message bubble structure

Required follow-up:

- update focused Swift tests for the decision or presentation resolver
- update any view-hosting snapshots that intentionally changed
- rerun the relevant UI scenario if the change is user-visible

### Settings, history, or chat layout changes

Examples:

- new controls
- shorter copy
- keyboard dismissal behavior
- accessibility contrast or clipping fixes

Required follow-up:

- targeted UI tests for the changed flow first
- targeted accessibility audit if the change affects visible text or controls
- snapshot refresh for every affected settings/history/chat reference image
- hosted snapshot refresh if `ViewHostingCoverageTests` moved

### Infrastructure or release-log changes

Examples:

- `scripts/ci.sh`
- `release_testflight.sh`
- log sanitizers
- GitHub workflow shell/runtime changes

Required follow-up:

- `release-readiness`
- the affected gate directly
- a final full CI run once the focused gate is stable

## Recommended Local Order

1. Confirm the failure is real by reading the current source and the failing
   `.xcresult` or log.
2. Fix the product or script root cause.
3. Run the narrowest relevant test or gate.
4. If the UI intentionally changed, refresh only the affected snapshot
   references.
5. Re-run the affected gate until it is stable.
6. Run `./scripts/ci.sh all`.
7. Read every file in `.local/build/ci`, not only the failed ones.
8. Check every generated `.xcresult` summary for:
   - `failedTests = 0`
   - `skippedTests = 0`
   - `expectedFailures = 0`

## Snapshot Refresh Checklist

When a UI change is intentional, update all impacted references in both places:

- `modules/native-chat/Tests/NativeChatTests/__Snapshots__/SnapshotViewTests`
- `modules/native-chat/Tests/NativeChatSwiftTests/__Snapshots__/ViewHostingCoverageTests`

Do not stop after the first snapshot suite passes. Hosted snapshots often catch
the same change through a different rendering path.

## Log Quality Standard

Passing is not enough. A release-quality local run must have:

- `0` warnings
- `0` errors
- `0` skipped tests
- `0` expected failures
- `0` repeated completion lines
- `0` missing-tool noise
- `0` simulator or script spam that can be removed from successful logs

If a line is benign but avoidable, treat it as debt and remove it before
release.

## Remote Flow

After the local run is clean:

1. Release from a clean worktree.
2. Push the stable branch and tag.
3. Watch the GitHub Actions run to completion.
4. Download and read every remote job log.
5. Apply the same zero-noise standard remotely.

If remote CI is noisy or flaky, fix it locally, commit, push again, and repeat.
