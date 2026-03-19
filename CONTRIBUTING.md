# Contributing to GlassGPT

Thank you for your interest in contributing to GlassGPT. This guide covers
everything you need to get started.

## Prerequisites

| Tool    | Version       |
|---------|---------------|
| Xcode   | 26+           |
| Swift   | 6.2.4         |
| iOS target | 26.0       |
| Python  | 3.14+         |

## Getting Started

```bash
git clone https://github.com/ljnpro/GlassGPT.git
cd GlassGPT
open ios/GlassGPT.xcworkspace
```

Build and run the `GlassGPT` scheme on a simulator or device.

## Branch Strategy

| Branch                  | Purpose                        |
|-------------------------|--------------------------------|
| `main`                  | Latest release                 |
| `codex/stable-4.9`      | Active stable release line     |
| `codex/feature/*`       | Feature branches               |

Create feature branches from `codex/stable-4.9`. Target your pull requests
back to that branch unless you are shipping a hotfix to `main`.

## Pre-commit Hooks

Enable the project hooks before your first commit:

```bash
git config core.hooksPath .githooks
```

## Pull Request Requirements

1. **All required CI gates pass.** The tracked path covers lint, format, build,
   architecture, tests, coverage, maintainability, source-share, infra-safety,
   module-boundary, documentation, localization, and release-readiness checks.
2. **Doc comments on every new public API symbol.**
3. **Snapshot updates** included when UI changes affect rendered output.
4. **Conventional Commits** message format (see below).

## Commit Convention

This project uses [Conventional Commits](https://www.conventionalcommits.org/):

```
feat: add model selector haptic feedback
fix: resolve SwiftData migration crash on iOS 26
docs: update architecture diagram in README
refactor: extract streaming logic into ChatStreamingCoordinator
test: add snapshot tests for MessageBubble dark mode
ci: add typed-throws gate to CI pipeline
```

## Code Style

- **SwiftLint** with 55+ active rules. Run locally:
  ```bash
  ./scripts/lint.sh
  ```
- **SwiftFormat** for consistent formatting:
  ```bash
  ./scripts/format.sh
  ```

Both tools run automatically through pre-commit hooks and CI.

## Testing

- New code must add meaningful automated coverage for the ownership boundary it changes.
- Run the full CI suite locally:
  ```bash
  ./scripts/ci.sh
  ```
- Run a specific gate:
  ```bash
  ./scripts/ci.sh maintainability
  ```
- Record snapshot baselines after UI changes:
  ```bash
  ./scripts/record_snapshots.sh
  ```

## Reporting Issues

Open an issue on GitHub with a clear description, steps to reproduce, and
the iOS / device version you are running.

## Code of Conduct

All participants are expected to follow the project Code of Conduct.
