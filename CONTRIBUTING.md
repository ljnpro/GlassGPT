# Contributing To GlassGPT

## Toolchain

| Tool | Version |
|------|---------|
| Xcode | 26.4+ |
| Swift | 6.2.x |
| iOS deployment target | 26.0 |
| Node.js | `>=22 <26` |
| pnpm | via Corepack |
| Python | 3.14+ |

## Getting Started

```bash
git clone https://github.com/ljnpro/GlassGPT.git
cd GlassGPT
git config core.hooksPath .githooks
open ios/GlassGPT.xcworkspace
```

For backend-specific setup, see
[docs/backend-local-development.md](/Applications/GlassGPT/docs/backend-local-development.md).

## Branch Strategy

| Branch | Purpose |
|--------|---------|
| `main` | latest released state |
| `codex/stable-5.3` | active 5.3 release line |
| `codex/feature/*` | feature or hardening work |

Create new work from `codex/stable-5.3` unless you are explicitly preparing a
different release line.

## Required Local Checks

- Full CI:

```bash
./scripts/ci.sh
```

- Common targeted lanes:

```bash
./scripts/ci.sh contracts,backend
./scripts/ci.sh ios
```

- NativeChat package test path:

```bash
cd modules/native-chat
xcodebuild -scheme NativeChat-Package \
  -destination 'platform=iOS Simulator,id=<simulator-id>' \
  test
```

## Pull Request Expectations

1. CI must pass for the affected lanes.
2. New behavior must include meaningful automated coverage.
3. Architecture and maintainability gates must stay green.
4. Documentation must stay truthful when behavior or release flow changes.
5. UI changes that affect presentation should include snapshot or equivalent
   regression coverage once the 5.3.0 snapshot path is fully in place.

## Commit Style

This repo uses Conventional Commits:

```text
feat: add staged backend promotion smoke checks
fix: stop sharing openai circuit breaker state across users
docs: rewrite architecture for 5.3.0 backend sync flow
refactor: extract shared backend conversation controller scaffolding
test: cover SSE replay last-event-id recovery
ci: gate release on todo audit evidence
```

## Notes

- Do not treat `todo.md` or `5.3.0-plan.md` as optional project notes; they are
  part of the release program for this line.
- Release publication is script-driven. Do not manually publish backend or
  TestFlight artifacts outside the release scripts.
